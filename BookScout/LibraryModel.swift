import Foundation
import Observation

protocol FavoritesPersisting {
    func load() throws -> [Book]
    func save(_ books: [Book]) throws
}

struct FavoritesFile: FavoritesPersisting {
    let url: URL
    static var standard: FavoritesFile {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return FavoritesFile(url: base.appendingPathComponent("BookScout/favorites.json"))
    }
    func load() throws -> [Book] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return try JSONDecoder().decode([Book].self, from: Data(contentsOf: url))
    }
    func save(_ books: [Book]) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(books).write(to: url, options: .atomic)
    }
}

@MainActor @Observable
final class LibraryModel {
    enum State: Equatable { case idle, loading, loaded, failed(String) }
    var query = ""
    private(set) var state: State = .idle
    private(set) var books: [Book] = []
    private(set) var favorites: [Book] = []
    var storageError: String?
    private var storageLoaded = false
    private let service: any BookSearching
    private let storage: any FavoritesPersisting
    private var generation = 0
    private var searchTask: Task<Void, Never>?
    private var lastRequest: Date?

    init(service: any BookSearching = OpenLibraryService(), storage: any FavoritesPersisting = FavoritesFile.standard) {
        self.service = service
        self.storage = storage
        reloadFavorites()
    }
    func reloadFavorites() {
        do {
            var seen = Set<String>()
            favorites = try storage.load().filter { seen.insert($0.id).inserted }
            storageLoaded = true
            storageError = nil
        } catch {
            storageLoaded = false
            storageError = "Не удалось прочитать избранное. Файл сохранён без изменений. Попробуйте загрузить снова."
        }
    }
    func isFavorite(_ book: Book) -> Bool { favorites.contains { $0.id == book.id } }
    func toggle(_ book: Book) {
        guard storageLoaded else {
            storageError = "Избранное пока не загружено. Повторите загрузку, чтобы не потерять сохранённые книги."
            return
        }
        var updated = favorites
        if isFavorite(book) { updated.removeAll { $0.id == book.id } } else { updated.insert(book, at: 0) }
        do { try storage.save(updated); favorites = updated }
        catch { storageError = "Не удалось сохранить избранное. Изменения не применены. Попробуйте снова." }
    }
    func queryChanged() {
        generation += 1
        searchTask?.cancel()
        books = []
        state = .idle
    }
    /// Search is explicit, so typing never sends a request. A one-second minimum
    /// interval and cancellation protect the public API from rapid submissions.
    func submit() {
        generation += 1
        let token = generation
        searchTask?.cancel()
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { state = .idle; books = []; return }
        state = .loading
        books = []
        searchTask = Task {
            let wait = max(0, 1 - Date().timeIntervalSince(lastRequest ?? .distantPast))
            do {
                if wait > 0 { try await Task.sleep(for: .seconds(wait)) }
                try Task.checkCancellation()
                lastRequest = Date()
                let result = try await service.search(text)
                guard token == generation, !Task.isCancelled else { return }
                books = result
                state = .loaded
            } catch {
                guard token == generation, !Task.isCancelled else { return }
                state = .failed((error as? LocalizedError)?.errorDescription ?? "Проверьте подключение к интернету и повторите поиск.")
            }
        }
    }
    func waitForSearch() async { await searchTask?.value }
}
