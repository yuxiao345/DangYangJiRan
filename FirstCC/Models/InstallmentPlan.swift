import Foundation
import SwiftData

@Model
final class InstallmentPlan {
    var id: UUID
    var totalAmount: Decimal
    var currencyCode: String
    var numberOfInstallments: Int
    var installmentAmount: Decimal
    var startDate: Date
    var note: String?

    var ledger: Ledger?

    var account: Account?

    @Relationship(deleteRule: .nullify)
    var transactions: [Transaction]? = []

    var remainingInstallments: Int {
        numberOfInstallments - (transactions?.count ?? 0)
    }

    init(
        id: UUID = UUID(),
        totalAmount: Decimal = 0,
        currencyCode: String = "CNY",
        numberOfInstallments: Int = 3,
        installmentAmount: Decimal = 0,
        startDate: Date = Date(),
        note: String? = nil,
        account: Account? = nil
    ) {
        self.id = id
        self.totalAmount = totalAmount
        self.currencyCode = currencyCode
        self.numberOfInstallments = numberOfInstallments
        self.installmentAmount = installmentAmount
        self.startDate = startDate
        self.note = note
        self.account = account
    }
}
