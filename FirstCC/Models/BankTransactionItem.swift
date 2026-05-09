import Foundation
import SwiftData

/// OCR-extracted bank transaction line item.
/// Currently a plain struct for the verification phase.
/// Will become a @Model when integrated into the reconciliation persistence layer.
struct BankTransactionItem: Identifiable {
    var id: UUID
    var transDate: Date?
    var amount: Decimal?
    var desc: String?
    var rawLine: String?
    var matchStatus: BankMatchStatus
    var sortOrder: Int

    init(
        id: UUID = UUID(),
        transDate: Date? = nil,
        amount: Decimal? = nil,
        desc: String? = nil,
        rawLine: String? = nil,
        matchStatus: BankMatchStatus = .unmatched,
        sortOrder: Int = 0
    ) {
        self.id = id
        self.transDate = transDate
        self.amount = amount
        self.desc = desc
        self.rawLine = rawLine
        self.matchStatus = matchStatus
        self.sortOrder = sortOrder
    }
}
