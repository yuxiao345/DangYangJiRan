import Foundation
@preconcurrency import CoreData

struct RecurringServiceImpl: RecurringServiceProtocol {
    func setRecurring(
        template: TransactionTemplate,
        frequency: RecurringFrequency,
        interval: Int,
        startDate: Date,
        endDate: Date?,
        context: NSManagedObjectContext
    ) throws -> RecurringRule {
        let rule: RecurringRule
        if let existing = template.recurringRule {
            let scheduleChanged = existing.frequency != frequency
                || existing.interval != Int64(interval)
                || existing.startDate != startDate

            existing.frequency = frequency
            existing.interval = Int64(interval)
            existing.startDate = startDate
            existing.endDate = endDate
            existing.isActive = true

            if scheduleChanged {
                if let currentNext = existing.nextGenerateDate {
                    existing.nextGenerateDate = max(startDate, currentNext)
                } else {
                    existing.nextGenerateDate = startDate
                }
            }
            rule = existing
        } else {
            rule = RecurringRule(
                frequency: frequency,
                interval: interval,
                startDate: startDate,
                endDate: endDate,
                context: context
            )
            rule.template = template
            template.recurringRule = rule
            template.isRecurring = true
        }
        try context.save()
        return rule
    }

    func disableRecurring(template: TransactionTemplate, context: NSManagedObjectContext) throws {
        if let rule = template.recurringRule {
            rule.template = nil
            template.recurringRule = nil
            context.delete(rule)
        }
        template.isRecurring = false
        try context.save()
    }

    func toggleActive(for rule: RecurringRule, context: NSManagedObjectContext) throws {
        rule.isActive.toggle()
        try context.save()
    }

    func processDueRecurring(context: NSManagedObjectContext) throws {
        let now = Date.now
        let request = NSFetchRequest<RecurringRule>(entityName: "RecurringRule")
        request.predicate = NSPredicate(format: "isActive == YES")
        let rules = try context.fetch(request)
        let cal = Calendar.current

        // 批量预取所有模板关联的已存在交易，构建查找表，避免逐条 fetch
        let existingReq = NSFetchRequest<Transaction>(entityName: "Transaction")
        existingReq.predicate = NSPredicate(format: "template IN %@", rules.compactMap(\.template))
        let existingTxs = (try? context.fetch(existingReq)) ?? []
        var existingByDay: [String: Bool] = [:]
        for tx in existingTxs {
            guard let tmpl = tx.template else { continue }
            existingByDay[Self.occurrenceKey(ledgerID: tx.ledger?.id, templateID: tmpl.id, date: tx.date, calendar: cal)] = true
        }

        var didInsert = false
        for rule in rules {
            guard let template = rule.template else { continue }
            guard var nextDate = rule.nextGenerateDate else { continue }

            while nextDate <= now {
                let following = RecurringRule.calculateNextDate(
                    from: nextDate, frequency: rule.frequency, interval: Int(rule.interval)
                )

                // 跳过已错过的期间
                guard following > now else {
                    if let endDate = rule.endDate, nextDate > endDate { rule.isActive = false; break }
                    nextDate = following
                    continue
                }

                // 结束日期检查
                if let endDate = rule.endDate, nextDate > endDate { rule.isActive = false; break }

                // 本地去重
                let dayKey = Self.occurrenceKey(ledgerID: template.ledger?.id, templateID: template.id, date: nextDate, calendar: cal)
                if existingByDay[dayKey] == true {
                    rule.nextGenerateDate = following; break
                }

                let signedAmt = signedAmount(amount: template.amount, type: template.type, direction: nil)
                // 转账模板不使用 分类/成员/商家/项目（见 TransactionType.allowsTagFields）
                let allowsTagFields = template.type.allowsTagFields
                let transaction = Transaction(
                    type: template.type, amount: signedAmt,
                    currencyCode: template.currencyCode, note: template.note, date: nextDate,
                    tags: template.tags, account: template.account, toAccount: template.toAccount,
                    category: allowsTagFields ? template.category : nil, member: allowsTagFields ? template.member : nil,
                    merchant: allowsTagFields ? template.merchant : nil, project: allowsTagFields ? template.project : nil, context: context
                )
                transaction.ledger = template.ledger
                transaction.template = template

                existingByDay[dayKey] = true  // 更新查找表防止同次调用内重复
                didInsert = true
                rule.lastGeneratedDate = nextDate
                rule.nextGenerateDate = following
                break
            }
        }

        try context.save()
        // 主动通知界面重载：本函数插入的交易不走 `TransactionServiceImpl` 的修改路径，
        // 没有别的地方会发这个通知。调用点现在都在首次 CloudKit 导入之后
        // （见 `CoreDataStack.waitForImportSinceLaunch`），即晚于视图首次加载，
        // 不发通知的话已上屏的总览/流水/账户列表就一直看不到新生成的这几笔。
        if didInsert {
            NotificationCenter.default.post(name: .transactionDidChange, object: nil)
        }
    }

    /// 跨设备去重：移除同一模板+同一天生成的重复周期交易。
    /// 应在 CloudKit 远程同步完成后调用，清理其他设备独立创建的重复记录。
    ///
    /// **保留者必须由每台设备独立算出同一个结论**，否则两端可能各删掉对方那条，两条全没。
    /// 判据按序：
    /// 1. 有人手动改过的那条优先 —— 机器自己补生成的那条往往比用户的修正"更新"，
    ///    按时间裁决会删掉用户手改的那条（Apple Music 涨价那次就是这么丢的）；
    /// 2. 两条都被人改过时，留后改的那条（代表用户最新意图）；
    /// 3. 其余情况留 `id` 最小的那条 —— UUID 全局唯一且可全序比较，所以各端选出的保留者
    ///    一致（Apple 官方 sample "Remove duplicate data" 的裁决方式）。两条内容一致时也走这条，
    ///    删掉哪个都不丢信息。
    func deduplicateRecurringTransactions(context: NSManagedObjectContext) throws {
        let request = NSFetchRequest<Transaction>(entityName: "Transaction")
        request.predicate = NSPredicate(format: "template != nil")
        let transactions = try context.fetch(request)
        let cal = Calendar.current

        var copiesByOccurrence: [String: [Transaction]] = [:]
        for t in transactions {
            guard let template = t.template else { continue }
            let dayKey = Self.occurrenceKey(ledgerID: t.ledger?.id, templateID: template.id, date: t.date, calendar: cal)
            copiesByOccurrence[dayKey, default: []].append(t)
        }

        var duplicates: [Transaction] = []
        for copies in copiesByOccurrence.values where copies.count > 1 {
            let ranked = copies.sorted { a, b in
                let aEdited = Self.isManuallyEdited(a)
                let bEdited = Self.isManuallyEdited(b)
                if aEdited != bEdited { return aEdited }
                // 两条都被人改过：后改的那条是用户最新意图。两边时间戳相同时落到
                // 末尾的 UUID 比较，避免排序谓词对等导致各端顺序不一致。
                if aEdited, a.modifiedAt != b.modifiedAt { return a.modifiedAt > b.modifiedAt }
                return a.id.uuidString < b.id.uuidString
            }
            duplicates.append(contentsOf: ranked.dropFirst())
        }

        guard !duplicates.isEmpty else { return }
        for dup in duplicates {
            DiagnosticLog.log("RecurringService: dedup removing tx id=\(dup.id.uuidString.prefix(8)) amount=\(dup.amount) manualEdit=\(Self.isManuallyEdited(dup))")
            context.delete(dup)
        }
        try context.save()
        DiagnosticLog.log("RecurringService: dedup removed \(duplicates.count) duplicate recurring transactions")
        // 去重删的是屏幕上的行，不发通知那几行会留在列表里，直到用户手动切页才消失。
        NotificationCenter.default.post(name: .transactionDidChange, object: nil)
    }

    /// 「同一期」的查找键：账本 + 模板 + 日。
    ///
    /// 三个维度缺一不可，生成（`processDueRecurring`）与去重（`deduplicateRecurringTransactions`）
    /// 共用这一份，避免两处各写一份、改一处漏一处 —— 曾经就是这样漏的：去重加了账本维度、
    /// 生成没加，于是复制出来的账本每一期都被判成"已存在"而静默不生成。
    ///
    /// 账本这一维不是可选的：`LedgerDeepCopyService` 复制账本时原样保留 `Template.id`
    /// （`copyTemplate`/`copyRecurringRule` 都带 `n.id = src.id`），所以源账本与副本里
    /// 各有一个 id 相同的模板与规则。少了账本维度，"副本模板的这一天"与"源模板的这一天"
    /// 会被当成同一期。
    private static func occurrenceKey(
        ledgerID: UUID?,
        templateID: UUID,
        date: Date,
        calendar: Calendar
    ) -> String {
        let ledger = ledgerID?.uuidString ?? "-"
        let day = Int(calendar.startOfDay(for: date).timeIntervalSince1970)
        return "\(ledger)-\(templateID.uuidString)-\(day)"
    }

    /// 这条交易是否被人手动改过。
    ///
    /// `Transaction.modifiedAt` 的写入点只有两类：插入时（`awakeFromInsert`，与 `createdAt`
    /// 同一时刻）和用户编辑路径（`AddEditTransactionView.save`；`TransactionServiceImpl.updateTransaction`
    /// 同样会写，但全仓当前没有调用点）。CloudKit 导入不会改它，且两个属性都随记录同步，
    /// 所以「`modifiedAt` 明显晚于 `createdAt`」在各设备上结论一致，可以充当裁决依据。
    /// （`LedgerDeepCopyService` 复制账本时原样搬运该值，标志位语义不变。）
    ///
    /// 留 1 秒余量，避免同一次插入里两个时间戳的细微抖动被误判成"人改过"。
    private static let manualEditThreshold: TimeInterval = 1

    private static func isManuallyEdited(_ transaction: Transaction) -> Bool {
        transaction.modifiedAt.timeIntervalSince(transaction.createdAt) > manualEditThreshold
    }

    func nextGenerateDate(for rule: RecurringRule) -> Date? {
        rule.nextGenerateDate
    }

    func processAndDeduplicate(context: NSManagedObjectContext) throws {
        try processDueRecurring(context: context)
        try deduplicateRecurringTransactions(context: context)
    }

    func fetchRules(for ledger: Ledger, context: NSManagedObjectContext) throws -> [RecurringRule] {
        let request = NSFetchRequest<RecurringRule>(entityName: "RecurringRule")
        let allRules = try context.fetch(request)
        return allRules.filter { $0.template?.ledger?.id == ledger.id }
    }

    func fetchActiveRules(for ledger: Ledger, context: NSManagedObjectContext) throws -> [RecurringRule] {
        let allRules = try fetchRules(for: ledger, context: context)
        return allRules.filter { $0.isActive }
    }
}
