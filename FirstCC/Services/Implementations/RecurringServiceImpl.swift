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
        let now = Date()
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
            let dayKey = "\(tmpl.id.uuidString)-\(Int(cal.startOfDay(for: tx.date).timeIntervalSince1970))"
            existingByDay[dayKey] = true
        }

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
                let dayKey = "\(template.id.uuidString)-\(Int(cal.startOfDay(for: nextDate).timeIntervalSince1970))"
                if existingByDay[dayKey] == true {
                    rule.nextGenerateDate = following; break
                }

                let signedAmt = signedAmount(amount: template.amount, type: template.type, direction: nil)
                let transaction = Transaction(
                    type: template.type, amount: signedAmt,
                    currencyCode: template.currencyCode, note: template.note, date: nextDate,
                    tags: template.tags, account: template.account, toAccount: template.toAccount,
                    category: template.category, member: template.member,
                    merchant: template.merchant, project: template.project, context: context
                )
                transaction.ledger = template.ledger
                transaction.template = template

                existingByDay[dayKey] = true  // 更新查找表防止同次调用内重复
                rule.lastGeneratedDate = nextDate
                rule.nextGenerateDate = following
                break
            }
        }

        try context.save()
    }

    /// 跨设备去重：移除同一模板+同一天生成的重复周期交易。
    /// 应在 CloudKit 远程同步完成后调用，清理其他设备独立创建的重复记录。
    func deduplicateRecurringTransactions(context: NSManagedObjectContext) throws {
        let request = NSFetchRequest<Transaction>(entityName: "Transaction")
        request.predicate = NSPredicate(format: "template != nil")
        request.sortDescriptors = [NSSortDescriptor(key: "modifiedAt", ascending: false)]
        let transactions = try context.fetch(request)
        let cal = Calendar.current

        var seen: [String: Transaction] = [:]
        var duplicates: [Transaction] = []

        for t in transactions {
            guard let template = t.template else { continue }
            let dayStart = cal.startOfDay(for: t.date)
            let dayKey = "\(template.id.uuidString)-\(Int(dayStart.timeIntervalSince1970))"

            if seen[dayKey] != nil {
                duplicates.append(t)
            } else {
                seen[dayKey] = t
            }
        }

        guard !duplicates.isEmpty else { return }
        for dup in duplicates {
            DiagnosticLog.log("RecurringService: dedup removing duplicate tx id=\(dup.id.uuidString.prefix(8))")
            context.delete(dup)
        }
        try context.save()
        DiagnosticLog.log("RecurringService: dedup removed \(duplicates.count) duplicate recurring transactions")
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
