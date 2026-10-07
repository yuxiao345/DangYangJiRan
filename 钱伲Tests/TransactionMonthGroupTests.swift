import XCTest
@preconcurrency import CoreData
@testable import 钱伲

/// `groupedByMonth` / `TransactionMonthGroup` 的回归测试。
///
/// 保护两条不变式：
/// ① 分组身份是**月首 `Date`**，不是显示字符串 —— 同月跨年必须分成两组
///   （`TransactionDayGroup` 当年就是因为拿没有年份的显示字符串当 key，
///   把 2025-06-09 和 2026-06-09 并成了一组）；
/// ② 按月分桶**不得重排**月内的日组 —— `dailyClosingBalances` 靠日组全局倒序做逐日
///   回推，顺序一乱，被收起月份之后所有天的余额都会错。
@MainActor
final class TransactionMonthGroupTests: CoreDataTestCase {

    private func monthComponents(_ date: Date) -> (year: Int, month: Int, day: Int) {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return (c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// 跨年同月必须分成两个月组。
    func test_groupedByMonth_doesNotMergeSameMonthAcrossYears() {
        let ledger = context.makeLedger("L")
        let account = context.makeAccount("现金", ledger: ledger)
        let t2026 = context.makeTransaction(amount: -100, date: TestDates.date(2026, 6, 9), account: account, ledger: ledger)
        let t2025 = context.makeTransaction(amount: -30, date: TestDates.date(2025, 6, 9), account: account, ledger: ledger)

        let months = [t2026, t2025].groupedByDay().groupedByMonth()

        XCTAssertEqual(months.count, 2, "2025-06 与 2026-06 是两个不同的月份")
        let newest = monthComponents(months[0].month)
        XCTAssertEqual(newest.year, 2026, "月间倒序：较新的月份在前")
        XCTAssertEqual(newest.month, 6)
        XCTAssertEqual(newest.day, 1, "分组身份必须归零到月首")
        XCTAssertEqual(monthComponents(months[1].month).year, 2025)
    }

    /// 月间倒序；月内保留 `groupedByDay` 给出的日间倒序。
    func test_groupedByMonth_ordersMonthsDescendingAndKeepsDayOrderWithinMonth() {
        let ledger = context.makeLedger("L")
        let account = context.makeAccount("现金", ledger: ledger)
        let june9 = context.makeTransaction(amount: -10, date: TestDates.date(2026, 6, 9), account: account, ledger: ledger)
        let june8 = context.makeTransaction(amount: -20, date: TestDates.date(2026, 6, 8), account: account, ledger: ledger)
        let june1 = context.makeTransaction(amount: -30, date: TestDates.date(2026, 6, 1), account: account, ledger: ledger)
        let may31 = context.makeTransaction(amount: -40, date: TestDates.date(2026, 5, 31), account: account, ledger: ledger)

        // 故意乱序传入：排序由 groupedByDay 负责，groupedByMonth 只做按月份入桶
        let dayGroups = [june9, june1, may31, june8].groupedByDay()
        let months = dayGroups.groupedByMonth()

        let cal = Calendar.current
        XCTAssertEqual(months.count, 2)
        XCTAssertEqual(monthComponents(months[0].month).month, 6, "6 月必须排在 5 月前面")
        XCTAssertEqual(monthComponents(months[1].month).month, 5)
        XCTAssertEqual(months[0].dayGroups.map(\.day),
                       [cal.startOfDay(for: june9.date),
                        cal.startOfDay(for: june8.date),
                        cal.startOfDay(for: june1.date)],
                       "月内必须保持日间倒序，不能因为按月分桶而重排")
        XCTAssertEqual(months[1].dayGroups.map(\.day), [cal.startOfDay(for: may31.date)])
    }

    /// 月组展平后必须与 `groupedByDay` 的输出**逐项相同**（顺序 + 内容）。
    ///
    /// 这是 `dailyClosingBalances` 正确性的前提：该函数只接受日组全局倒序，
    /// 而账户详情页喂给它的仍是全量日组，与展开了哪些月份无关。
    func test_groupedByMonth_flattenedDaysEqualDayGroupingOutput() {
        let ledger = context.makeLedger("L")
        let account = context.makeAccount("现金", ledger: ledger)
        let dates = [(2026, 6, 9), (2026, 6, 8), (2026, 6, 1), (2026, 5, 31), (2026, 5, 30), (2025, 12, 31)]
        let transactions = dates.map {
            context.makeTransaction(amount: -10, date: TestDates.date($0.0, $0.1, $0.2), account: account, ledger: ledger)
        }

        let dayGroups = transactions.groupedByDay()
        let flat = dayGroups.groupedByMonth().flatMap(\.dayGroups)

        XCTAssertEqual(flat.map(\.day), dayGroups.map(\.day), "展平后日组顺序必须与 groupedByDay 完全一致")
        XCTAssertEqual(flat.flatMap { $0.transactions }.map(\.objectID),
                       dayGroups.flatMap { $0.transactions }.map(\.objectID),
                       "不得丢交易、不得改行顺序")
    }

    /// 收支合计取**原始 `amount` 正负号**，不是 `signedAmount`。
    ///
    /// 反例就在转账上：`signedAmount` 把 transfer 一律记成 −abs（流出），
    /// 而本页交易行与逐日余额都用 `amount` 原值。月份头若改用 `signedAmount`，
    /// 同一个月的头与它下面的行/余额会互相矛盾。
    func test_monthTotals_useRawAmountSignNotSignedAmount() throws {
        let ledger = context.makeLedger("L")
        let account = context.makeAccount("现金", ledger: ledger)
        let salary = context.makeTransaction(amount: 3200, date: TestDates.date(2026, 6, 5),
                                            account: account, ledger: ledger, type: .income)
        let lunch = context.makeTransaction(amount: -50, date: TestDates.date(2026, 6, 5),
                                           account: account, ledger: ledger, type: .expense)
        // 转入本账户的转账：amount 为正，但 signedAmount 会把它算成流出
        let transferIn = context.makeTransaction(amount: 500, date: TestDates.date(2026, 6, 6),
                                                account: account, ledger: ledger, type: .transfer)

        let month = try XCTUnwrap([salary, lunch, transferIn].groupedByDay().groupedByMonth().first)

        XCTAssertEqual(month.inflow, 3700, "流入 = 3200 工资 + 500 转入，转账按 amount 原值算流入")
        XCTAssertEqual(month.outflow, -50)
        // 关键交叉验证：两个合计之和 = Σ amount，正是 dailyClosingBalances 逐日回推所用的量
        XCTAssertEqual(month.inflow + month.outflow, 3650,
                       "合计之和必须等于 Σ amount（余额回推同一口径），否则月份头与日余额互相矛盾")
    }

    /// 月份标题**始终**带年份：只显示「10月」的话，2026 年 10 月和 2025 年 10 月两个分组头
    /// 长得一模一样（账户明细拉的是全量历史，必然跨年）。
    func test_monthTitle_alwaysIncludesYear() {
        let ledger = context.makeLedger("L")
        let account = context.makeAccount("现金", ledger: ledger)
        let thisYear = context.makeTransaction(amount: -1, date: Date(), account: account, ledger: ledger)
        let lastYearDate = Calendar.current.date(byAdding: .year, value: -1, to: Date())!
        let lastYear = context.makeTransaction(amount: -2, date: lastYearDate, account: account, ledger: ledger)

        let months = [thisYear, lastYear].groupedByDay().groupedByMonth()

        XCTAssertEqual(months.count, 2)
        for month in months {
            // 年份文本必须用**同一个 formatter + 同一个 locale** 生成再比：
            // `String(cal.component(.year, from:))` 出的是拉丁数字「2026」，
            // 而标题走 `Locale.autoupdatingCurrent`，在波斯/阿拉伯数字的 locale 下是
            // 「۲۰۲۶」，contains 会假失败（实现是对的、测试红）。
            let yearText = month.month.formatted(.dateTime.year())
            XCTAssertTrue(month.title.contains(yearText),
                          "标题必须含年份 \(yearText)，否则跨年同月撞标题：\(month.title)")
        }
        XCTAssertNotEqual(months[0].title, months[1].title, "相隔一年的两个月份标题必须可区分")
    }
}

/// `MonthExpansionState` 的回归测试 —— 账户明细页「按年月折叠」的展开状态机。
///
/// 这一组**不需要 CoreData**（纯状态转移，输入只是月首 `Date` 数组），所以不继承
/// `CoreDataTestCase`：状态机原先只活在两个 View 的 `@State` 里，靠读代码推理；
/// 抽成共享类型就是为了让它能这样被测。
final class MonthExpansionStateTests: XCTestCase {

    /// 身份是月首 `Date`。测试里自己造，不经过 `groupedByMonth()`，
    /// 免得「测状态机」被 CoreData fixture 带偏。
    private func monthStart(_ year: Int, _ month: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: 1))!
    }

    /// 首次收敛：最新月份展开，其余收起。
    func test_reconcile_firstTimeExpandsNewestMonthOnly() {
        let july = monthStart(2026, 7), june = monthStart(2026, 6)
        var state = MonthExpansionState()

        state.reconcile(months: [july, june])

        XCTAssertEqual(state.expanded, [july], "首屏只展开最新一个月")
        XCTAssertEqual(state.knownNewest, july)
    }

    /// 规则①：最新月份被删空（或改期到更早月份）后，展开位置退回新的最新月份 ——
    /// 否则展开集合里只剩一个悬空的月首键，整页一个展开的月份都没有。
    func test_reconcile_whenNewestDisappears_movesExpansionToNewNewest() {
        let july = monthStart(2026, 7), june = monthStart(2026, 6)
        var state = MonthExpansionState()
        state.reconcile(months: [july, june])

        state.reconcile(months: [june])   // 7 月那几笔被删空

        XCTAssertEqual(state.expanded, [june], "必须退回新的最新月份，不能留悬空键、也不能一个都不展开")
        XCTAssertFalse(state.isExpanded(july), "已不存在的月份不得继续占位")
        XCTAssertEqual(state.knownNewest, june)
    }

    /// 规则②：跨月后录的第一笔（新出现了更新的月份）自动展开，且**保留**其余手动展开。
    func test_reconcile_whenNewerMonthAppears_addsItAndKeepsManualExpansions() {
        let august = monthStart(2026, 8), july = monthStart(2026, 7), june = monthStart(2026, 6)
        var state = MonthExpansionState()
        state.reconcile(months: [july, june])
        state.toggle(june)                // 用户手动展开了 6 月

        state.reconcile(months: [august, july, june])

        XCTAssertEqual(state.expanded, [august, july, june],
                       "新的最新月份自动展开，用户手动展开的不能被清掉")
        XCTAssertEqual(state.knownNewest, august)
    }

    /// 规则③：最新月份没变时完全不动 —— 用户手动收起的月份不能被刷新重新撑开。
    func test_reconcile_whenNewestUnchanged_leavesUserStateAlone() {
        let july = monthStart(2026, 7), june = monthStart(2026, 6)
        var state = MonthExpansionState()
        state.reconcile(months: [july, june])
        state.toggle(july)                // 用户把唯一展开的月份收起了

        state.reconcile(months: [july, june])   // 期间发生交易增删改 → load() 重跑

        XCTAssertTrue(state.expanded.isEmpty, "最新月份没变时不得回弹展开")
        XCTAssertEqual(state.knownNewest, july)
    }

    /// 数据清空：`knownNewest` 归零，下次有数据时按「首次」重新展开 ——
    /// 否则「删光全部交易、再录第一笔」会出现整页收起的坏状态。
    func test_reconcile_whenAllDataGone_thenNewDataExpandsAgain() {
        let july = monthStart(2026, 7)
        var state = MonthExpansionState()
        state.reconcile(months: [july])

        state.reconcile(months: [])       // 交易被删光

        XCTAssertTrue(state.expanded.isEmpty)
        XCTAssertNil(state.knownNewest, "清空后要忘掉「上次最新月份」，否则下次不会再展开")

        state.reconcile(months: [july])   // 又在 7 月录了一笔

        XCTAssertEqual(state.expanded, [july])
    }
}
