import Foundation
@preconcurrency import CoreData

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
        context: NSManagedObjectContext
    ) throws -> SplitGroup {
        let group = SplitGroup(
            totalAmount: totalAmount,
            currencyCode: currencyCode,
            splitType: splitType,
            note: note,
            date: date,
            context: context
        )
        group.ledger = ledger
        group.transaction = transaction
        transaction.splitGroup = group
        transaction.isSplitParent = true

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
                member: member,
                context: context
            )
            entry.splitGroup = group
        }

        try saveAndNotify(context: context)
        return group
    }

    func markEntryPaid(_ entry: SplitEntry, context: NSManagedObjectContext) throws {
        entry.isPaid = true
        entry.paidDate = Date.now
        try saveAndNotify(context: context)
    }

    func settleSplit(_ splitGroup: SplitGroup, context: NSManagedObjectContext) throws {
        for entry in splitGroup.entries ?? [] {
            if !entry.isPaid {
                entry.isPaid = true
                entry.paidDate = Date.now
            }
        }
        try saveAndNotify(context: context)
    }

    private func saveAndNotify(context: NSManagedObjectContext) throws {
        try context.save()
        NotificationCenter.default.post(name: .transactionDidChange, object: nil)
    }

    func fetchSplits(for ledger: Ledger, context: NSManagedObjectContext) throws -> [SplitGroup] {
        let ledgerID = ledger.id
        let request = NSFetchRequest<SplitGroup>(entityName: "SplitGroup")
        request.predicate = NSPredicate(format: "ledger.id == %@", ledgerID as CVarArg)
        request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
        return try context.fetch(request)
    }
}

enum SplitError: LocalizedError {
    case invalidAmounts

    var errorDescription: String? {
        switch self {
        case .invalidAmounts:
            return String(localized: "分摊金额配置无效")
        }
    }
}
