import Foundation
@preconcurrency import CoreData

@objc(SplitGroup)
final class SplitGroup: NSManagedObject,  Sendable {
    @NSManaged var id: UUID
    @NSManaged var totalAmountInFen: Int64
    @NSManaged var currencyCode: String
    @NSManaged var splitTypeRaw: String
    @NSManaged var note: String?
    @NSManaged var date: Date
    @NSManaged var createdAt: Date

    @NSManaged var ledger: Ledger?
    @NSManaged var entries: Set<SplitEntry>?
    @NSManaged var transaction: Transaction?

    var splitType: SplitType {
        get { SplitType(rawValue: splitTypeRaw) ?? .equal }
        set { splitTypeRaw = newValue.rawValue }
    }

    var totalAmount: Decimal {
        get { Decimal(totalAmountInFen) / 100 }
        set { totalAmountInFen = Int64(truncating: (newValue * 100) as NSDecimalNumber) }
    }

    var totalPaid: Decimal {
        (entries ?? []).filter { $0.isPaid }.reduce(0) { $0 + $1.amount }
    }

    var remainingAmount: Decimal {
        totalAmount - totalPaid
    }

    var settlementStatus: SettlementStatus {
        if totalPaid >= totalAmount { return .settled }
        if totalPaid > 0 { return .partial }
        return .unsettled
    }

    override func awakeFromInsert() {
        super.awakeFromInsert()
        id = UUID()
        createdAt = Date.now
        date = Date.now
    }

    convenience init(
        totalAmount: Decimal = 0,
        currencyCode: String = "CNY",
        splitType: SplitType = .equal,
        note: String? = nil,
        date: Date = Date.now,
        context: NSManagedObjectContext
    ) {
        self.init(context: context)
        self.totalAmount = totalAmount
        self.currencyCode = currencyCode
        self.splitTypeRaw = splitType.rawValue
        self.note = note
        self.date = date
    }
}

extension SplitGroup: Identifiable {}
