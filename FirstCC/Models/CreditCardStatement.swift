import Foundation
import SwiftData

@Model
final class CreditCardStatement {
    var id: UUID = UUID()
    var periodYear: Int = Calendar.current.component(.year, from: Date())
    var periodMonth: Int = Calendar.current.component(.month, from: Date())
    var statementAmount: Decimal?
    var reconciledAppAmount: Decimal?
    var isReconciled: Bool = false
    var reconciledAt: Date?
    var note: String?
    var bankCSVData: Data?
    var bankCSVFileName: String?

    var account: Account?

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
