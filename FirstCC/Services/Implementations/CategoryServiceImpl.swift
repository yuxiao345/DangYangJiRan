import Foundation
import SwiftData

struct CategoryServiceImpl: CategoryServiceProtocol {
    func createCategory(_ category: Category, ledger: Ledger, context: ModelContext) throws {
        category.ledger = ledger
        context.insert(category)
        try context.save()
    }

    func fetchCategories(for ledger: Ledger, type: TransactionType? = nil, context: ModelContext) throws -> [Category] {
        let all = try fetchAllCategories(for: ledger, type: type, context: context)
        return all.filter { !$0.isHidden }
    }

    func fetchAllCategories(for ledger: Ledger, type: TransactionType? = nil, context: ModelContext) throws -> [Category] {
        let ledgerID = ledger.id
        var descriptor: FetchDescriptor<Category>
        if let type = type {
            let typeRaw = type.rawValue
            descriptor = FetchDescriptor<Category>(
                predicate: #Predicate { $0.ledger?.id == ledgerID && $0.typeRaw == typeRaw },
                sortBy: [SortDescriptor(\.sortOrder)]
            )
        } else {
            descriptor = FetchDescriptor<Category>(
                predicate: #Predicate { $0.ledger?.id == ledgerID },
                sortBy: [SortDescriptor(\.sortOrder)]
            )
        }
        return try context.fetch(descriptor)
    }

    func updateCategory(_ category: Category, context: ModelContext) throws {
        try context.save()
    }

    func deleteCategory(_ category: Category, context: ModelContext) throws {
        context.delete(category)
        try context.save()
    }

    func seedDefaults(ledger: Ledger, context: ModelContext) {
        CategorySeeder.seed(modelContext: context, ledger: ledger)
    }
}
