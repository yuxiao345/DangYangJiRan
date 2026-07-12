import Foundation
@preconcurrency import CoreData

@objc(Category)
final class Category: NSManagedObject,  Sendable {
    @NSManaged var id: UUID
    @NSManaged var name: String
    @NSManaged var iconName: String
    @NSManaged var colorHex: String
    @NSManaged var typeRaw: String
    @NSManaged var isSystem: Bool
    @NSManaged var isHidden: Bool
    @NSManaged var sortOrder: Int64

    @NSManaged var ledger: Ledger?
    @NSManaged var parent: Category?
    @NSManaged var children: Set<Category>?
    @NSManaged var transactions: Set<Transaction>?
    @NSManaged var budgetItems: Set<BudgetItem>?
    @NSManaged var templateTransactions: Set<TransactionTemplate>?

    var type: TransactionType {
        get { TransactionType(rawValue: typeRaw) ?? .expense }
        set { typeRaw = newValue.rawValue }
    }

    override func awakeFromInsert() {
        super.awakeFromInsert()
        id = UUID()
    }

    convenience init(
        name: String,
        iconName: String = "questionmark",
        colorHex: String = "#666666",
        type: TransactionType = .expense,
        isSystem: Bool = false,
        isHidden: Bool = false,
        sortOrder: Int = 0,
        parent: Category? = nil,
        context: NSManagedObjectContext
    ) {
        self.init(context: context)
        self.name = name
        self.iconName = iconName
        self.colorHex = colorHex
        self.typeRaw = type.rawValue
        self.isSystem = isSystem
        self.isHidden = isHidden
        self.sortOrder = Int64(sortOrder)
        self.parent = parent
    }
}

extension Category {
    @objc var transactionsList: [Transaction] {
        (transactions ?? []).sorted { $0.date > $1.date }
    }
}

extension Category: Identifiable {}

// MARK: - 分类层级遍历（预算向上汇总用）

extension Category {
    /// 所有后代分类 ID（递归，含子、孙、曾孙...）
    var allDescendantIDs: Set<UUID> {
        var ids = Set<UUID>()
        for child in children ?? [] {
            ids.insert(child.id)
            ids.formUnion(child.allDescendantIDs)
        }
        return ids
    }

    /// 所有祖先分类 ID（父、祖父...，不含自身）
    var allAncestorIDs: Set<UUID> {
        var ids = Set<UUID>()
        var current = parent
        while let p = current {
            ids.insert(p.id)
            current = p.parent
        }
        return ids
    }
}
