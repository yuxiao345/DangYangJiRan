import Foundation
import SwiftData

@Model
final class CreditCardStatement {
    var id: UUID
    var account: Account?
    var periodYear: Int
    var periodMonth: Int
    var statementAmount: Decimal?
    var reconciledAppAmount: Decimal?
    var isReconciled: Bool
    var reconciledAt: Date?
    var note: String?
    var bankCSVData: Data?
    var bankCSVFileName: String?

    var ledger: Ledger?

    init(
        id: UUID = UUID(),
        account: Account? = nil,
        periodYear: Int,
        periodMonth: Int,
        statementAmount: Decimal? = nil,
        reconciledAppAmount: Decimal? = nil,
        isReconciled: Bool = false,
        reconciledAt: Date? = nil,
        note: String? = nil,
        bankCSVData: Data? = nil,
        bankCSVFileName: String? = nil
    ) {
        self.id = id
        self.account = account
        self.periodYear = periodYear
        self.periodMonth = periodMonth
        self.statementAmount = statementAmount
        self.reconciledAppAmount = reconciledAppAmount
        self.isReconciled = isReconciled
        self.reconciledAt = reconciledAt
        self.note = note
        self.bankCSVData = bankCSVData
        self.bankCSVFileName = bankCSVFileName
    }
}
