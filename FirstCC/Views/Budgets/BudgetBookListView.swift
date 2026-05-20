import SwiftUI
import SwiftData

// MARK: - Book List

struct BudgetBookListView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appContainer: AppContainer
    @State private var books: [BudgetBook] = []
    @State private var showAddSheet = false
    @State private var editingBook: BudgetBook?

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
                NavigationLink(destination: BudgetBookDetailView(book: book)) {
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
                loadBooks()
            } label: { Label("删除", systemImage: "trash") }
        }
            }
        }
        .navigationTitle("预算管理")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showAddSheet = true } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showAddSheet, onDismiss: { loadBooks() }) {
            AddEditBudgetBookView(ledger: effectiveLedger)
        }
        .sheet(item: $editingBook, onDismiss: { loadBooks() }) { book in
            AddEditBudgetBookView(editing: book, ledger: effectiveLedger)
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
                if !book.isActive {
                    Text("草稿").font(.designBodySmall).foregroundStyle(.secondary)
                }
            }
            Text("\(book.startDate.formatted(date: .abbreviated, time: .omitted)) — \(book.endDate.formatted(date: .abbreviated, time: .omitted))")
                .font(.designBodySmall)
                .foregroundStyle(.secondary)
            let totalBudget = appContainer.budgetService.totalBudget(for: book)
            if totalBudget > 0 {
                HStack {
                    Text("总预算:")
                        .font(.designBodySmall)
                    CurrencyText(amount: totalBudget, currencyCode: book.ledger?.defaultCurrencyCode ?? "CNY", size: 12, foregroundColor: .blue)
                    Spacer()
                    let itemCount = book.items?.count ?? 0
                    if itemCount > 0 {
                        Text("\(itemCount)项")
                            .font(.designBodySmall)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func loadBooks() {
        guard let ledger = effectiveLedger else { return }
        books = (try? appContainer.budgetService.fetchBooks(for: ledger, context: modelContext)) ?? []
    }
}
