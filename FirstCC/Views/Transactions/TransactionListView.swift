import SwiftUI
@preconcurrency import CoreData

struct TransactionListView: View {
    @EnvironmentObject private var appContainer: AppContainer
    @Environment(\.managedObjectContext) private var modelContext
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

    var body: some View {
        ScrollView {
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
                .padding(.horizontal, 16)
                .padding(.top, 8)

                LazyVStack(spacing: 12) {
                    if transactions.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "tray")
                                .font(.system(size: 36))
                                .foregroundStyle(Color.designOnSurfaceVariant.opacity(0.4))
                            Text(selectedDay != nil ? "当天没有交易记录" : "暂无交易记录")
                                .font(.designBodyMedium)
                                .foregroundStyle(Color.designOnSurfaceVariant)
                        }
                        .padding(.top, 60)
                    } else {
                        ForEach(groupedByDate, id: \.key) { group in
                            dateSectionHeader(dateKey: group.key, transactions: group.value)
                            ForEach(group.value) { transaction in
                                NavigationLink(destination: TransactionDetailView(transaction: transaction)) {
                                    TransactionRowView(transaction: transaction)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(16)
            }
        }
        .modifier(ScrollCollapseModifier(isCalendarExpanded: $isCalendarExpanded))
        .designScreen()
        .navigationTitle("流水")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 16) {
                    if let ledger = appContainer.currentLedger {
                        NavigationLink {
                            SearchView(viewModel: SearchViewModel(
                                ledger: ledger,
                                transactionService: appContainer.transactionService
                            ))
                        } label: {
                            Image(systemName: "magnifyingglass")
                        }
                    }
                    Button { showAddSheet = true } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            ToolbarItem(placement: .navigationBarLeading) {
                Menu {
                    Button("全部") { filterType = nil }
                    Button(TransactionType.expense.displayName) { filterType = .expense }
                    Button(TransactionType.income.displayName) { filterType = .income }
                    Button(TransactionType.transfer.displayName) { filterType = .transfer }
                    Button(TransactionType.lending.displayName) { filterType = .lending }

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

    // MARK: - Date Section Header

    private func dateSectionHeader(dateKey: String, transactions: [Transaction]) -> some View {
        let total = transactions.reduce(Decimal.zero) { $0 + $1.amount }
        let currencyCode = transactions.first?.currencyCode ?? "CNY"

        return HStack(spacing: 8) {
            Circle()
                .fill(Color.designPrimaryContainer)
                .frame(width: 6, height: 6)

            Text(LocalizedStringKey(dateKey))
                .font(.custom("SpaceGrotesk-Medium", fixedSize: 14))
                .foregroundStyle(Color.designOnSurfaceVariant)

            Text("流水")
                .font(.designLabel)
                .foregroundStyle(Color.designOnSurfaceVariant.opacity(0.6))

            Spacer()

            Text("合计：")
                .font(.custom("SpaceGrotesk-Medium", fixedSize: 12))
                .foregroundStyle(Color.designOnSurfaceVariant.opacity(0.5))
                +
            Text(total >= 0 ? "+\(CurrencyFormatter.formatShort(amount: total, currencyCode: currencyCode))" : "\(CurrencyFormatter.formatShort(amount: total, currencyCode: currencyCode))")
                .font(.custom("JetBrainsMono-Medium", fixedSize: 12))
                .foregroundStyle(total >= 0 ? Color.designPrimaryFixedDim : Color.designAccentRed)
        }
        .padding(.horizontal, 4)
        .padding(.top, 4)
    }

    // MARK: - Grouping

    private static let dateGroupLocale = Locale(identifier: "zh_CN")

    private var groupedByDate: [(key: String, value: [Transaction])] {
        transactions.groupedByRelativeDate(locale: Self.dateGroupLocale)
    }

    // MARK: - Data Loading

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
}

// MARK: - Scroll Collapse (iOS 18+)

private struct ScrollCollapseModifier: ViewModifier {
    @Binding var isCalendarExpanded: Bool

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.onScrollGeometryChange(for: CGFloat.self) { geo in
                geo.contentOffset.y
            } action: { oldY, newY in
                if newY < oldY - 10, isCalendarExpanded {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        isCalendarExpanded = false
                    }
                }
            }
        } else {
            content
        }
    }
}
