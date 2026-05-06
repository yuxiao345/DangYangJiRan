import Foundation
import SwiftData

@Model
final class Category {
    var id: UUID
    var name: String
    var iconName: String
    var colorHex: String
    var typeRaw: String
    var isSystem: Bool
    var sortOrder: Int

    var ledger: Ledger?

    var parent: Category?

    @Relationship(deleteRule: .nullify)
    var children: [Category]? = []

    @Relationship(deleteRule: .nullify)
    var transactions: [Transaction]? = []

    @Relationship(deleteRule: .cascade)
    var budgets: [Budget]? = []

    var type: TransactionType {
        get { TransactionType(rawValue: typeRaw) ?? .expense }
        set { typeRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        name: String,
        iconName: String = "questionmark",
        colorHex: String = "#666666",
        type: TransactionType = .expense,
        isSystem: Bool = false,
        sortOrder: Int = 0,
        parent: Category? = nil
    ) {
        self.id = id
        self.name = name
        self.iconName = iconName
        self.colorHex = colorHex
        self.typeRaw = type.rawValue
        self.isSystem = isSystem
        self.sortOrder = sortOrder
        self.parent = parent
    }
}
