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
    }

    func load(ledger: Ledger, context: NSManagedObjectContext) {
        self.ledger = ledger
        load(context: context)
    }

    func load(context: NSManagedObjectContext) {
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

        var filters = TransactionFilters()
        filters.dateRange = monthStart..<monthEnd
        let allTransactions = (try? transactionService.fetchTransactions(for: ledger, context: context, filters: filters)) ?? []

        let settlementIncomeIDs = Set(allTransactions.compactMap(\.reimbursedById))
        let normalTransactions = allTransactions.filter { t in
            guard t.refundGroupId == nil else { return false }
            if t.type == .expense, t.isReimbursable { return false }
            if t.type == .income, settlementIncomeIDs.contains(t.id) { return false }
            return true
        }

        monthlyIncome = normalTransactions.filter { $0.type == .income }.reduce(0) { $0 + $1.amount }
        monthlyExpense = normalTransactions.filter { $0.type == .expense }.reduce(0) { $0 + $1.amount }

        recentTransactions = Array(allTransactions.deduplicatingTransfers().sorted(by: { $0.date > $1.date }).prefix(20))

        // Previous month balance = current balance - this month's net (all types, unfiltered)
        let net = allTransactions.reduce(0) { $0 + $1.amount }
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
    }

    var monthlyNet: Decimal {
        monthlyIncome - monthlyExpense
    }

    var budgetFraction: Double {
        guard budgetLimit > 0 else { return 0 }
        return max(0, min(1, Double(truncating: (budgetSpent / budgetLimit) as NSNumber)))
    }
}
