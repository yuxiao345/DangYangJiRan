import Foundation
import SwiftData

struct TemplateServiceImpl: TemplateServiceProtocol {
    func createTemplate(_ template: TransactionTemplate, ledger: Ledger, context: ModelContext) throws {
        template.ledger = ledger
        context.insert(template)
        try context.save()
    }

    func fetchTemplates(for ledger: Ledger, context: ModelContext) throws -> [TransactionTemplate] {
        let ledgerID = ledger.id
        let descriptor = FetchDescriptor<TransactionTemplate>(
            predicate: #Predicate { $0.ledger?.id == ledgerID },
            sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.createdAt)]
        )
        return try context.fetch(descriptor)
    }

    func updateTemplate(_ template: TransactionTemplate, context: ModelContext) throws {
        try context.save()
    }

    func deleteTemplate(_ template: TransactionTemplate, context: ModelContext) throws {
        context.delete(template)
        try context.save()
    }

    func createTransaction(from template: TransactionTemplate, date: Date, context: ModelContext) throws -> Transaction {
        let transaction = Transaction(
            type: template.type,
            amount: template.amount,
            currencyCode: template.currencyCode,
            note: template.note,
            date: date,
            tags: template.tags,
            account: template.account,
            toAccount: template.toAccount,
            category: template.category,
            member: template.member,
            merchant: template.merchant,
            project: template.project
        )
        transaction.ledger = template.ledger
        transaction.template = template
        context.insert(transaction)
        try context.save()
        return transaction
    }
}
