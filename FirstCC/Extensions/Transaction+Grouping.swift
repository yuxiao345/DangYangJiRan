import Foundation

/// 一组「同一天」的交易。
///
/// `day` 同时是分组身份和排序依据 —— 它是归零到日界的 `Date`，跨年不会撞车；
/// `title` 只用于渲染，**不要**拿它参与分组、排序，也不要当 `ForEach` 的 id。
///
/// 反面教材（本次修掉的 bug）：原先分组身份是
/// `.dateTime.month(.abbreviated).day(.defaultDigits)` 生成的显示字符串（**没有年份**），
/// 于是 2025-06-09 和 2026-06-09 被并进同一组；`AccountDetailView.dateBalances`
/// 又拿同一个字符串当余额字典的 key，撞车那一组之后的每日期末余额整体偏移
/// （回推循环里 `running` 被一次性多减掉了更早年份那天的净额）。
/// 分组身份一旦用显示字符串，正确性就取决于 locale 和「同月同日是否跨年」。
struct TransactionDayGroup: Identifiable {
    let day: Date
    let title: String
    let transactions: [Transaction]

    var id: Date { day }
}

/// 日期分组标题的取法。标题只影响渲染，不影响分组身份。
enum DayGroupTitleStyle {
    /// 今天 / 昨天 / 「6月9日」（往年补年份）。用于流水列表、账户明细这种连续跨天的场景。
    case relative
    /// 完整日期（含年份、随 locale）。用于可能跨年的搜索结果。
    case fullDate
}

/// 日期分组的显示标题。**不是**分组身份，见 `TransactionDayGroup`。
private func dayGroupTitle(for day: Date, calendar cal: Calendar, style: DayGroupTitleStyle) -> String {
    switch style {
    case .relative:
        if cal.isDateInToday(day) { return String(localized: "今天") }
        if cal.isDateInYesterday(day) { return String(localized: "昨天") }
        // 不传 locale，用 Locale.autoupdatingCurrent 自适应系统语言 ——
        // 不要在这里写死 zh_CN，否则英文界面下这个页面是中文格式的日期。
        if cal.isDate(day, equalTo: .now, toGranularity: .year) {
            return day.shortDisplay
        }
        // 往年补年份：账户明细拉的是全量历史，跨年会撞出两个一模一样的「6月9日」标题
        // （分组身份已按 Date 分开、余额也对了，但标题仍会让用户分不清是哪一年）。
        // 流水列表按月显示、翻到往年月份时同样受益。
        return day.formatted(.dateTime.year().month(.abbreviated).day(.defaultDigits))
    case .fullDate:
        return day.formatted(date: .complete, time: .omitted)
    }
}

extension Array where Element == Transaction {
    /// 按自然日分组：组间按真实日期倒序，组内按真实时间倒序。
    ///
    /// 「今天 / 昨天」不再是特殊分支 —— 按 `day` 倒序时它们天然排在最前，标题交给
    /// `dayGroupTitle`，所以整段逻辑只剩「按 Date 分组 + 排序」一条路径。
    func groupedByDay(titleStyle: DayGroupTitleStyle = .relative) -> [TransactionDayGroup] {
        let cal = Calendar.current
        return Dictionary(grouping: self) { cal.startOfDay(for: $0.date) }
            .sorted { $0.key > $1.key }
            .map { day, transactions in
                TransactionDayGroup(
                    day: day,
                    title: dayGroupTitle(for: day, calendar: cal, style: titleStyle),
                    transactions: transactions.sorted { $0.date > $1.date }
                )
            }
    }

    /// 排除可报销支出及其关联的报销结算收入，用于统计/报表等非流水口径。
    func excludingReimbursementTransactions() -> [Transaction] {
        let settlementIDs = Set(compactMap(\.reimbursedById))
        return filter { t in
            if t.type == .expense, t.isReimbursable { return false }
            if t.type == .income, settlementIDs.contains(t.id) { return false }
            return true
        }
    }

    /// Keep only one side of each transfer (outflow, amount < 0). Other types pass through unchanged.
    func deduplicatingTransfers() -> [Transaction] {
        var seen = Set<UUID>()
        return filter { t in
            if t.type == .transfer, let gid = t.transferGroupId {
                if seen.contains(gid) { return false }
                if t.amount < 0 {
                    seen.insert(gid)
                    return true
                }
                return false
            }
            return true
        }
    }
}

extension Array where Element == TransactionDayGroup {
    /// 每个日期组的期末余额：从当前余额出发，按组由新到旧逐步回推。
    ///
    /// 前提是「一组 = 一个自然日」且已按 `day` 倒序（`groupedByDay` 的输出即是）；
    /// 分组身份若用显示字符串导致跨年并组，回推会被带偏，见 `TransactionDayGroup`。
    ///
    /// 金额口径用 `amount`（账户自身币种），与回推起点 `calculateBalance` 的取法一致；
    /// 外币账户下 `ledgerAmount` 是折算后的基准币种金额，会与该行标的币种不符。
    ///
    /// 已知边界（沿用自旧实现，非本函数职责）：`calculateBalance` 对借贷账户做符号反转
    /// 与已结算抵扣、并排除 `isReconciled == true` 的交易；这里只是朴素 `Σ amount`，
    /// 这两种情况下回推结果与 `balance` 对不上。修它需重新对齐借贷/对账口径，不在本修复范围。
    func dailyClosingBalances(startingFrom closingBalance: Decimal) -> [Date: Decimal] {
        var result: [Date: Decimal] = [:]
        var running = closingBalance
        for group in self {
            result[group.day] = running
            running -= group.transactions.reduce(Decimal.zero) { $0 + $1.amount }
        }
        return result
    }
}

/// 根据交易类型和借贷方向计算签名金额。
/// - isRefund=true 时按 type 决定符号：原 expense 退款 → +abs（原支出变退款收入），原 income 退款 → -abs。
///   这与 createRefund 写入约定保持一致（TransactionServiceImpl.createRefund: original.type == .expense ? absAmount : -absAmount）。
func signedAmount(amount: Decimal, type: TransactionType, direction: LendingDirection? = nil, isRefund: Bool = false) -> Decimal {
    if isRefund {
        return type == .income ? -abs(amount) : abs(amount)
    }
    switch type {
    case .expense: return -abs(amount)
    case .income: return abs(amount)
    case .lending:
        switch direction {
        case .lendOut, .repay: return -abs(amount)
        case .borrowIn, .collect: return abs(amount)
        case .none: return abs(amount)
        }
    case .transfer: return -abs(amount)
    case .adjustment: return amount
    default: return abs(amount)
    }
}

/// 将分类层级（父+子）展平为一维数组，按 sortOrder 排序
func flattenCategoryTree(_ parents: [Category]) -> [Category] {
    var result: [Category] = []
    for parent in parents.sorted(by: { $0.sortOrder < $1.sortOrder }) {
        result.append(parent)
        for child in (parent.children as? Set<Category> ?? []).sorted(by: { $0.sortOrder < $1.sortOrder }) {
            result.append(child)
        }
    }
    return result
}
