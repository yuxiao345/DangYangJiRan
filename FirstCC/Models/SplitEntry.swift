import Foundation
import SwiftData

@Model
final class SplitEntry {
    var id: UUID
    var amount: Decimal
    var isPaid: Bool
    var paidDate: Date?

    var splitGroup: SplitGroup?

    var user: User?

    init(
        id: UUID = UUID(),
        amount: Decimal = 0,
        isPaid: Bool = false,
        paidDate: Date? = nil,
        user: User? = nil
    ) {
        self.id = id
        self.amount = amount
        self.isPaid = isPaid
        self.paidDate = paidDate
        self.user = user
    }
}
