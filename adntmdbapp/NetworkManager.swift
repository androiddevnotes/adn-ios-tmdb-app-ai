import SwiftUI

class NetworkManager: ObservableObject {
  @Published var movies: [Movie] = []
  @Published var currentCategory: MovieCategory = .popular
  var currentPage = 1
  var totalPages = 1
  @Published var selectedGenres: Set<String> = []
  @Published var selectedYear: Int?
  @Published var minRating: Double = 0.0
  @Published var searchQuery = ""

  let favoritesManager: FavoritesManager

  init(favoritesManager: FavoritesManager) {
    self.favoritesManager = favoritesManager
  }

  private var apiKey: String {
    if let path = Bundle.main.path(forResource: Constants.Secrets.plistName, ofType: "plist"),
      let dict = NSDictionary(contentsOfFile: path),
      let apiKey = dict[Constants.Secrets.apiKeyKey] as? String
    {
      return apiKey
    }
    return ""
  }

  private let baseURL = Constants.API.baseURL
  private let imageBaseURL = Constants.Image.baseURL

  func fetchMovies(for category: MovieCategory) {
    currentCategory = category
    currentPage = 1
    movies = []
    fetchMoviesPage()
  }

  func applyFilters() {
    currentPage = 1
    movies = []
    fetchMoviesPage()
  }

  func fetchMoviesPage() {
    guard currentPage <= totalPages else { return }
    var urlString =
      "\(baseURL)/discover/movie?api_key=\(apiKey)&page=\(currentPage)&sort_by=\(currentCategory.rawValue)"

    if !selectedGenres.isEmpty {
      let genreIds = selectedGenres.compactMap { GenreMapping.genreNameToId[$0] }.joined(
        separator: ",")
      urlString += "&with_genres=\(genreIds)"
    }

    if let year = selectedYear {
      urlString += "&primary_release_year=\(year)"
    }

    urlString += "&vote_average.gte=\(minRating)"

    guard let url = URL(string: urlString) else { return }

    URLSession.shared.dataTask(with: url) { data, response, error in
      if let data = data {
        do {
          let movieResponse = try JSONDecoder().decode(MovieResponse.self, from: data)
          DispatchQueue.main.async {
            let newMovies = movieResponse.results.map { movie in
              var updatedMovie = movie
              updatedMovie.isFavorite = self.favoritesManager.isFavorite(movie)
              updatedMovie.categoryId = self.currentCategory.rawValue
              return updatedMovie
            }
            self.movies.append(contentsOf: newMovies)
            self.currentPage += 1
            self.totalPages = movieResponse.totalPages
          }
        } catch {
          print("Error decoding JSON: \(error)")
        }
      }
    }.resume()
  }

  func searchMovies() {
    guard !searchQuery.isEmpty else {
      fetchMovies(for: currentCategory)
      return
    }

    currentPage = 1
    movies = []

    let urlString =
      "\(baseURL)/search/movie?api_key=\(apiKey)&query=\(searchQuery.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"

    guard let url = URL(string: urlString) else { return }

    URLSession.shared.dataTask(with: url) { data, response, error in
      if let data = data {
        do {
          let movieResponse = try JSONDecoder().decode(MovieResponse.self, from: data)
          DispatchQueue.main.async {
            self.movies = movieResponse.results.map { movie in
              var updatedMovie = movie
              updatedMovie.isFavorite = self.favoritesManager.isFavorite(movie)
              return updatedMovie
            }
            self.currentPage = 2
            self.totalPages = movieResponse.totalPages
          }
        } catch {
          print("Error decoding JSON: \(error)")
        }
      }
    }.resume()
  }

  func posterImage(for movie: Movie) -> some View {
    Group {
      if let posterPath = movie.posterPath {
        AsyncImage(url: URL(string: "\(imageBaseURL)\(posterPath)")) { phase in
          switch phase {
          case .empty:
            ProgressView()
          case .success(let image):
            image
              .resizable()
              .aspectRatio(contentMode: .fit)
          case .failure:
            Image(systemName: "photo")
              .foregroundColor(.gray)
          @unknown default:
            EmptyView()
          }
        }
      } else {
        Image(systemName: "photo")
          .foregroundColor(.gray)
      }
    }
  }
}
