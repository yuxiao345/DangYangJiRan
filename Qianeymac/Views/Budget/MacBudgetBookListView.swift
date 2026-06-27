import SwiftUI
@preconcurrency import CoreData

struct MacBudgetBookListView: View {
    @Environment(AppContainer.self) private var appContainer
    @Environment(\.managedObjectContext) private var modelContext
    let ledger: Ledger?
    @State private var books: [BudgetBook] = []
    @State private var showAddSheet = false
    @State private var editingBook: BudgetBook?
    @State private var showDeleteAlert = false
    @State private var bookToDelete: BudgetBook?
    @State private var selectedBook: BudgetBook?
    @State private var refreshTrigger = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("预算管理").font(.designHeadlineMedium).foregroundStyle(Color.designOnSurface)
                Spacer()
                Button { showAddSheet = true } label: {
                    Image(systemName: "plus").fontWeight(.semibold)
                }
                .buttonStyle(DesignGlassCircleButton())
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 12)

            if books.isEmpty {
                Text("暂无预算计划")
                    .foregroundStyle(Color.designOnSurfaceVariant)
                    .padding(24)
                    .frame(maxWidth: .infinity)
            } else {
                List {
                    ForEach(books) { book in
                        bookRowContent(book)
                            .contentShape(Rectangle())
                            .onTapGesture { selectedBook = book }
                    }
                    .onMove { from, to in
                        var mutable = books
                        mutable.move(fromOffsets: from, toOffset: to)
                        try? appContainer.budgetService.reorderBooks(mutable, context: modelContext)
                        load()
                        NotificationCenter.default.post(name: .transactionDidChange, object: nil)
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
            }
        }
        .frame(minWidth: 460, maxWidth: 650, minHeight: 400)
        .designScreen()
        .onAppear(perform: load)
        .onChange(of: refreshTrigger) { _, _ in load() }
        .alert("删除预算计划", isPresented: $showDeleteAlert) {
            Button("取消", role: .cancel) { bookToDelete = nil }
            Button("删除", role: .destructive) { confirmDelete() }
        } message: {
            if let b = bookToDelete {
                Text("确定要删除预算计划「\(b.name)」吗？此操作不可撤销。")
            }
        }
        .sheet(isPresented: $showAddSheet, onDismiss: { refreshTrigger.toggle() }) {
            MacAddEditBudgetBookView(ledger: effectiveLedger)
        }
        .sheet(item: $editingBook, onDismiss: { refreshTrigger.toggle() }) { book in
            MacAddEditBudgetBookView(editing: book, ledger: effectiveLedger)
        }
        .sheet(item: $selectedBook, onDismiss: { refreshTrigger.toggle() }) { book in
            BudgetBookDetailMacView(book: book)
        }
    }

    private var effectiveLedger: Ledger? { ledger ?? appContainer.currentLedger }

    private func bookRowContent(_ book: BudgetBook) -> some View {
        HStack(spacing: 8) {
            Image(systemName: book.isActive ? "bookmark.fill" : "bookmark")
                .foregroundStyle(book.isActive ? Color.designPrimaryContainer : .secondary)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(book.name).font(.designBodyMedium)
                    if !book.isActive {
                        Text("草稿")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(Color.designOnSurfaceVariant)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Capsule().fill(Color.designOnSurfaceVariant.opacity(0.12)))
                    }
                }
                Text("\(book.startDate.formatted(date: .abbreviated, time: .omitted)) — \(book.endDate.formatted(date: .abbreviated, time: .omitted))")
                    .font(.designBodyCaption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    let itemCount = book.items?.count ?? 0
                    Text("\(itemCount)个预算项").font(.designBodyCaption).foregroundStyle(.secondary)
                    let total = appContainer.budgetService.totalBudget(for: book)
                    if total > 0 {
                        CurrencyText(amount: total, currencyCode: book.ledger?.defaultCurrencyCode ?? "CNY",
                                     size: 11, foregroundColor: .designPrimaryContainer)
                    }
                }
            }
            Spacer()
            Image(systemName: "pencil")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
                .onTapGesture { editingBook = book }
            Image(systemName: "trash")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
                .onTapGesture {
                    bookToDelete = book
                    showDeleteAlert = true
                }
        }
        .padding(.vertical, 4)
        .opacity(book.isActive ? 1.0 : 0.55)
    }

    private func load() {
        guard let l = effectiveLedger else { return }
        books = (try? appContainer.budgetService.fetchBooks(for: l, context: modelContext)) ?? []
    }

    private func confirmDelete() {
        guard let book = bookToDelete else { return }
        try? appContainer.budgetService.deleteBook(book, context: modelContext)
        bookToDelete = nil
        load()
    }
}
