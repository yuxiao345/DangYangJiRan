import Foundation
import SwiftData

protocol TransactionServiceProtocol {
    func createTransaction(_ transaction: Transaction, ledger: Ledger, context: ModelContext) throws
    func createTransfer(
        from sourceAccount: Account,
        to destAccount: Account,
        amount: Decimal,
        date: Date,
        note: String?,
        ledger: Ledger,
        context: ModelContext
    ) throws -> (Transaction, Transaction)
    func createRefund(
        for original: Transaction,
        amount: Decimal,
        context: ModelContext
    ) throws -> Transaction
    func fetchTransactions(
        for ledger: Ledger,
        context: ModelContext,
        filters: TransactionFilters?
    ) throws -> [Transaction]
    func updateTransaction(_ transaction: Transaction, context: ModelContext) throws
    func deleteTransaction(_ transaction: Transaction, context: ModelContext) throws
}

struct TransactionFilters {
    var dateRange: Range<Date>?
    var amountRange: ClosedRange<Decimal>?
    var accountID: UUID?
    var categoryID: UUID?
    var tags: [String]?
    var type: TransactionType?
    var keyword: String?
}
