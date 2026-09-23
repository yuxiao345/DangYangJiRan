import Foundation
@preconcurrency import CoreData

struct SplitServiceImpl: SplitServiceProtocol {
    func createSplit(
        totalAmount: Decimal,
        currencyCode: String,
        splitType: SplitType,
        members: [Member],
        amounts: [Decimal]?,
        note: String?,
        date: Date,
        transaction: Transaction,
        ledger: Ledger,
        context: NSManagedObjectContext
    ) throws -> SplitGroup {
        let group = SplitGroup(
            totalAmount: totalAmount,
            currencyCode: currencyCode,
            splitType: splitType,
            note: note,
            date: date,
            context: context
        )
        group.ledger = ledger
        group.transaction = transaction
        transaction.splitGroup = group
        transaction.isSplitParent = true

        let entryAmounts: [Decimal]
        switch splitType {
        case .equal:
            entryAmounts = Self.equalShares(totalAmount: totalAmount, count: members.count)
        case .percentage, .fixed:
            guard let amounts else { throw SplitError.invalidAmounts }
            entryAmounts = amounts
        }

        for (index, member) in members.enumerated() {
            let entry = SplitEntry(
                amount: entryAmounts[index],
                member: member,
                context: context
            )
            entry.splitGroup = group
        }

        try saveAndNotify(context: context)
        return group
    }

    /// 等额分摊的每人金额，**按分均分、余数补给最后一名成员**。
    ///
    /// 这是 equal 分摊算法的唯一实现——`SplitFormView` 的「均分金额」预览也调它，
    /// 不要再在 View 里写 `amount / count`，否则预览与写库会差 1 分。
    ///
    /// 为什么不能写 `totalAmount / Decimal(count)`：除不尽时 `Decimal` 除法会填满
    /// 38 位有效数字，每份再按分截断后**合计少于** `totalAmount`
    /// （¥100 分 3 人 → 每人 3333，合计 9999）。于是
    /// `SplitGroup.settlementStatus` 的 `totalPaid >= totalAmount` 永不成立，
    /// 全部付清也停在 `.partial` —— `SplitDetailView` 的「一键结算」按钮门控是
    /// `settlementStatus != .settled`，于是那按钮永不消失、还挂着「剩余 ¥0.01」。
    ///
    /// 先取整到分再均分，于是只要 **`count ≥ 1`** 就恒有 `sum(shares) == totalAmount`，
    /// 与 `SplitGroup.totalAmountInFen`（同样是分）口径一致。
    ///
    /// ⚠️ **这个不变量目前只对 `.equal` 成立。** `.percentage` / `.fixed` 直接用调用方
    /// 传来的金额、每份各按分截断，合计仍可能**少于**总额、仍会卡在 `.partial`
    /// （实测：¥7.77 按 33/33/34 百分比 → 256+256+264 = 776 分 ≠ 777 分）。
    /// 未修——修它要改另外两个分支的语义（超出本轮范围），待办见
    /// `.claude/plans/release-checklist.md` §六-8-2。
    static func equalShares(totalAmount: Decimal, count: Int) -> [Decimal] {
        // 上层 UI 会拦住空选，但这里必须自保：Int64 除以 0 是运行时 trap，不是抛错
        guard count > 0 else { return [] }
        let totalFen = totalAmount.fenValue
        let base = totalFen / Int64(count)
        var shares = Array(repeating: base, count: count)
        shares[count - 1] += totalFen - base * Int64(count)
        return shares.map { Decimal($0) / 100 }
    }

    func markEntryPaid(_ entry: SplitEntry, context: NSManagedObjectContext) throws {
        entry.isPaid = true
        entry.paidDate = Date.now
        try saveAndNotify(context: context)
    }

    func settleSplit(_ splitGroup: SplitGroup, context: NSManagedObjectContext) throws {
        for entry in splitGroup.entries ?? [] {
            if !entry.isPaid {
                entry.isPaid = true
                entry.paidDate = Date.now
            }
        }
        try saveAndNotify(context: context)
    }

    private func saveAndNotify(context: NSManagedObjectContext) throws {
        try context.save()
        NotificationCenter.default.post(name: .transactionDidChange, object: nil)
    }

    func fetchSplits(for ledger: Ledger, context: NSManagedObjectContext) throws -> [SplitGroup] {
        let ledgerID = ledger.id
        let request = NSFetchRequest<SplitGroup>(entityName: "SplitGroup")
        request.predicate = NSPredicate(format: "ledger.id == %@", ledgerID as CVarArg)
        request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
        return try context.fetch(request)
    }
}

enum SplitError: LocalizedError {
    case invalidAmounts

    var errorDescription: String? {
        switch self {
        case .invalidAmounts:
            return String(localized: "分摊金额配置无效")
        }
    }
}
