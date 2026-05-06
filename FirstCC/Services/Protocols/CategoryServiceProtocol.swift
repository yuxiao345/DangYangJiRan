import Foundation
import SwiftData

protocol CategoryServiceProtocol {
    func createCategory(_ category: Category, ledger: Ledger, context: ModelContext) throws
    func fetchCategories(for ledger: Ledger, type: TransactionType?, context: ModelContext) throws -> [Category]
    func fetchAllCategories(for ledger: Ledger, type: TransactionType?, context: ModelContext) throws -> [Category]
    func updateCategory(_ category: Category, context: ModelContext) throws
    func deleteCategory(_ category: Category, context: ModelContext) throws
    func seedDefaults(ledger: Ledger, context: ModelContext)
}
