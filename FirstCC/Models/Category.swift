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
    var isHidden: Bool
    var sortOrder: Int

    var ledger: Ledger?

    var parent: Category?

    @Relationship(deleteRule: .nullify)
    var children: [Category]? = []

    @Relationship(deleteRule: .nullify)
    var transactions: [Transaction]? = []

    var budgetItems: [BudgetItem]? = []

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
        isHidden: Bool = false,
        sortOrder: Int = 0,
        parent: Category? = nil
    ) {
        self.id = id
        self.name = name
        self.iconName = iconName
        self.colorHex = colorHex
        self.typeRaw = type.rawValue
        self.isSystem = isSystem
        self.isHidden = isHidden
        self.sortOrder = sortOrder
        self.parent = parent
    }
}

extension Category: Hashable {
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
    public static func == (lhs: Category, rhs: Category) -> Bool { lhs.id == rhs.id }
}
