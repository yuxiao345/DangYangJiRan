import Foundation
import SwiftData

protocol TemplateServiceProtocol {
    func createTemplate(_ template: TransactionTemplate, ledger: Ledger, context: ModelContext) throws
    func fetchTemplates(for ledger: Ledger, context: ModelContext) throws -> [TransactionTemplate]
    func updateTemplate(_ template: TransactionTemplate, context: ModelContext) throws
    func deleteTemplate(_ template: TransactionTemplate, context: ModelContext) throws
    func createTransaction(from template: TransactionTemplate, date: Date, context: ModelContext) throws -> Transaction
}
