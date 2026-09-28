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

    /// 用模板记一笔。
    ///
    /// ⚠️ **别把它接到 UI 上**（例如"模板 chip → 保存时挂 `template`"）—— 除非同时给交易
    /// 加一个明确的"由规则生成"标记并让 `deduplicateRecurringTransactions` 认这个标记。
    /// 原因：去重是按「账本 + 模板 + 日」判"同一期"的，本方法又会把 `template` 挂上去，
    /// 于是**周期模板**下的这一笔会和当天规则自动生成的那笔撞成同一期，按裁决规则删掉一条 ——
    /// 用户手记的那笔可能在不知情的情况下被当成"重复"清掉。
    /// 眼下全仓没有生产调用点（`AddEditTransactionView.applyTemplate` 只预填表单字段，不挂 `template`），
    /// 所以这是个潜在陷阱而不是线上 bug。
    /// 走那条路要先做两件事：标记必须**随记录同步**（否则各端算出的保留者不一致），
    /// 且它是 schema 变更 —— 要动 `FirstCC.xcdatamodeld` 并按需部署 CloudKit schema。
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
