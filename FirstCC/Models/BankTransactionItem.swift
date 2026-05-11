import Foundation

struct BankTransactionItem: Identifiable {
    var id: UUID
    var transDate: Date?
    var amount: Decimal?
    var desc: String?
    var rawLine: String?
    var sortOrder: Int

    init(
        id: UUID = UUID(),
        transDate: Date? = nil,
        amount: Decimal? = nil,
        desc: String? = nil,
        rawLine: String? = nil,
        sortOrder: Int = 0
    ) {
        self.id = id
        self.transDate = transDate
        self.amount = amount
        self.desc = desc
        self.rawLine = rawLine
        self.sortOrder = sortOrder
    }
}
