import Foundation
@preconcurrency import CoreData

protocol TransactionServiceProtocol {
    func createTransaction(_ transaction: Transaction, ledger: Ledger, context: NSManagedObjectContext) throws
    func createTransfer(
        from sourceAccount: Account,
        to destAccount: Account,
        amount: Decimal,
        date: Date,
        note: String?,
        ledger: Ledger,
        context: NSManagedObjectContext
    ) throws -> (Transaction, Transaction)
    func createRefund(
        for original: Transaction,
        amount: Decimal,
        context: NSManagedObjectContext
    ) throws -> Transaction
    func fetchTransactions(
        for ledger: Ledger,
        context: NSManagedObjectContext,
        filters: TransactionFilters?
    ) throws -> [Transaction]
    func updateTransaction(_ transaction: Transaction, context: NSManagedObjectContext) throws
    func deleteTransaction(_ transaction: Transaction, context: NSManagedObjectContext) throws
}

struct TransactionFilters {
    var dateRange: Range<Date>?
    var amountRange: ClosedRange<Decimal>?
    var type: TransactionType?
    var keyword: String?
    // 多选：同类 = OR, 跨类 = AND
    var categoryIDs: Set<UUID>?
    var memberIDs: Set<UUID>?
    var projectIDs: Set<UUID>?
}
