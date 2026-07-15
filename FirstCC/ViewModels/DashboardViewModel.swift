import Foundation
@preconcurrency import CoreData

@Observable
@MainActor
final class DashboardViewModel {
    var monthlyIncome: Decimal = 0
    var monthlyExpense: Decimal = 0
    var recentTransactions: [Transaction] = []
    var accounts: [Account] = []
    var accountBalances: [UUID: Decimal] = [:]
    var totalBalance: Decimal = 0
    var previousMonthBalance: Decimal = 0
    var balanceChange: Decimal? = nil
    var balanceChangePercent: Decimal? = nil
    var budgetSpent: Decimal = 0
    var budgetLimit: Decimal = 0
    var hasBudget: Bool = false
    var activeBudgetBook: BudgetBook?
    var categoryOverviewItems: [CategoryExpenseItem] = []
    var categoryOverviewTotal: Decimal = 0
    var allocationItems: [AccountAllocationItem] = []
    var burnRateData: [BurnRateBucket] = []
    var budgetTimeProgress: Double = 0
    var budgetElapsedDays: Int = 0
    var budgetTotalDays: Int = 0

    private let accountService: AccountServiceProtocol
    private let transactionService: TransactionServiceProtocol
    private var ledger: Ledger?

    init(accountService: AccountServiceProtocol, transactionService: TransactionServiceProtocol, ledger: Ledger? = nil) {
        self.ledger = ledger
        self.accountService = accountService
        self.transactionService = transactionService
    }

    func copyFrom(_ other: DashboardViewModel) {
        monthlyIncome = other.monthlyIncome
        monthlyExpense = other.monthlyExpense
        recentTransactions = other.recentTransactions
        accounts = other.accounts
        accountBalances = other.accountBalances
        totalBalance = other.totalBalance
        previousMonthBalance = other.previousMonthBalance
        balanceChange = other.balanceChange
        balanceChangePercent = other.balanceChangePercent
        budgetSpent = other.budgetSpent
        budgetLimit = other.budgetLimit
        hasBudget = other.hasBudget
        activeBudgetBook = other.activeBudgetBook
        categoryOverviewItems = other.categoryOverviewItems
        categoryOverviewTotal = other.categoryOverviewTotal
        allocationItems = other.allocationItems
        burnRateData = other.burnRateData
        budgetTimeProgress = other.budgetTimeProgress
        budgetElapsedDays = other.budgetElapsedDays
        budgetTotalDays = other.budgetTotalDays
    }

    func load(ledger: Ledger, context: NSManagedObjectContext, budgetService: BudgetServiceProtocol) {
        self.ledger = ledger
        load(context: context, budgetService: budgetService)
    }

    func load(context: NSManagedObjectContext, budgetService: BudgetServiceProtocol) {
        guard let ledger else { return }
        let calendar = Calendar.current
        let now = Date()
        guard let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now)),
              let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart) else { return }

        accounts = (try? accountService.fetchAccounts(for: ledger, includeArchived: true, context: context)) ?? []
        totalBalance = 0
        for a in accounts {
            let bal = accountService.calculateBalance(for: a, context: context)
            accountBalances[a.id] = bal
            totalBalance += bal
        }

        // Build allocation items from accounts
        let nonZeroAccts = accounts.filter { (accountBalances[$0.id] ?? 0) != 0 }
        let totalAbs: Decimal = nonZeroAccts.reduce(0) { acc, a in
            acc + abs(accountBalances[a.id] ?? 0)
        }
        allocationItems = nonZeroAccts
            .sorted { a, b in
                abs(accountBalances[a.id] ?? 0) > abs(accountBalances[b.id] ?? 0)
            }
            .map { a in
                let bal = accountBalances[a.id] ?? 0
                return AccountAllocationItem(
                    id: a.id, name: a.name, accountType: a.type,
                    iconName: a.iconName ?? a.type.systemIcon, balance: bal,
                    percentage: totalAbs > 0 ? Double(truncating: (abs(bal) / totalAbs) as NSNumber) : 0,
                    isLiability: bal < 0
                )
            }

        var filters = TransactionFilters()
        filters.dateRange = monthStart..<monthEnd
        let allTransactions = (try? transactionService.fetchTransactions(for: ledger, context: context, filters: filters)) ?? []

        let normalTransactions = allTransactions.excludingReimbursementTransactions()

        monthlyIncome = normalTransactions.filter { $0.type == .income }.reduce(0) { $0 + $1.ledgerAmount }
        let cal = Calendar.current
        let rangeStart = cal.startOfDay(for: monthStart)
        let rangeEnd = cal.endOfDay(for: cal.date(byAdding: DateComponents(month: 1, day: -1), to: monthStart) ?? monthStart)
        let monthRange = rangeStart...rangeEnd
        monthlyExpense = -(budgetService.totalExpense(in: monthRange, ledger: ledger, context: context))

        let oneMonthAgo = calendar.date(byAdding: .month, value: -1, to: now) ?? now
        recentTransactions = Array(allTransactions
            .deduplicatingTransfers()
            .filter { $0.date >= oneMonthAgo }
            .sorted(by: { $0.date > $1.date }))

        // Previous month balance = current balance - this month's net (all types, unfiltered)
        let net = allTransactions.reduce(0) { $0 + $1.ledgerAmount }
        previousMonthBalance = totalBalance - net
        if previousMonthBalance != 0 {
            let change = totalBalance - previousMonthBalance
            balanceChange = change
            let magnitude = abs(change / previousMonthBalance) * 100
            balanceChangePercent = change >= 0 ? magnitude : -magnitude
        } else {
            balanceChange = nil
            balanceChangePercent = nil
        }
    }

    func loadBudget(context: NSManagedObjectContext, budgetService: BudgetServiceProtocol) {
        guard let ledger else { return }
        guard let books = try? budgetService.fetchBooks(for: ledger, context: context),
              let activeBook = books.first(where: { $0.isActive }) else {
            hasBudget = false
            return
        }
        hasBudget = true
        activeBudgetBook = activeBook
        budgetSpent = budgetService.totalCurrentPeriodSpending(for: activeBook, context: context)
        budgetLimit = budgetService.totalCurrentPeriodBudget(for: activeBook)

        // Compute time progress
        let cal = Calendar.current
        let now = Date()
        let start = cal.startOfDay(for: activeBook.startDate)
        let end = cal.startOfDay(for: activeBook.endDate)
        let total = max(1, (cal.dateComponents([.day], from: start, to: end).day ?? 0) + 1)
        let elapsed = max(0, min(total, cal.dateComponents([.day], from: start, to: now).day ?? 0))
        budgetTotalDays = total
        budgetElapsedDays = elapsed
        budgetTimeProgress = total > 0 ? Double(elapsed) / Double(total) : 0
    }

    func loadBudgetBurnRate(context: NSManagedObjectContext, budgetService: BudgetServiceProtocol) {
        guard let ledger, let book = activeBudgetBook else { return }
        let cal = Calendar.current
        let trendStart = cal.startOfDay(for: book.startDate)
        let trendEnd = cal.startOfDay(for: Date())

        // Aggregate daily spending. When matchBudgetItems is false, count ALL categories
        // (consistent with the budget summary card); otherwise aggregate only budgeted categories.
        var dailyAggregate: [Date: Decimal] = [:]
        if book.matchBudgetItems {
            let items = (try? budgetService.fetchItems(for: book, context: context)) ?? []
            let budgetedCatIDs = Set(items.filter { $0.isActive }.compactMap { $0.category?.id })
            for item in items {
                guard let cat = item.category else { continue }
                // 找出该分类下已有独立预算的后代，作为排除项传给 dailySpending
                // 父分类只统计其独占交易，子分类交易由各自的预算项自行纳入，避免重复
                let childBudgetedIDs = cat.allDescendantIDs.filter { budgetedCatIDs.contains($0) }
                let points = budgetService.dailySpending(in: trendStart...trendEnd, categoryID: cat.id, excludeCategoryIDs: childBudgetedIDs, ledgerID: ledger.id, context: context)
                for point in points {
                    dailyAggregate[point.date, default: 0] += point.amount
                }
            }
        } else {
            let points = budgetService.dailySpending(in: trendStart...trendEnd, categoryID: nil, ledgerID: ledger.id, context: context)
            for point in points {
                dailyAggregate[point.date, default: 0] += point.amount
            }
        }

        let totalDays = max(1, cal.dateComponents([.day], from: trendStart, to: trendEnd).day ?? 0)
        let bucketDays = max(1, totalDays / 12)
        var buckets: [BurnRateBucket] = []
        for i in 0..<12 {
            let bucketStart = cal.date(byAdding: .day, value: i * bucketDays, to: trendStart) ?? trendStart
            let bucketEnd = min(cal.date(byAdding: .day, value: bucketDays - 1, to: bucketStart) ?? bucketStart, trendEnd)
            var sum: Decimal = 0
            for (date, amount) in dailyAggregate {
                if date >= bucketStart && date <= bucketEnd { sum += amount }
            }
            buckets.append(BurnRateBucket(index: i, startDate: bucketStart, endDate: bucketEnd, amount: sum, maxAmount: 0))
        }
        let maxAmt = buckets.map(\.amount).max() ?? 1
        burnRateData = buckets.map { b in
            BurnRateBucket(index: b.index, startDate: b.startDate, endDate: b.endDate, amount: b.amount, maxAmount: maxAmt)
        }
    }

    var monthlyNet: Decimal {
        monthlyIncome - monthlyExpense
    }

    var budgetFraction: Double {
        guard budgetLimit > 0 else { return 0 }
        return max(0, min(1, Double(truncating: (budgetSpent / budgetLimit) as NSNumber)))
    }

    // MARK: - Category Overview

    func loadCategoryOverview(
        ledger: Ledger,
        transactionService: TransactionServiceProtocol,
        categoryService: CategoryServiceProtocol,
        context: NSManagedObjectContext
    ) {
        let cal = Calendar.current
        let now = Date()
        guard let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: now)),
              let monthEnd = cal.date(byAdding: .month, value: 1, to: monthStart) else { return }

        var filters = TransactionFilters()
        filters.dateRange = monthStart..<monthEnd
        let all = (try? transactionService.fetchTransactions(for: ledger, context: context, filters: filters)) ?? []

        let expenseTxns = all.filter { t in
            guard t.type == .expense else { return false }
            guard !t.isSplitParent else { return false }
            guard !t.isReimbursable else { return false }
            return true
        }

        let allCategories = (try? categoryService.fetchAllCategories(for: ledger, type: .expense, context: context)) ?? []
        let categoryLookup = Dictionary(uniqueKeysWithValues: allCategories.map { ($0.id, $0) })

        var rootTotals: [UUID: Decimal] = [:]
        var uncategorizedTotal: Decimal = 0

        for t in expenseTxns {
            guard let cat = t.category else {
                uncategorizedTotal += netAmount(t)
                continue
            }
            let root = rootCategory(for: cat)
            rootTotals[root.id, default: 0] += netAmount(t)
        }

        let total = rootTotals.values.reduce(0, +) + uncategorizedTotal

        var items: [CategoryExpenseItem] = rootTotals.map { id, amount in
            let cat = categoryLookup[id]
            return CategoryExpenseItem(
                id: id,
                name: cat?.name ?? String(localized: "未知"),
                iconName: cat?.iconName ?? "questionmark",
                colorHex: cat?.colorHex ?? "#999999",
                amount: amount,
                percentage: total > 0 ? Double(truncating: (amount / total) as NSNumber) : 0,
                parentID: nil,
                children: []
            )
        }.sorted { $0.amount > $1.amount }

        if uncategorizedTotal > 0 {
            let uncategorizedItem = CategoryExpenseItem(
                id: UUID(),
                name: String(localized: "未分类"),
                iconName: "questionmark.circle",
                colorHex: "#AAAAAA",
                amount: uncategorizedTotal,
                percentage: total > 0 ? Double(truncating: (uncategorizedTotal / total) as NSNumber) : 0,
                parentID: nil,
                children: []
            )
            items.append(uncategorizedItem)
        }

        categoryOverviewItems = items
        categoryOverviewTotal = total
    }

    private func netAmount(_ t: Transaction) -> Decimal {
        let base = t.ledgerAmount
        return t.refundGroupId != nil ? -abs(base) : abs(base)
    }

    private func rootCategory(for cat: Category) -> Category {
        var current = cat
        while let p = current.parent { current = p }
        return current
    }
}
