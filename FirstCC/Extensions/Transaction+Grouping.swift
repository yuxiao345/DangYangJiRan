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

/// 一组「同一个月」的日期组。
///
/// `month` 是归零到月首的 `Date`，同时是分组身份和排序依据；`title` 只用于渲染，
/// **不要**拿它参与分组、排序，也不要当 `ForEach` 的 id —— 与 `TransactionDayGroup`
/// 同一个理由：显示字符串随 locale 变，还可能跨年撞车。
struct TransactionMonthGroup: Identifiable {
    let month: Date
    let title: String
    let dayGroups: [TransactionDayGroup]

    var id: Date { month }

    /// 当月全部交易（跨日组展平）。
    var transactions: [Transaction] { dayGroups.flatMap(\.transactions) }

    /// 当月流入合计（只累加 `amount > 0` 的部分），恒 ≥ 0。口径说明见 `outflow`。
    var inflow: Decimal {
        transactions.reduce(Decimal.zero) { $0 + ($1.amount > 0 ? $1.amount : 0) }
    }

    /// 当月流出合计（只累加 `amount < 0` 的部分），恒 ≤ 0。
    ///
    /// 口径是**原始 `amount` 的正负号**，即「进账 / 出账」，不是按 `type` 分的
    /// 「收入 / 支出」。这么切有两个理由：
    /// ① `inflow + outflow ≡ Σ amount`，与每日期末余额（`dailyClosingBalances` 就是朴素
    ///   `Σ amount` 回推）以及账户余额同口径；
    /// ② 改用 `signedAmount` 按 type 重推符号（转账一律记负）后，表头两个数之和
    ///   就不再等于同期余额变动，头与它下面的日余额会互相矛盾。
    ///
    /// **表头的颜色与它下面那些行的颜色不是同一套语义**，别照着行色去调表头：
    /// 行色按 `type` 走（`TransactionRowView.amountView`：转账恒蓝且抹掉符号、借贷负数为橙、
    /// 支出恒红），表头只有「流入绿 / 流出红」两桶。于是同一笔 `.expense` 退款
    /// （`createRefund` 存成 `type: .expense` + **正** `amount`）在行里是红色 `+¥100`，
    /// 在表头计入流入是绿色 `+¥100`；同一笔转账在转出方页面表头是红色流出、
    /// 在转入方页面表头是绿色流入，而行里两处都是蓝色 `↔`。
    /// 金额是同一笔、颜色不同源，这是刻意保留的差异，不是 bug。
    var outflow: Decimal {
        transactions.reduce(Decimal.zero) { $0 + ($1.amount < 0 ? $1.amount : 0) }
    }
}

/// 月份分组的显示标题。**不是**分组身份，见 `TransactionMonthGroup`。
///
/// 与 `dayGroupTitle(.relative)` 不同：这里**始终带年份** —— 账户明细拉的是全量历史，
/// 只显示「10月」的话，2026 年 10 月和 2025 年 10 月两个分组头长得一模一样。
/// 不传 locale，用 `Locale.autoupdatingCurrent` 自适应系统语言
/// （实测 zh-Hans「2026年10月」/ en "October 2026"）。
private func monthGroupTitle(for month: Date) -> String {
    month.formatted(.dateTime.year().month(.wide))
}

extension Array where Element == TransactionDayGroup {
    /// 把「按日分组」的输出再按月归并：月间倒序，月内**保留输入的日间顺序**。
    ///
    /// 保序是硬要求：`dailyClosingBalances` 靠日组的全局倒序做逐日回推，
    /// 这里只做「按月份入桶 + 保序」，不打乱桶内顺序。
    func groupedByMonth() -> [TransactionMonthGroup] {
        let cal = Calendar.current
        var order: [Date] = []
        var buckets: [Date: [TransactionDayGroup]] = [:]
        for group in self {
            let comps = cal.dateComponents([.year, .month], from: group.day)
            guard let month = cal.date(from: comps) else { continue }
            if buckets[month] == nil { order.append(month) }
            buckets[month, default: []].append(group)
        }
        return order.sorted(by: >).compactMap { month in
            guard let days = buckets[month] else { return nil }
            return TransactionMonthGroup(month: month, title: monthGroupTitle(for: month), dayGroups: days)
        }
    }

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

/// 账户/账户明细页「按年月折叠」的展开状态。
///
/// 把状态和收敛规则从两个平台的 View 里抽出来，一是消除 iOS/Mac 的重复实现，
/// 二是让「最新月份被删空」「跨月后录的第一笔」这类转移能被单测覆盖 ——
/// 它们原先只存在于 `@State` 里，靠读代码推理，测不了。
///
/// **身份必须与月份列表同源**：这里的 `Date` 是月首（取自 `TransactionMonthGroup.month`，
/// 归零到月首 00:00）。`reconcile` 用的是精确相等比较，若某处传进来的键带了时分秒，
/// 集合交集会静默把键全删掉。与 `TransactionDayGroup` 同一个纪律：
/// 分组身份用 `Date`，不用显示字符串。
/// - Note: 故意**不**声明 `Equatable`。本文件同时编进 iOS 和 Mac 两个 target，而 Mac
///   target 开了 `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` —— 同一个源文件在 Mac 模块里
///   会变成 MainActor 隔离，合成的 `==` 也跟着带上隔离；一旦有非隔离上下文用到它
///   （例如将来把这组测试搬去 `QianeymacTests`），Swift 5 是警告、Swift 6 直接报
///   `#IsolatedConformances` 错误。这里没有任何地方比较两个 state，所以不要它。
struct MonthExpansionState {
    /// 当前展开的月份（月首 `Date`）。
    private(set) var expanded: Set<Date> = []
    /// 上次收敛时「最新月份」是谁，用来判断最新月份有没有变。
    private(set) var knownNewest: Date?

    func isExpanded(_ month: Date) -> Bool { expanded.contains(month) }

    /// 用户点月份头：展开 <-> 收起。
    mutating func toggle(_ month: Date) {
        if expanded.contains(month) {
            expanded.remove(month)
        } else {
            expanded.insert(month)
        }
    }

    /// 用当前月份列表收敛一次。**`load()` 每次重跑都要调用**（不是只在首次）。
    ///
    /// 规则：
    /// ① 已不存在的月份不再占位 —— 否则用户删空最新月份后，展开集合里只剩一个悬空的
    ///    月首键，整页一个展开的月份都不剩，只剩月份头、一行交易都看不到；
    /// ② 最新月份变了（新出现了更新的月份，或原最新月份被删空/改期到更早）就展开新的
    ///    最新月份，**保留其余手动展开**的结果 —— 跨月后录的第一笔因此自动可见；
    /// ③ 最新月份没变时完全不动 —— 每次刷新都重置的话，用户刚展开的月份会被刷回去。
    ///
    /// - Parameter months: 月首 `Date`，**最新在前**（即 `groupedByMonth().map(\.month)`）。
    mutating func reconcile(months: [Date]) {
        expanded.formIntersection(Set(months))
        guard let newest = months.first else {
            knownNewest = nil   // 数据为空：下次有数据时按「首次」处理
            return
        }
        if newest != knownNewest {
            expanded.insert(newest)
            knownNewest = newest
        }
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
