import Foundation

protocol BookSearching: Sendable {
    func search(_ query: String) async throws -> [Book]
}

enum SearchError: Error, LocalizedError {
    case server(Int), invalidResponse
    var errorDescription: String? {
        switch self {
        case .server(429): "Слишком много запросов. Подождите немного и повторите."
        case .server: "Каталог временно недоступен. Попробуйте ещё раз."
        case .invalidResponse: "Не удалось прочитать ответ каталога."
        }
    }
}

struct OpenLibraryService: BookSearching {
    let session: URLSession
    init(session: URLSession = .shared) { self.session = session }
    func search(_ query: String) async throws -> [Book] {
        var url = URLComponents(string: "https://openlibrary.org/search.json")!
        url.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "limit", value: "30"),
            URLQueryItem(name: "fields", value: "key,title,author_name,first_publish_year,cover_i")
        ]
        var request = URLRequest(url: url.url!)
        request.timeoutInterval = 20
        request.setValue("BookScout/1.0 (portfolio iOS app)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw SearchError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw SearchError.server(http.statusCode) }
        do { return try JSONDecoder().decode(SearchResponse.self, from: data).books }
        catch { throw SearchError.invalidResponse }
    }
}
