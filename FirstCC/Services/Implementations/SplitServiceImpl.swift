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
            // 长度必须一致：下面的循环只写 members.count 份 entry，而 balancedToTotal 把差额
            // 补给 amounts 的**最后一个元素** —— 少了会越界崩，多了则多出的那份不入库、
            // 差额落空、`settlementStatus` 照样到不了 `.settled`。两种错配都在这里挡掉。
            guard let amounts, amounts.count == members.count else { throw SplitError.invalidAmounts }
            entryAmounts = amounts
        }

        // 三种模式统一兜底：保证 sum(entries) == totalAmount（详见 balancedToTotal）
        let shares = Self.balancedToTotal(entryAmounts, totalAmount: totalAmount)

        for (index, member) in members.enumerated() {
            let entry = SplitEntry(
                amount: shares[index],
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
    /// 这里保证的是 `.equal` 这一支的**分配方式**（尽量均匀）；
    /// 「合计等于总额」这个不变量由 `createSplit` 里统一调用的 `balancedToTotal` 兜底，
    /// 对它而言本函数的输出差值是 0，属空操作。
    static func equalShares(totalAmount: Decimal, count: Int) -> [Decimal] {
        // 上层 UI 会拦住空选，但这里必须自保：Int64 除以 0 是运行时 trap，不是抛错
        guard count > 0 else { return [] }
        let totalFen = totalAmount.fenValue
        let base = totalFen / Int64(count)
        var shares = Array(repeating: base, count: count)
        shares[count - 1] += totalFen - base * Int64(count)
        return shares.map { Decimal($0) / 100 }
    }

    /// 把分摊金额归一到「**合计 == 总额**」，差额补给最后一份。
    ///
    /// 三种模式统一走这里。为什么需要它：**每一份各自按分截断**，合计就可能少于总额。
    /// `.equal` 由 `equalShares` 保证合计精确（走到这里差值为 0，是空操作）；
    /// `.percentage`/`.fixed` 的金额由调用方传入，除不尽时必然凑不齐 ——
    /// 实测 ¥99.99 按 33/33/34 得 `3299+3299+3399 = 9997`，比总额少 **2** 分。
    ///
    /// 为什么必须补齐：`SplitGroup.settlementStatus` 的判据是 `totalPaid >= totalAmount`，
    /// 合计补不齐就永远到不了 `.settled`，而 `SplitDetailView` 的「一键结算」按钮门控是
    /// `settlementStatus != .settled` —— 于是按钮永不消失，还一直挂着「剩余 ¥0.01」。
    ///
    /// 这是**有意吸收**调用方的差额，不是校验：把「合计必须对」的保证从 UI 收进 service。
    /// 差额大小受 `人数−1` 分约束（真按比例算的话），若调用方给出完全对不上的金额，
    /// 就由最后一份全额吸收。
    ///
    /// 保证的范围：**差额补在 `amounts` 的最后一个元素上**，而 `createSplit` 只写
    /// `members.count` 份 entry，所以「写进去的份数合计等于总额」只在
    /// **`amounts.count == members.count`** 时成立 —— 这个前提由 `createSplit` 的
    /// `.percentage`/`.fixed` 分支用 `guard` 保证（错配直接抛 `invalidAmounts`）。
    /// 本函数自己**不做长度校验**：它是纯函数，只对给定的数组负责。
    static func balancedToTotal(_ amounts: [Decimal], totalAmount: Decimal) -> [Decimal] {
        var fen = amounts.map(\.fenValue)
        // 空数组时下面 fen.count - 1 会越界；members 为空时本函数本就不该造出任何 entry
        guard !fen.isEmpty else { return [] }
        fen[fen.count - 1] += totalAmount.fenValue - fen.reduce(0, +)
        return fen.map { Decimal($0) / 100 }
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
