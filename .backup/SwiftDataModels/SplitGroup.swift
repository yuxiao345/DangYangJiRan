import Foundation
import SwiftData

@Model
final class SplitGroup {
    var id: UUID = UUID()
    var totalAmount: Decimal = 0
    var currencyCode: String = "CNY"
    var splitTypeRaw: String = SplitType.equal.rawValue
    var note: String?
    var date: Date = Date()
    var createdAt: Date = Date()

    var ledger: Ledger?

    @Relationship(deleteRule: .cascade, inverse: \SplitEntry.splitGroup)
    var entries: [SplitEntry]? = []

    var transaction: Transaction?

    var splitType: SplitType {
        get { SplitType(rawValue: splitTypeRaw) ?? .equal }
        set { splitTypeRaw = newValue.rawValue }
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

    init(
        id: UUID = UUID(),
        totalAmount: Decimal = 0,
        currencyCode: String = "CNY",
        splitType: SplitType = .equal,
        note: String? = nil,
        date: Date = Date()
    ) {
        self.id = id
        self.totalAmount = totalAmount
        self.currencyCode = currencyCode
        self.splitTypeRaw = splitType.rawValue
        self.note = note
        self.date = date
        self.createdAt = Date()
    }
}
