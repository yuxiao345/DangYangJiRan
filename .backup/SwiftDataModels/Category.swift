import Foundation
import SwiftData

@Model
final class Category {
    var id: UUID = UUID()
    var name: String = ""
    var iconName: String = "questionmark"
    var colorHex: String = "#666666"
    var typeRaw: String = TransactionType.expense.rawValue
    var isSystem: Bool = false
    var isHidden: Bool = false
    var sortOrder: Int = 0

    var ledger: Ledger?

    var parent: Category?

    @Relationship(deleteRule: .cascade, inverse: \Category.parent)
    var children: [Category]? = []

    @Relationship(deleteRule: .nullify, inverse: \Transaction.category)
    var transactions: [Transaction]? = []

    @Relationship(deleteRule: .nullify, inverse: \BudgetItem.category)
    var budgetItems: [BudgetItem]? = []

    @Relationship(deleteRule: .nullify, inverse: \TransactionTemplate.category)
    var templateTransactions: [TransactionTemplate]? = []

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
