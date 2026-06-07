import Foundation
@preconcurrency import CoreData

protocol CategoryServiceProtocol {
    func createCategory(_ category: Category, ledger: Ledger, context: NSManagedObjectContext) throws
    func fetchCategories(for ledger: Ledger, type: TransactionType?, context: NSManagedObjectContext) throws -> [Category]
    func fetchAllCategories(for ledger: Ledger, type: TransactionType?, context: NSManagedObjectContext) throws -> [Category]
    func findByName(_ name: String, ledger: Ledger, context: NSManagedObjectContext) throws -> Category?
    func updateCategory(_ category: Category, context: NSManagedObjectContext) throws
    func deleteCategory(_ category: Category, context: NSManagedObjectContext) throws
    func seedDefaults(ledger: Ledger, context: NSManagedObjectContext)
}
