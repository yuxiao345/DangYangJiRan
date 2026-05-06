import Foundation
import SwiftData

@Model
final class Lending {
    var id: UUID
    var typeRaw: String
    var counterparty: String
    var counterpartyUserID: UUID?
    var amount: Decimal
    var currencyCode: String
    var repaidAmount: Decimal
    var date: Date
    var dueDate: Date?
    var note: String?
    var statusRaw: String

    var ledger: Ledger?

    var user: User?

    @Relationship(deleteRule: .cascade)
    var repayments: [LendingRepayment]? = []

    var type: LendingType {
        get { LendingType(rawValue: typeRaw) ?? .borrow }
        set { typeRaw = newValue.rawValue }
    }

    var status: LendingStatus {
        get { LendingStatus(rawValue: statusRaw) ?? .active }
        set { statusRaw = newValue.rawValue }
    }

    var outstandingAmount: Decimal {
        amount - repaidAmount
    }

    init(
        id: UUID = UUID(),
        type: LendingType = .borrow,
        counterparty: String = "",
        amount: Decimal = 0,
        currencyCode: String = "CNY",
        date: Date = Date(),
        dueDate: Date? = nil,
        note: String? = nil
    ) {
        self.id = id
        self.typeRaw = type.rawValue
        self.counterparty = counterparty
        self.amount = amount
        self.currencyCode = currencyCode
        self.repaidAmount = 0
        self.date = date
        self.dueDate = dueDate
        self.note = note
        self.statusRaw = LendingStatus.active.rawValue
    }
}
