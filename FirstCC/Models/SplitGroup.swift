import Foundation
import SwiftData

@Model
final class SplitGroup {
    var id: UUID
    var totalAmount: Decimal
    var currencyCode: String
    var splitTypeRaw: String
    var note: String?
    var date: Date
    var createdAt: Date

    var ledger: Ledger?

    @Relationship(deleteRule: .cascade)
    var entries: [SplitEntry]? = []

    var transaction: Transaction?

    var splitType: SplitType {
        get { SplitType(rawValue: splitTypeRaw) ?? .equal }
        set { splitTypeRaw = newValue.rawValue }
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
