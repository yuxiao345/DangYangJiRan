import Foundation
@preconcurrency import CoreData

@objc(SplitEntry)
final class SplitEntry: NSManagedObject,  Sendable {
    @NSManaged var id: UUID
    @NSManaged var amountInFen: Int64
    @NSManaged var isPaid: Bool
    @NSManaged var paidDate: Date?

    @NSManaged var splitGroup: SplitGroup?
    @NSManaged var member: Member?
    @NSManaged var user: User?

    var amount: Decimal {
        get { Decimal(amountInFen) / 100 }
        set { amountInFen = Int64(truncating: (newValue * 100) as NSDecimalNumber) }
    }

    override func awakeFromInsert() {
        super.awakeFromInsert()
        id = UUID()
    }

    convenience init(
        amount: Decimal = 0,
        isPaid: Bool = false,
        paidDate: Date? = nil,
        member: Member? = nil,
        user: User? = nil,
        context: NSManagedObjectContext
    ) {
        self.init(context: context)
        self.amount = amount
        self.isPaid = isPaid
        self.paidDate = paidDate
        self.member = member
        self.user = user
    }
}

extension SplitEntry: Identifiable {}
