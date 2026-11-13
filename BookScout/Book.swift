import Foundation

struct Book: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let authors: [String]
    let firstPublishYear: Int?
    let coverID: Int?

    var authorLine: String { authors.isEmpty ? "Автор не указан" : authors.joined(separator: ", ") }
    var coverURL: URL? {
        coverID.map { URL(string: "https://covers.openlibrary.org/b/id/\($0)-M.jpg?default=false")! }
    }
    var webURL: URL? {
        guard id.hasPrefix("/works/"), !id.contains("..") else { return nil }
        return URL(string: "https://openlibrary.org\(id)")
    }
}

struct SearchResponse: Decodable {
    let docs: [Document]
    struct Document: Decodable {
        let key: String
        let title: String
        let author_name: [String]?
        let first_publish_year: Int?
        let cover_i: Int?
        var book: Book {
            Book(id: key.hasPrefix("/") ? key : "/works/\(key)", title: title,
                 authors: author_name ?? [], firstPublishYear: first_publish_year, coverID: cover_i)
        }
    }
    var books: [Book] {
        var seen = Set<String>()
        return docs.map(\.book).filter { seen.insert($0.id).inserted }
    }
}
