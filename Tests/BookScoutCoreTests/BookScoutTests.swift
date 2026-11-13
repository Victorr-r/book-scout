import Foundation
import Testing
@testable import BookScoutCore

private let sample = Book(id: "/works/OL1W", title: "Book", authors: ["Author"], firstPublishYear: 1900, coverID: 123)

@Test func decodingOptionalFieldsAndDuplicateWorks() throws {
    let data = Data(#"{"docs":[{"key":"OL1W","title":"Book"},{"key":"/works/OL1W","title":"Duplicate"}]}"#.utf8)
    let books = try JSONDecoder().decode(SearchResponse.self, from: data).books
    #expect(books.count == 1)
    #expect(books[0].id == "/works/OL1W")
    #expect(books[0].authors.isEmpty)
    #expect(books[0].coverURL == nil)
    #expect(books[0].authorLine == "Автор не указан")
}

@Test func fileStorageRoundTripAndCorruption() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let storage = FavoritesFile(url: directory.appendingPathComponent("favorites.json"))
    #expect(try storage.load().isEmpty)
    try storage.save([sample])
    #expect(try storage.load() == [sample])
    try storage.save([])
    #expect(try storage.load().isEmpty)
    try Data("broken".utf8).write(to: storage.url)
    #expect(throws: (any Error).self) { try storage.load() }
}

private final class MemoryStorage: FavoritesPersisting {
    var books: [Book] = []
    var failSave = false
    var failLoad = false
    func load() throws -> [Book] { if failLoad { throw SearchError.invalidResponse }; return books }
    func save(_ books: [Book]) throws { if failSave { throw SearchError.invalidResponse }; self.books = books }
}
private struct FixedSearch: BookSearching {
    let result: [Book]
    func search(_ query: String) async throws -> [Book] { result }
}
private struct FailingSearch: BookSearching {
    func search(_ query: String) async throws -> [Book] { throw SearchError.server(429) }
}

@Test @MainActor func favoriteToggleIsPersistedAndFailureRollsBack() {
    let storage = MemoryStorage()
    let model = LibraryModel(storage: storage)
    model.toggle(sample)
    #expect(model.isFavorite(sample))
    #expect(LibraryModel(storage: storage).favorites == [sample])
    storage.failSave = true
    model.toggle(sample)
    #expect(model.isFavorite(sample))
    #expect(model.storageError != nil)
    storage.failSave = false
    model.toggle(sample)
    #expect(model.favorites.isEmpty)
}

@Test @MainActor func unreadableFileCannotBeOverwritten() {
    let storage = MemoryStorage()
    storage.books = [sample]
    storage.failLoad = true
    let model = LibraryModel(storage: storage)
    model.toggle(sample)
    #expect(storage.books == [sample])
    #expect(model.storageError != nil)
    storage.failLoad = false
    model.reloadFavorites()
    #expect(model.favorites == [sample])
}

@Test @MainActor func successEmptyAndBlankSearchStates() async {
    let model = LibraryModel(service: FixedSearch(result: [sample]), storage: MemoryStorage())
    model.query = "Book"
    model.submit()
    #expect(model.state == .loading)
    await model.waitForSearch()
    #expect(model.state == .loaded)
    #expect(model.books == [sample])
    model.query = "  \n"
    model.submit()
    #expect(model.state == .idle)
    #expect(model.books.isEmpty)
    let empty = LibraryModel(service: FixedSearch(result: []), storage: MemoryStorage())
    empty.query = "missing"
    empty.submit()
    await empty.waitForSearch()
    #expect(empty.state == .loaded)
    #expect(empty.books.isEmpty)
}

@Test @MainActor func searchErrorIsShown() async {
    let model = LibraryModel(service: FailingSearch(), storage: MemoryStorage())
    model.query = "Book"
    model.submit()
    await model.waitForSearch()
    if case .failed(let message) = model.state { #expect(message.contains("Подождите")) }
    else { Issue.record("Expected failed state") }
}

private actor ControlledSearch: BookSearching {
    var continuation: CheckedContinuation<[Book], Never>?
    func search(_ query: String) async throws -> [Book] {
        await withCheckedContinuation { continuation = $0 }
    }
    func started() -> Bool { continuation != nil }
    func finish() { continuation?.resume(returning: [sample]); continuation = nil }
}

@Test @MainActor func editedQueryRejectsLateResponseEvenIfServiceIgnoresCancellation() async {
    let service = ControlledSearch()
    let model = LibraryModel(service: service, storage: MemoryStorage())
    model.query = "old"
    model.submit()
    while !(await service.started()) { await Task.yield() }
    model.query = "new"
    model.queryChanged()
    await service.finish()
    await model.waitForSearch()
    #expect(model.state == .idle)
    #expect(model.books.isEmpty)
}

private final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let items = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
        let query = items.first { $0.name == "q" }?.value
        let status = query == "error" ? 503 : 200
        let body = query == "malformed" ? "broken" : #"{"docs":[{"key":"/works/OL1W","title":"Book","author_name":["Author"],"first_publish_year":1900,"cover_i":123}]}"#
        if query == "a & русский" {
            #expect(items.first { $0.name == "limit" }?.value == "30")
            #expect(request.value(forHTTPHeaderField: "User-Agent")?.contains("BookScout") == true)
        }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@Test func networkAdapterWithStubbedHTTP() async throws {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [StubURLProtocol.self]
    let session = URLSession(configuration: config)
    defer { session.invalidateAndCancel() }
    let service = OpenLibraryService(session: session)
    #expect(try await service.search("a & русский") == [sample])
    await #expect(throws: (any Error).self) { try await service.search("error") }
    await #expect(throws: (any Error).self) { try await service.search("malformed") }
}

private actor RetrySearch: BookSearching {
    var calls = 0
    func search(_ query: String) async throws -> [Book] {
        calls += 1
        if calls == 1 { throw SearchError.server(503) }
        return [sample]
    }
}

@Test @MainActor func retryRecoversAfterNetworkError() async {
    let model = LibraryModel(service: RetrySearch(), storage: MemoryStorage())
    model.query = "Book"
    model.submit()
    await model.waitForSearch()
    guard case .failed = model.state else { Issue.record("Expected initial failure"); return }
    model.submit()
    await model.waitForSearch()
    #expect(model.state == .loaded)
    #expect(model.books == [sample])
}
