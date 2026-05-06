import Foundation
import SwiftData

@Model
final class LendingRepayment {
    var id: UUID
    var amount: Decimal
    var date: Date
    var note: String?

    var lending: Lending?

    init(
        id: UUID = UUID(),
        amount: Decimal = 0,
        date: Date = Date(),
        note: String? = nil
    ) {
        self.id = id
        self.amount = amount
        self.date = date
        self.note = note
    }
}
