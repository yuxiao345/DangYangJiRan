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

    /// 停用周期账：删掉规则，模板本身留下。
    ///
    /// ⚠️ 本方法会把 `template.recurringRule` 置 nil，而 `deduplicateRecurringTransactions`
    /// 正是拿"模板挂没挂规则"当判重范围的判据 —— 一旦调用，该模板名下已生成的交易立即退出
    /// 判重范围，其中可能存在的跨设备重复就再也清不掉了。
    /// 目前**全仓没有生产调用点**（UI 的"停用"走 `toggleActive`，规则保留），所以是潜伏缺口；
    /// 要把"停用"接回这里之前，先给交易加一个显式的"由规则生成"标记（详见该方法的注释）。
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
            existingByDay[Self.occurrenceKey(ledgerID: tmpl.ledger?.id, templateID: tmpl.id, date: tx.date, calendar: cal)] = true
        }

        var didInsert = false
        for rule in rules {
            guard let template = rule.template else { continue }
            guard var nextDate = rule.nextGenerateDate else { continue }

            while nextDate <= now {
                let following = RecurringRule.calculateNextDate(
                    from: nextDate, frequency: rule.frequency, interval: Int(rule.interval)
                )

                // 日期必须前进，否则下面这个 `while` 会原地打转把主线程卡死：
                // `following == nextDate` 时 `following <= now` 恒成立，`nextDate` 永不变化。
                // 可达路径：`setRecurring` 是协议公开 API，interval 传 0 时 `calculateNextDate`
                // 加 0 就是同一天；它的 `?? date` 兜底在 `byAdding` 失败时同样返回原日期。
                // 两个平台的间隔 Stepper 限 1…99，所以眼下只有 API 与测试能触发。
                guard following > nextDate else {
                    DiagnosticLog.log("RecurringService: rule \(rule.id.uuidString.prefix(8)) 的下一次日期没有前进（interval=\(rule.interval)），跳过本期生成")
                    break
                }

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
    /// **只管周期模板**：判重范围是「此刻挂着 `recurringRule` 的模板」名下那些交易，
    /// 因为"同一期"这个概念只对自动生成的期次成立。**从未启用过**周期规则的模板名下
    /// 同一天的两笔是用户自己记的两笔，不是重复（细节与代价见循环里的注释）。
    ///
    /// **保留者必须由每台设备独立算出同一个结论**，否则两端可能各删掉对方那条，两条全没。
    /// 判据按序：
    /// 1. 有人手动改过的那条优先 —— 机器自己补生成的那条往往比用户的修正"更新"，
    ///    按时间裁决会删掉用户手改的那条（Apple Music 涨价那次就是这么丢的）；
    /// 2. 同一组内比时间戳，留较晚的那条：都被人改过时看 `modifiedAt`（代表用户最新意图），
    ///    都没被改过时看 `createdAt` —— 后生成的那台设备读到的是更晚的模板值。模板改价后，
    ///    先收到变更的设备和后收到的那台会各按新旧价生成一笔，两条都没被手改，
    ///    只比 UUID 会有一半概率留下旧价那条；
    /// 3. 时间戳也相同时，留 `id` 最小的那条 —— UUID 全局唯一且可全序比较，所以各端选出的
    ///    保留者一致（Apple 官方 sample "Remove duplicate data" 的裁决方式）。
    func deduplicateRecurringTransactions(context: NSManagedObjectContext) throws {
        let request = NSFetchRequest<Transaction>(entityName: "Transaction")
        request.predicate = NSPredicate(format: "template != nil")
        let transactions = try context.fetch(request)
        let cal = Calendar.current

        var copiesByOccurrence: [String: [Transaction]] = [:]
        for t in transactions {
            // 只判**周期模板**的期次：`template != nil` 这个条件本身太宽，它同样圈得进
            // 「用户拿某个普通模板手动记的一笔」（`TemplateServiceImpl.createTransaction(from:)`
            // 会挂 `template`）。那种交易从来没有对应的"自动生成的那一期"，同一天两条
            // 只是用户当天记了两笔，按"同一期"裁决就会删掉其中一条 —— 那是删用户的账。
            //
            // 代价（两处，都是已知的）：
            // 1. 判据是"模板**此刻**挂没挂规则"，所以 `disableRecurring` 过的模板（规则被删、
            //    `template.recurringRule` 置 nil）名下若还留着跨设备重复，就此永久退出判重范围、
            //    再也合不上。眼下不打紧：`disableRecurring` 全仓**没有生产调用点**，UI 里的
            //    "停用"走的是 `toggleActive`（只翻 `isActive`，规则保留），"删除"走的是删模板
            //    （`Transaction.template` 的删除规则是 Nullify，两边都脱范）。一旦有人把
            //    `disableRecurring` 接回 UI，这条就会变成真缺口 —— 届时该改用显式的
            //    "由规则生成"标记，而不是拿规则在不在当代理条件。
            // 2. CloudKit 分批导入的中间态（`recurringRule` 还没解析过来）会被跳过一轮。
            //    能自愈：去重挂在 `NSPersistentStoreRemoteChange` 上、每次远程变更都跑
            //    （`AppContainer.deduplicateRecurring`，无限流），规则到位那一批会再触发一次。
            guard let template = t.template, template.recurringRule != nil else { continue }
            let dayKey = Self.occurrenceKey(ledgerID: template.ledger?.id, templateID: template.id, date: t.date, calendar: cal)
            copiesByOccurrence[dayKey, default: []].append(t)
        }

        var duplicates: [Transaction] = []
        for copies in copiesByOccurrence.values where copies.count > 1 {
            let ranked = copies.sorted { a, b in
                let aEdited = Self.isManuallyEdited(a)
                let bEdited = Self.isManuallyEdited(b)
                if aEdited != bEdited { return aEdited }
                // 同组内比时间戳，取较晚的：都被人改过看 `modifiedAt`（用户最新意图），
                // 都没被改过看 `createdAt`（后生成的那台读到的是更晚的模板值）。
                // 两个时间戳都随记录同步，各端能独立算出同一结论。
                let aStamp = aEdited ? a.modifiedAt : a.createdAt
                let bStamp = bEdited ? b.modifiedAt : b.createdAt
                if aStamp != bStamp { return aStamp > bStamp }
                // 时间戳相同才落到 UUID 比较，避免排序谓词对等导致各端顺序不一致。
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
    ///
    /// 账本一律取自**模板**（`template.ledger`），三处调用点都是 —— 不要改从交易那边取。
    /// 交易身上那条 ledger 关系在 CloudKit 分批导入的中间态下可能还没解析（暂时为 nil），
    /// 于是"建索引"与"查索引"会算出分属两个桶的键：既会重复生成一笔，又会让去重永远合不上
    /// （一个落在 `-` 桶、一个落在真账本桶）。正常路径下两者本就相等
    /// （生成时 `transaction.ledger = template.ledger`），所以统一取模板不改变正常行为。
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
