import Foundation
@preconcurrency import CoreData

struct TemplateServiceImpl: TemplateServiceProtocol {
    func createTemplate(_ template: TransactionTemplate, ledger: Ledger, context: NSManagedObjectContext) throws {
        template.ledger = ledger
        try context.save()
    }

    func fetchTemplates(for ledger: Ledger, context: NSManagedObjectContext) throws -> [TransactionTemplate] {
        let ledgerID = ledger.id
        let request = NSFetchRequest<TransactionTemplate>(entityName: "TransactionTemplate")
        request.predicate = NSPredicate(format: "ledger.id == %@", ledgerID as CVarArg)
        request.sortDescriptors = [NSSortDescriptor(key: "sortOrder", ascending: true), NSSortDescriptor(key: "createdAt", ascending: true)]
        return try context.fetch(request)
    }

    func updateTemplate(_ template: TransactionTemplate, context: NSManagedObjectContext) throws {
        try context.save()
    }

    func deleteTemplate(_ template: TransactionTemplate, context: NSManagedObjectContext) throws {
        context.delete(template)
        try context.save()
    }

    func createTransaction(from template: TransactionTemplate, date: Date, context: NSManagedObjectContext) throws -> Transaction {
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
            project: template.project,
            context: context
        )
        transaction.ledger = template.ledger
        transaction.template = template
        try context.save()
        return transaction
    }
}
