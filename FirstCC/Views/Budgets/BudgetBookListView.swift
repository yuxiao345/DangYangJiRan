import SwiftUI
@preconcurrency import CoreData

// MARK: - Book List

struct BudgetBookListView: View {
    @Environment(\.managedObjectContext) private var modelContext
    @Environment(AppContainer.self) private var appContainer
    @State private var books: [BudgetBook] = []
    @State private var showAddSheet = false
    @State private var editingBook: BudgetBook?
    @State private var listVersion = 0

    let ledger: Ledger?
    private var effectiveLedger: Ledger? { ledger ?? appContainer.currentLedger }

    init(ledger: Ledger? = nil) {
        self.ledger = ledger
    }

    var body: some View {
        List {
            if books.isEmpty {
                Text("暂无预算计划，点击右上角 + 添加")
                    .foregroundStyle(.secondary)
            }
            ForEach(books) { book in
                NavigationLink(value: book.objectID) {
                    bookRow(book)
                }
                .swipeActions(edge: .leading) {
                    Button { editingBook = book } label: {
                        Label("编辑", systemImage: "pencil")
                    }
                    .tint(.blue)
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        try? appContainer.budgetService.deleteBook(book, context: modelContext)
                        reloadBooks()
                    } label: { Label("删除", systemImage: "trash") }
                }
            }
            .onMove { from, to in
                var mutable = books
                mutable.move(fromOffsets: from, toOffset: to)
                try? appContainer.budgetService.reorderBooks(mutable, context: modelContext)
                reloadBooks()
            }
        }
        .navigationTitle("预算管理")
        .id(listVersion)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showAddSheet = true } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel(Text("添加预算本"))
            }
            #if os(iOS)
            ToolbarItem(placement: .topBarLeading) {
                EditButton()
            }
            #endif
        }
        .sheet(isPresented: $showAddSheet) {
            AddEditBudgetBookView(ledger: effectiveLedger)
        }
        .onChange(of: showAddSheet) { _, newValue in
            if !newValue { reloadBooks() }
        }
        .sheet(item: $editingBook) { book in
            AddEditBudgetBookView(editing: book, ledger: effectiveLedger)
        }
        .onChange(of: editingBook) { _, newValue in
            if newValue == nil { reloadBooks() }
        }
        .navigationDestination(for: NSManagedObjectID.self) { id in
            if let book = modelContext.object(with: id) as? BudgetBook {
                budgetDetailDestination(for: book)
            }
        }
        .onAppear(perform: loadBooks)
    }

    private func bookRow(_ book: BudgetBook) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: book.isActive ? "bookmark.fill" : "bookmark")
                    .foregroundStyle(book.isActive ? .blue : .secondary)
                Text(book.name)
                    .font(.designBodyMedium)
                Spacer()
                Text(book.isActive ? "启用" : "草稿")
                    .font(.designBodySmall)
                    .foregroundStyle(book.isActive ? .green : .secondary)
            }
            Text("\(book.startDate.formatted(date: .abbreviated, time: .omitted)) — \(book.endDate.formatted(date: .abbreviated, time: .omitted))")
                .font(.designBodySmall)
                .foregroundStyle(.secondary)
            HStack {
                let itemCount = book.items?.count ?? 0
                Text("\(itemCount)个预算项")
                    .font(.designBodySmall)
                    .foregroundStyle(.secondary)
                Spacer()
                let totalBudget = appContainer.budgetService.totalBudget(for: book)
                if totalBudget > 0 {
                    CurrencyText(amount: totalBudget, currencyCode: book.ledger?.defaultCurrencyCode ?? "CNY", size: 12, foregroundColor: .blue)
                }
            }
        }
    }

    @ViewBuilder
    private func budgetDetailDestination(for book: BudgetBook) -> some View {
        #if os(macOS)
        BudgetBookDetailMacView(book: book)
        #else
        BudgetBookDetailView(book: book)
        #endif
    }

    private func reloadBooks() {
        listVersion += 1
        loadBooks()
    }

    private func loadBooks() {
        guard let ledger = effectiveLedger else { return }
        books = (try? appContainer.budgetService.fetchBooks(for: ledger, context: modelContext)) ?? []
    }
}
