import Foundation
@preconcurrency import CoreData

struct CategoryServiceImpl: CategoryServiceProtocol {
    func createCategory(_ category: Category, ledger: Ledger, context: NSManagedObjectContext) throws {
        category.ledger = ledger
        try context.save()
    }

    func fetchCategories(for ledger: Ledger, type: TransactionType? = nil, context: NSManagedObjectContext) throws -> [Category] {
        let all = try fetchAllCategories(for: ledger, type: type, context: context)
        return all.filter { !$0.isHidden }
    }

    func fetchAllCategories(for ledger: Ledger, type: TransactionType? = nil, context: NSManagedObjectContext) throws -> [Category] {
        let ledgerID = ledger.id
        let request = NSFetchRequest<Category>(entityName: "Category")
        request.sortDescriptors = [NSSortDescriptor(key: "sortOrder", ascending: true)]
        if let type = type {
            let typeRaw = type.rawValue
            request.predicate = NSPredicate(format: "ledger.id == %@ AND typeRaw == %@", ledgerID as CVarArg, typeRaw)
        } else {
            request.predicate = NSPredicate(format: "ledger.id == %@", ledgerID as CVarArg)
        }
        return try context.fetch(request)
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
