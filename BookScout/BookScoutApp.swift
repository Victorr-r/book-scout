import SwiftUI

@main
struct BookScoutApp: App {
    @State private var model = LibraryModel()
    var body: some Scene {
        WindowGroup { LibraryScreen(model: model).tint(.indigo) }
    }
}

struct LibraryScreen: View {
    @Bindable var model: LibraryModel
    @State private var favoritesOnly = false
    @FocusState private var searchFocused: Bool
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Ваша следующая\nлюбимая книга").font(.largeTitle.bold())
                            Text("Найдите историю. Сохраните на потом.")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 4)
                        Image(systemName: "books.vertical.fill").font(.title).foregroundStyle(.indigo)
                            .padding(12).background(.indigo.opacity(0.09), in: RoundedRectangle(cornerRadius: 18))
                            .accessibilityHidden(true)
                    }
                    HStack {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("Название или автор", text: $model.query)
                            .focused($searchFocused).submitLabel(.search)
                            .onSubmit(search)
                            .onChange(of: model.query) { _, _ in model.queryChanged() }
                        if !model.query.isEmpty {
                            Button { model.query = "" } label: { Image(systemName: "xmark.circle.fill") }
                                .accessibilityLabel("Очистить поиск").foregroundStyle(.secondary)
                        }
                    }
                    .padding(14).background(.background, in: RoundedRectangle(cornerRadius: 14))
                    HStack {
                        Picker("Раздел", selection: $favoritesOnly) {
                            Text("Поиск").tag(false)
                            Text("Избранное · \(model.favorites.count)").tag(true)
                        }.pickerStyle(.segmented)
                        if !favoritesOnly {
                            Button("Найти", action: search).buttonStyle(.borderedProminent)
                                .disabled(model.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                }.padding(20).background(Color.indigo.opacity(0.045))
                Group {
                    if favoritesOnly {
                        if model.favorites.isEmpty {
                            empty("Соберите свою полку", "Откройте книгу и нажмите на закладку. Избранное доступно без интернета.", "bookmark")
                        } else { bookList(model.favorites, caption: "ВАША КНИЖНАЯ ПОЛКА") }
                    } else {
                        switch model.state {
                        case .idle:
                            VStack(spacing: 20) {
                                empty("Что почитаем?", "Введите название или имя автора и нажмите «Найти».", "text.book.closed")
                                Button("Попробовать: Шерлок Холмс") { model.query = "Sherlock Holmes"; searchFocused = true }
                                    .buttonStyle(.bordered).padding(.bottom, 32)
                            }
                        case .loading:
                            VStack(spacing: 16) { ProgressView(); Text("Ищем в Open Library…").foregroundStyle(.secondary) }
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        case .failed(let message):
                            VStack(spacing: 18) {
                                empty("Поиск не завершён", message, "wifi.exclamationmark")
                                Button("Повторить", action: search).buttonStyle(.borderedProminent).padding(.bottom, 40)
                            }
                        case .loaded:
                            if model.books.isEmpty { empty("Ничего не найдено", "Попробуйте другое название или имя автора, в том числе на английском.", "magnifyingglass") }
                            else { bookList(model.books, caption: "НАЙДЕНО · \(model.books.count) • ДО 30 КНИГ") }
                        }
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationTitle("Book Scout").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Image(systemName: "sparkle").foregroundStyle(.indigo).accessibilityHidden(true) } }
            .alert("Избранное", isPresented: Binding(get: { model.storageError != nil }, set: { if !$0 { model.storageError = nil } })) {
                Button("Загрузить снова") { model.reloadFavorites() }
                Button("Закрыть", role: .cancel) { model.storageError = nil }
            } message: { Text(model.storageError ?? "") }
        }
    }
    private func search() { searchFocused = false; favoritesOnly = false; model.submit() }
    private func empty(_ title: String, _ text: String, _ icon: String) -> some View {
        ContentUnavailableView { Label(title, systemImage: icon) } description: { Text(text) }
    }
    private func bookList(_ books: [Book], caption: String) -> some View {
        List {
            Section {
                ForEach(books) { book in
                    NavigationLink {
                        BookDetail(book: book, model: model)
                    } label: {
                        HStack(spacing: 16) {
                            Cover(book: book).frame(width: 58, height: 82)
                            VStack(alignment: .leading, spacing: 6) {
                                Text(book.title).font(.headline).lineLimit(3)
                                Text(book.authorLine).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                                if let year = book.firstPublishYear { Text(String(year)).font(.caption).foregroundStyle(.secondary) }
                            }
                            Spacer(minLength: 0)
                            if model.isFavorite(book) { Image(systemName: "bookmark.fill").foregroundStyle(.indigo).accessibilityLabel("В избранном") }
                        }.padding(.vertical, 6)
                    }
                }
            } header: { Text(caption) } footer: { Text("Каталог и обложки: Open Library. Показаны произведения, а не отдельные издания.") }
        }.listStyle(.plain).scrollDismissesKeyboard(.interactively)
    }
}

struct Cover: View {
    let book: Book
    var body: some View {
        AsyncImage(url: book.coverURL) { image in image.resizable().scaledToFit() } placeholder: {
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(.indigo.opacity(0.08))
                Image(systemName: "book.closed").font(.title2).foregroundStyle(.indigo.opacity(0.6))
            }
        }.clipShape(RoundedRectangle(cornerRadius: 8)).accessibilityHidden(true)
    }
}

struct BookDetail: View {
    let book: Book
    @Bindable var model: LibraryModel
    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                Cover(book: book).frame(width: 160, height: 220).padding(.top, 12)
                VStack(spacing: 10) {
                    Text(book.title).font(.title.bold()).multilineTextAlignment(.center)
                    Text(book.authorLine).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    if let year = book.firstPublishYear { Text("Впервые опубликовано: \(String(year))").font(.subheadline).foregroundStyle(.secondary) }
                }
                Button { model.toggle(book) } label: {
                    Label(model.isFavorite(book) ? "Убрать из избранного" : "Сохранить в избранное",
                          systemImage: model.isFavorite(book) ? "bookmark.fill" : "bookmark")
                        .frame(maxWidth: .infinity).padding(.vertical, 6)
                }.buttonStyle(.borderedProminent)
                if let url = book.webURL {
                    Link(destination: url) { Label("Подробнее в Open Library", systemImage: "arrow.up.right.square") }
                }
                Text("Сохранённые название, автор и год доступны офлайн. Для обложки и страницы каталога требуется интернет.")
                    .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }.padding(24).frame(maxWidth: 600).frame(maxWidth: .infinity)
        }.navigationTitle("О книге").navigationBarTitleDisplayMode(.inline)
    }
}
