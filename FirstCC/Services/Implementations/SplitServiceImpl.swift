import Foundation
import SwiftData

struct SplitServiceImpl: SplitServiceProtocol {
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
        context: ModelContext
    ) throws -> SplitGroup {
        let group = SplitGroup(
            totalAmount: totalAmount,
            currencyCode: currencyCode,
            splitType: splitType,
            note: note,
            date: date
        )
        group.ledger = ledger
        group.transaction = transaction
        transaction.splitGroup = group
        transaction.isSplitParent = true
        context.insert(group)

        let entryAmounts: [Decimal]
        switch splitType {
        case .equal:
            let share = totalAmount / Decimal(members.count)
            entryAmounts = Array(repeating: share, count: members.count)
        case .percentage, .fixed:
            guard let amounts else { throw SplitError.invalidAmounts }
            entryAmounts = amounts
        }

        for (index, member) in members.enumerated() {
            let entry = SplitEntry(
                amount: entryAmounts[index],
                member: member
            )
            entry.splitGroup = group
            context.insert(entry)
        }

        try saveAndNotify(context: context)
        return group
    }

    func markEntryPaid(_ entry: SplitEntry, context: ModelContext) throws {
        entry.isPaid = true
        entry.paidDate = Date()
        try saveAndNotify(context: context)
    }

    func settleSplit(_ splitGroup: SplitGroup, context: ModelContext) throws {
        for entry in splitGroup.entries ?? [] {
            if !entry.isPaid {
                entry.isPaid = true
                entry.paidDate = Date()
            }
        }
        try saveAndNotify(context: context)
    }

    private func saveAndNotify(context: ModelContext) throws {
        try context.save()
        NotificationCenter.default.post(name: .transactionDidChange, object: nil)
    }

    func fetchSplits(for ledger: Ledger, context: ModelContext) throws -> [SplitGroup] {
        let ledgerID = ledger.id
        let descriptor = FetchDescriptor<SplitGroup>(
            predicate: #Predicate { $0.ledger?.id == ledgerID },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }
}

enum SplitError: LocalizedError {
    case invalidAmounts

    var errorDescription: String? {
        switch self {
        case .invalidAmounts:
            return "分摊金额配置无效"
        }
    }
}
