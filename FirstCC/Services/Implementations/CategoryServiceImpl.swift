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
        // Sort hierarchically: parent categories first, then children grouped under their parent
        return all.sorted { a, b in
            let aGroup = a.parent?.sortOrder ?? a.sortOrder
            let bGroup = b.parent?.sortOrder ?? b.sortOrder
            if aGroup != bGroup { return aGroup < bGroup }
            // Within same group: parent before children
            if a.parent == nil && b.parent != nil { return true }
            if a.parent != nil && b.parent == nil { return false }
            return a.sortOrder < b.sortOrder
        }
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
