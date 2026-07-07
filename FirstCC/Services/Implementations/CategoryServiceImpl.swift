import Foundation
@preconcurrency import CoreData

struct CategoryServiceImpl: CategoryServiceProtocol {
    func createCategory(_ category: Category, ledger: Ledger, context: NSManagedObjectContext) throws {
        category.ledger = ledger
        try context.save()
    }

    func findByName(_ name: String, ledger: Ledger, context: NSManagedObjectContext) throws -> Category? {
        let request = NSFetchRequest<Category>(entityName: "Category")
        request.predicate = NSPredicate(format: "ledger.id == %@ AND name == %@", ledger.id as CVarArg, name)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    func fetchCategories(for ledger: Ledger, type: TransactionType? = nil, context: NSManagedObjectContext) throws -> [Category] {
        let all = try fetchAllCategories(for: ledger, type: type, context: context)
        return all.filter { !$0.isHidden }
    }

    func fetchAllCategories(for ledger: Ledger, type: TransactionType? = nil, context: NSManagedObjectContext) throws -> [Category] {
        let ledgerID = ledger.id
        let request = NSFetchRequest<Category>(entityName: "Category")
        if let type = type {
            let typeRaw = type.rawValue
            request.predicate = NSPredicate(format: "ledger.id == %@ AND typeRaw == %@", ledgerID as CVarArg, typeRaw)
        } else {
            request.predicate = NSPredicate(format: "ledger.id == %@", ledgerID as CVarArg)
        }
        let all = try context.fetch(request)
        // Sort hierarchically: group children under their specific parent, not just by parent sortOrder
        // When multiple parents share the same sortOrder (e.g. 0 for system defaults),
        // we must use parent identity to keep families together.
        // Build lookup: parentID → children, one-pass O(n)
        var childrenByParent: [UUID: [Category]] = [:]
        for cat in all where cat.parent != nil {
            childrenByParent[cat.parent!.id, default: []].append(cat)
        }
        let rootCats = all.filter { $0.parent == nil }.sorted { $0.sortOrder < $1.sortOrder }
        var result: [Category] = []
        var accountedParentIDs = Set<UUID>()
        for root in rootCats {
            result.append(root)
            accountedParentIDs.insert(root.id)
            let children = (childrenByParent[root.id] ?? []).sorted { $0.sortOrder < $1.sortOrder }
            result.append(contentsOf: children)
        }
        // Orphans: children whose parent was filtered out (e.g., hidden or type mismatch)
        let orphans = childrenByParent
            .filter { !accountedParentIDs.contains($0.key) }
            .flatMap { $0.value }
            .sorted { $0.sortOrder < $1.sortOrder }
        result.append(contentsOf: orphans)
        return result
    }

    func updateCategory(_ category: Category, context: NSManagedObjectContext) throws {
        try context.save()
    }

    func deleteCategory(_ category: Category, context: NSManagedObjectContext) throws {
        context.delete(category)
        try context.save()
    }

    func seedDefaults(ledger: Ledger, context: NSManagedObjectContext) {
        CategorySeeder.seed(modelContext: context, ledger: ledger)
    }
}
