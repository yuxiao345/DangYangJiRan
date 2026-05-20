import Foundation
import SwiftData

@MainActor
final class DashboardViewModel: ObservableObject {
    @Published var monthlyIncome: Decimal = 0
    @Published var monthlyExpense: Decimal = 0
    @Published var recentTransactions: [Transaction] = []
    @Published var accounts: [Account] = []
    @Published var accountBalances: [UUID: Decimal] = [:]
    @Published var totalBalance: Decimal = 0
    @Published var previousMonthBalance: Decimal = 0
    @Published var balanceChangePercent: Decimal? = nil
    @Published var budgetSpent: Decimal = 0
    @Published var budgetLimit: Decimal = 0
    @Published var hasBudget: Bool = false

    private let accountService: AccountServiceProtocol
    private let transactionService: TransactionServiceProtocol
    private let ledger: Ledger

    init(ledger: Ledger, accountService: AccountServiceProtocol, transactionService: TransactionServiceProtocol) {
        self.ledger = ledger
        self.accountService = accountService
        self.transactionService = transactionService
    }

    func load(context: ModelContext) {
        let calendar = Calendar.current
        let now = Date()
        guard let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) else { return }
        let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart)!

        accounts = (try? accountService.fetchAccounts(for: ledger, context: context)) ?? []
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

        recentTransactions = Array(allTransactions.sorted(by: { $0.date > $1.date }).prefix(20))

        // Previous month balance = current balance - this month's net
        let net = monthlyIncome - monthlyExpense
        previousMonthBalance = totalBalance - net
        if previousMonthBalance != 0 {
            let change = (totalBalance - previousMonthBalance) / previousMonthBalance * 100
            balanceChangePercent = change
        } else {
            balanceChangePercent = nil
        }
    }

    func loadBudget(context: ModelContext, budgetService: BudgetServiceProtocol) {
        guard let books = try? budgetService.fetchBooks(for: ledger, context: context),
              let activeBook = books.first(where: { $0.isActive }) ?? books.first else {
            hasBudget = false
            return
        }
        hasBudget = true
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
