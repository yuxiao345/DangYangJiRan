import Foundation
import SwiftData

protocol SplitServiceProtocol {
    func createSplit(
        totalAmount: Decimal,
        currencyCode: String,
        splitType: SplitType,
        members: [User],
        amounts: [Decimal]?,
        note: String?,
        date: Date,
        transaction: Transaction,
        ledger: Ledger,
        context: ModelContext
    ) throws -> SplitGroup
    func markEntryPaid(_ entry: SplitEntry, context: ModelContext) throws
    func settleSplit(_ splitGroup: SplitGroup, context: ModelContext) throws
    func fetchSplits(for ledger: Ledger, context: ModelContext) throws -> [SplitGroup]
}
