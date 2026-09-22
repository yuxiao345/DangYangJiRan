import Foundation
@preconcurrency import CoreData

struct TemplateServiceImpl: TemplateServiceProtocol {
    func createTemplate(_ template: TransactionTemplate, ledger: Ledger, context: NSManagedObjectContext) throws {
        template.ledger = ledger
        try context.save()
    }

    func findByName(_ name: String, ledger: Ledger, context: NSManagedObjectContext) throws -> TransactionTemplate? {
        let request = NSFetchRequest<TransactionTemplate>(entityName: "TransactionTemplate")
        request.predicate = NSPredicate(format: "ledger.id == %@ AND name == %@", ledger.id as CVarArg, name)
        request.fetchLimit = 1
        return try context.fetch(request).first
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
        // 转账模板不使用 分类/成员/商家/项目（见 TransactionType.allowsTagFields）
        let allowsTagFields = template.type.allowsTagFields
        let transaction = Transaction(
            type: template.type,
            amount: template.amount,
            currencyCode: template.currencyCode,
            note: template.note,
            date: date,
            tags: template.tags,
            account: template.account,
            toAccount: template.toAccount,
            category: allowsTagFields ? template.category : nil,
            member: allowsTagFields ? template.member : nil,
            merchant: allowsTagFields ? template.merchant : nil,
            project: allowsTagFields ? template.project : nil,
            context: context
        )
        transaction.ledger = template.ledger
        transaction.template = template
        try context.save()
        return transaction
    }
}
