import Foundation
import SwiftData

/// Wraps a bank transaction item with its matching result against app transactions
struct ReconciliationMatch: Identifiable {
    var id: UUID = UUID()
    var bankItem: BankTransactionItem
    var candidates: [Transaction]
    var status: BankMatchStatus
    var userAction: UserAction = .pending

    enum UserAction {
        case pending
        case confirmed(Transaction)   // matched to this app transaction
        case ignored
        case createNew                // will create a new app transaction
    }
}

protocol ReconciliationServiceProtocol {
    /// Match bank items against app transactions for a billing period
    func matchItems(_ bankItems: [BankTransactionItem], for account: Account, year: Int, month: Int, context: ModelContext) -> [ReconciliationMatch]

    /// Confirm reconciliation: mark matched transactions as reconciled, create statement
    func confirmReconciliation(
        matches: [ReconciliationMatch],
        account: Account,
        year: Int,
        month: Int,
        bankAmount: Decimal,
        ledger: Ledger,
        context: ModelContext
    ) throws -> CreditCardStatement
}
