import Foundation
@preconcurrency import CoreData

protocol SplitServiceProtocol {
    func createSplit(
        totalAmount: Decimal,
        currencyCode: String,
        splitType: SplitType,
        members: [Member],
        amounts: [Decimal]?,
        note: String?,
        date: Date,
        transaction: Transaction,
        ledger: Ledger,
        context: NSManagedObjectContext
    ) throws -> SplitGroup
    func markEntryPaid(_ entry: SplitEntry, context: NSManagedObjectContext) throws
    func settleSplit(_ splitGroup: SplitGroup, context: NSManagedObjectContext) throws
    func fetchSplits(for ledger: Ledger, context: NSManagedObjectContext) throws -> [SplitGroup]
}
