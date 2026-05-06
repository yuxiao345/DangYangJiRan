import Foundation
import SwiftData

@Model
final class Ledger {
    var id: UUID
    var name: String
    var iconName: String
    var typeRaw: String
    var defaultCurrencyCode: String
    var isShared: Bool
    var createdAt: Date
    var ownerUserRecordID: String?

    @Relationship(deleteRule: .cascade)
    var members: [User]? = []

    @Relationship(deleteRule: .cascade)
    var accounts: [Account]? = []

    @Relationship(deleteRule: .cascade)
    var categories: [Category]? = []

    @Relationship(deleteRule: .cascade)
    var transactions: [Transaction]? = []

    @Relationship(deleteRule: .cascade)
    var templates: [TransactionTemplate]? = []

    @Relationship(deleteRule: .cascade)
    var budgets: [Budget]? = []

    @Relationship(deleteRule: .cascade)
    var lendings: [Lending]? = []

    var type: LedgerType {
        get { LedgerType(rawValue: typeRaw) ?? .personal }
        set { typeRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        name: String,
        iconName: String = "house",
        type: LedgerType = .personal,
        defaultCurrencyCode: String = "CNY",
        isShared: Bool = false,
        ownerUserRecordID: String? = nil
    ) {
        self.id = id
        self.name = name
        self.iconName = iconName
        self.typeRaw = type.rawValue
        self.defaultCurrencyCode = defaultCurrencyCode
        self.isShared = isShared
        self.createdAt = Date()
        self.ownerUserRecordID = ownerUserRecordID
    }
}
