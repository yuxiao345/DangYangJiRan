import SwiftUI
import SwiftData

struct TransactionListView: View {
    @EnvironmentObject private var appContainer: AppContainer
    @Environment(\.modelContext) private var modelContext
    @State private var transactions: [Transaction] = []
    @State private var showAddSheet = false
    @State private var filterType: TransactionType?
    @State private var selectedMonth: Date = Date().startOfMonth
    @State private var selectedDay: Int?
    @State private var isCalendarExpanded = false
    @State private var dailyExpense: [Int: Decimal] = [:]
    @State private var dailyIncome: [Int: Decimal] = [:]
    @State private var maxDailyExpense: Decimal = 0
    @State private var monthlyIncome: Decimal = 0
    @State private var monthlyExpense: Decimal = 0
    @State private var monthTransactions: [Transaction] = []
    @State private var dateFormattedCache: [Transaction.ID: String] = [:]

    var body: some View {
        VStack(spacing: 0) {
            CalendarStripView(
                selectedMonth: $selectedMonth,
                selectedDay: $selectedDay,
                isExpanded: $isCalendarExpanded,
                dailyExpense: $dailyExpense,
                dailyIncome: $dailyIncome,
                maxDailyExpense: $maxDailyExpense,
                monthlyIncome: $monthlyIncome,
                monthlyExpense: $monthlyExpense
            )
            Divider()

            List {
                if transactions.isEmpty {
                    Text(selectedDay != nil ? "当天没有交易记录" : "暂无交易记录")
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
            .listStyle(.insetGrouped)
        }
        .navigationTitle("流水")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showAddSheet = true } label: {
                    Image(systemName: "plus")
                }
            }
            ToolbarItem(placement: .navigationBarLeading) {
                Menu {
                    Button("全部") { filterType = nil }
                    Button(TransactionType.expense.displayName) { filterType = .expense }
                    Button(TransactionType.income.displayName) { filterType = .income }
                    Button(TransactionType.transfer.displayName) { filterType = .transfer }
                    Button(TransactionType.lending.displayName) { filterType = .lending }
                    Button(TransactionType.adjustment.displayName) { filterType = .adjustment }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddEditTransactionView()
        }
        .onAppear(perform: loadCalendarData)
        .onChange(of: selectedMonth) { _, _ in loadCalendarData() }
        .onChange(of: filterType) { _, _ in loadCalendarData() }
        .onChange(of: selectedDay) { _, _ in applyFilters() }
        .onReceive(NotificationCenter.default.publisher(for: .transactionDidChange)) { _ in
            loadCalendarData()
        }
    }

    private var groupedByDate: [(key: String, value: [Transaction])] {
        let grouped = Dictionary(grouping: transactions) { t in
            if let cached = dateFormattedCache[t.id] { return cached }
            let formatted = t.date.formatted(date: .complete, time: .omitted)
            dateFormattedCache[t.id] = formatted
            return formatted
        }
        return grouped.sorted { $0.key > $1.key }.map { ($0.key, $0.value.sorted { $0.date > $1.date }) }
    }

    private func loadCalendarData() {
        guard let ledger = appContainer.currentLedger else { return }
        let cal = Calendar.current
        let start = selectedMonth
        guard let end = cal.date(byAdding: .month, value: 1, to: start) else { return }

        var filters = TransactionFilters()
        filters.dateRange = start..<end
        let all = (try? appContainer.transactionService.fetchTransactions(for: ledger, context: modelContext, filters: filters)) ?? []

        let settlementIDs = Set(all.compactMap(\.reimbursedById))
        let normal = all.filter { t in
            guard t.refundGroupId == nil else { return false }
            if t.type == .expense, t.isReimbursable { return false }
            if t.type == .income, settlementIDs.contains(t.id) { return false }
            return true
        }

        var expenseByDay: [Int: Decimal] = [:]
        var incomeByDay: [Int: Decimal] = [:]
        var totalIncome: Decimal = 0
        var totalExpense: Decimal = 0

        for t in normal {
            let d = cal.component(.day, from: t.date)
            switch t.type {
            case .expense:
                let absAmt = abs(t.amount)
                expenseByDay[d, default: 0] += absAmt
                totalExpense += absAmt
            case .income:
                incomeByDay[d, default: 0] += t.amount
                totalIncome += t.amount
            default:
                break
            }
        }

        dailyExpense = expenseByDay
        dailyIncome = incomeByDay
        maxDailyExpense = expenseByDay.values.max() ?? 0
        monthlyIncome = totalIncome
        monthlyExpense = totalExpense
        monthTransactions = all
        dateFormattedCache.removeAll()

        applyFilters()
    }

    private func applyFilters() {
        var result = monthTransactions
        if let day = selectedDay {
            let cal = Calendar.current
            result = result.filter { cal.component(.day, from: $0.date) == day }
        }
        if let type = filterType {
            result = result.filter { $0.type == type }
        }
        transactions = result
    }

    private func deleteTransactions(in indexSet: IndexSet, from group: [Transaction]) {
        for index in indexSet {
            let transaction = group[index]
            try? appContainer.transactionService.deleteTransaction(transaction, context: modelContext)
        }
        loadCalendarData()
    }
}
