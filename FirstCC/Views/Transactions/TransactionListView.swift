import SwiftUI
import SwiftData

struct TransactionListView: View {
    @EnvironmentObject private var appContainer: AppContainer
    @Environment(\.modelContext) private var modelContext
    @State private var transactions: [Transaction] = []
    @State private var showAddSheet = false
    @State private var filterType: TransactionType?
    @State private var selectedMonth: Date = Date()

    var body: some View {
        List {
            if transactions.isEmpty {
                Text("暂无交易记录")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(groupedByDate, id: \.key) { group in
                    Section(group.key) {
                        ForEach(group.value) { transaction in
                            NavigationLink(destination: TransactionDetailView(transaction: transaction)) {
                                TransactionRowView(transaction: transaction)
                            }
                        }
                        .onDelete { indexSet in
                            deleteTransactions(in: indexSet, from: group.value)
                        }
                    }
                }
            }
        }
        .navigationTitle("流水")
        .toolbar {
            ToolbarItem(placement: .principal) {
                monthNavigator
            }
            ToolbarItem(placement: .primaryAction) {
                Button { showAddSheet = true } label: {
                    Image(systemName: "plus")
                }
            }
            ToolbarItem(placement: .navigationBarLeading) {
                Menu {
                    Button("全部") { filterType = nil }
                    Button("支出") { filterType = .expense }
                    Button("收入") { filterType = .income }
                    Button("转账") { filterType = .transfer }
                    Button("借贷") { filterType = .lending }
                    Button("调整") { filterType = .adjustment }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddEditTransactionView()
        }
        .onAppear(perform: loadTransactions)
        .onChange(of: selectedMonth) { _, _ in loadTransactions() }
        .onChange(of: filterType) { _, _ in loadTransactions() }
    }

    private var monthNavigator: some View {
        HStack(spacing: 8) {
            Button {
                selectedMonth = Calendar.current.date(byAdding: .month, value: -1, to: selectedMonth) ?? selectedMonth
            } label: {
                Image(systemName: "chevron.left")
                    .font(.subheadline)
            }
            Text(selectedMonth.formatted(Date.FormatStyle().year(.defaultDigits).month(.abbreviated)))
                .font(.subheadline)
                .frame(minWidth: 80)
            Button {
                selectedMonth = Calendar.current.date(byAdding: .month, value: 1, to: selectedMonth) ?? selectedMonth
            } label: {
                Image(systemName: "chevron.right")
                    .font(.subheadline)
            }
        }
    }

    private var groupedByDate: [(key: String, value: [Transaction])] {
        let filtered = filterType.map { type in transactions.filter { $0.type == type } } ?? transactions
        let grouped = Dictionary(grouping: filtered) { t in
            t.date.formatted(date: .complete, time: .omitted)
        }
        return grouped.sorted { $0.key > $1.key }.map { ($0.key, $0.value.sorted { $0.date > $1.date }) }
    }

    private func loadTransactions() {
        guard let ledger = appContainer.currentLedger else { return }
        let cal = Calendar.current
        let startOfMonth = cal.date(from: cal.dateComponents([.year, .month], from: selectedMonth))!
        let endOfMonth = cal.date(byAdding: DateComponents(month: 1, day: -1), to: startOfMonth)!
        let endOfDay = cal.date(byAdding: .day, value: 1, to: endOfMonth)!
        var filters = TransactionFilters()
        filters.dateRange = startOfMonth..<endOfDay
        filters.type = filterType
        transactions = (try? appContainer.transactionService.fetchTransactions(for: ledger, context: modelContext, filters: filters)) ?? []
    }

    private func deleteTransactions(in indexSet: IndexSet, from group: [Transaction]) {
        for index in indexSet {
            let transaction = group[index]
            try? appContainer.transactionService.deleteTransaction(transaction, context: modelContext)
        }
        loadTransactions()
    }
}
