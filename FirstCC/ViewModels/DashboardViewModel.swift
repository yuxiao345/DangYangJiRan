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

        accounts = (try? accountService.fetchAccounts(for: ledger, context: context)) ?? []
        for a in accounts {
            accountBalances[a.id] = accountService.calculateBalance(for: a, context: context)
        }

        let allTransactions = (try? transactionService.fetchTransactions(for: ledger, context: context, filters: nil)) ?? []
        let monthTransactions = allTransactions.filter { $0.date >= monthStart }
        // Exclude refund transactions from monthly totals
        let normalTransactions = monthTransactions.filter { $0.refundGroupId == nil }

        monthlyIncome = normalTransactions.filter { $0.type == .income }.reduce(0) { $0 + $1.amount }
        monthlyExpense = normalTransactions.filter { $0.type == .expense }.reduce(0) { $0 + abs($1.amount) }

        recentTransactions = Array(allTransactions.prefix(10))
    }

    var monthlyNet: Decimal {
        monthlyIncome - monthlyExpense
    }
}
