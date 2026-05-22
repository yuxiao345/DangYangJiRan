import Foundation
import SwiftData

@Model
final class SplitEntry {
    var id: UUID = UUID()
    var amount: Decimal = 0
    var isPaid: Bool = false
    var paidDate: Date?

    var splitGroup: SplitGroup?

    var member: Member?

    var user: User?

    init(
        id: UUID = UUID(),
        amount: Decimal = 0,
        isPaid: Bool = false,
        paidDate: Date? = nil,
        member: Member? = nil,
        user: User? = nil
    ) {
        self.id = id
        self.amount = amount
        self.isPaid = isPaid
        self.paidDate = paidDate
        self.member = member
        self.user = user
    }
}
