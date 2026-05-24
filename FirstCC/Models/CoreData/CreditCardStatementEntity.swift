import Foundation
@preconcurrency import CoreData

@objc(CreditCardStatement)
final class CreditCardStatement: NSManagedObject,  Sendable {
    @NSManaged var id: UUID
    @NSManaged var periodYear: Int64
    @NSManaged var periodMonth: Int64
    @NSManaged var statementAmountInFen: Int64  // optional, 0 = nil
    @NSManaged var reconciledAppAmountInFen: Int64  // optional, 0 = nil
    @NSManaged var isReconciled: Bool
    @NSManaged var reconciledAt: Date?
    @NSManaged var note: String?
    @NSManaged var bankCSVData: Data?
    @NSManaged var bankCSVFileName: String?

    @NSManaged var account: Account?
    @NSManaged var ledger: Ledger?

    var statementAmount: Decimal? {
        get { statementAmountInFen == 0 ? nil : Decimal(statementAmountInFen) / 100 }
        set { statementAmountInFen = newValue.map { Int64(truncating: ($0 * 100) as NSDecimalNumber) } ?? 0 }
    }

    var reconciledAppAmount: Decimal? {
        get { reconciledAppAmountInFen == 0 ? nil : Decimal(reconciledAppAmountInFen) / 100 }
        set { reconciledAppAmountInFen = newValue.map { Int64(truncating: ($0 * 100) as NSDecimalNumber) } ?? 0 }
    }

    override func awakeFromInsert() {
        super.awakeFromInsert()
        id = UUID()
    }

    convenience init(
        account: Account? = nil,
        periodYear: Int,
        periodMonth: Int,
        statementAmount: Decimal? = nil,
        reconciledAppAmount: Decimal? = nil,
        isReconciled: Bool = false,
        reconciledAt: Date? = nil,
        note: String? = nil,
        bankCSVData: Data? = nil,
        bankCSVFileName: String? = nil,
        context: NSManagedObjectContext
    ) {
        self.init(context: context)
        self.account = account
        self.periodYear = Int64(periodYear)
        self.periodMonth = Int64(periodMonth)
        self.statementAmount = statementAmount
        self.reconciledAppAmount = reconciledAppAmount
        self.isReconciled = isReconciled
        self.reconciledAt = reconciledAt
        self.note = note
        self.bankCSVData = bankCSVData
        self.bankCSVFileName = bankCSVFileName
    }
}

extension CreditCardStatement: Identifiable {}
