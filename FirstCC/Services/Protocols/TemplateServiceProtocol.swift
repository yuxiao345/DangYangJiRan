import Foundation
@preconcurrency import CoreData

protocol TemplateServiceProtocol {
    func createTemplate(_ template: TransactionTemplate, ledger: Ledger, context: NSManagedObjectContext) throws
    func fetchTemplates(for ledger: Ledger, context: NSManagedObjectContext) throws -> [TransactionTemplate]
    func findByName(_ name: String, ledger: Ledger, context: NSManagedObjectContext) throws -> TransactionTemplate?
    func updateTemplate(_ template: TransactionTemplate, context: NSManagedObjectContext) throws
    func deleteTemplate(_ template: TransactionTemplate, context: NSManagedObjectContext) throws
    func createTransaction(from template: TransactionTemplate, date: Date, context: NSManagedObjectContext) throws -> Transaction
}
