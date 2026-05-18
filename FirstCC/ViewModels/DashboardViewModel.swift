import Foundation
import SwiftData

@MainActor
final class DashboardViewModel: ObservableObject {
    @Published var monthlyIncome: Decimal = 0
    @Published var monthlyExpense: Decimal = 0
    @Published var recentTransactions: [Transaction] = []
    @Published var accounts: [Account] = []
    @Published var accountBalances: [UUID: Decimal] = [:]

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
        for a in accounts {
            accountBalances[a.id] = accountService.calculateBalance(for: a, context: context)
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

        recentTransactions = Array(allTransactions.sorted(by: { $0.date > $1.date }).prefix(10))
    }

    var monthlyNet: Decimal {
        monthlyIncome - monthlyExpense
    }
}
