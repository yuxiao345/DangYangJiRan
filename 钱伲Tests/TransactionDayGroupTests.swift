import XCTest
@preconcurrency import CoreData
@testable import 钱伲

/// `groupedByDay` / `dailyClosingBalances` 的回归测试。
///
/// 重点保护「分组身份必须是 `Date`」这条不变式。旧实现用
/// `.dateTime.month(.abbreviated).day(.defaultDigits)` 生成的显示字符串（**无年份**）
/// 当分组 key，导致 2025-06-09 与 2026-06-09 并成一组；`AccountDetailView.dateBalances`
/// 又拿同一个字符串当余额字典的 key，撞车那一组之后的每日期末余额整体偏移。
///
/// 断言全部基于 `Date`（日界、金额），与 locale 无关。
@MainActor
final class TransactionDayGroupTests: CoreDataTestCase {

    /// 跨年同月同日必须分成两组，不能合并 —— 这是本次修的 bug 的核心断言。
    func test_groupedByDay_doesNotMergeSameMonthDayAcrossYears() {
        let ledger = context.makeLedger("L")
        let account = context.makeAccount("现金", ledger: ledger)
        let tx2026 = context.makeTransaction(amount: -100, date: TestDates.date(2026, 6, 9), account: account, ledger: ledger)
        let tx2025 = context.makeTransaction(amount: -30, date: TestDates.date(2025, 6, 9), account: account, ledger: ledger)

        let groups = [tx2026, tx2025].groupedByDay()

        XCTAssertEqual(groups.count, 2, "2025-06-09 与 2026-06-09 是两个不同的自然日，旧实现会把它们并成一组")
        XCTAssertEqual(groups.map(\.day), [Calendar.current.startOfDay(for: tx2026.date),
                                           Calendar.current.startOfDay(for: tx2025.date)],
                       "组间按真实日期倒序")
        XCTAssertEqual(groups[0].transactions.map(\.objectID), [tx2026.objectID])
        XCTAssertEqual(groups[1].transactions.map(\.objectID), [tx2025.objectID])
    }

    /// 组间按真实日期倒序，组内按真实时间倒序，且不依赖输入顺序。
    func test_groupedByDay_ordersByRealDateAndIgnoresInputOrder() {
        let ledger = context.makeLedger("L")
        let account = context.makeAccount("现金", ledger: ledger)
        // 故意乱序传入，且同一天里早的在前
        let a = context.makeTransaction(amount: -1, date: TestDates.date(2026, 6, 30, hr: 9), account: account, ledger: ledger)
        let b = context.makeTransaction(amount: -2, date: TestDates.date(2026, 6, 9, hr: 20), account: account, ledger: ledger)
        let c = context.makeTransaction(amount: -3, date: TestDates.date(2026, 6, 9, hr: 8), account: account, ledger: ledger)
        let d = context.makeTransaction(amount: -4, date: TestDates.date(2026, 6, 10), account: account, ledger: ledger)

        let groups = [b, d, a, c].groupedByDay()

        let dayNumbers = groups.map { Calendar.current.component(.day, from: $0.day) }
        XCTAssertEqual(dayNumbers, [30, 10, 9], "组间必须按真实日期倒序")

        let lastDayHours = groups[2].transactions.map { Calendar.current.component(.hour, from: $0.date) }
        XCTAssertEqual(lastDayHours, [20, 8], "组内必须按真实时间倒序")
        XCTAssertEqual(groups[2].transactions.map(\.objectID), [b.objectID, c.objectID])
    }

    /// 今天 / 昨天仍然排在最前（按 `day` 倒序天然如此），且标题走本地化键。
    func test_groupedByDay_todayAndYesterdayComeFirst() {
        let ledger = context.makeLedger("L")
        let account = context.makeAccount("现金", ledger: ledger)
        let today = Date.now
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today)!
        let older = Calendar.current.date(byAdding: .day, value: -3, to: today)!

        let tToday = context.makeTransaction(amount: -1, date: today, account: account, ledger: ledger)
        let tYesterday = context.makeTransaction(amount: -2, date: yesterday, account: account, ledger: ledger)
        let tOlder = context.makeTransaction(amount: -3, date: older, account: account, ledger: ledger)

        let groups = [tOlder, tYesterday, tToday].groupedByDay()

        XCTAssertEqual(groups.count, 3)
        XCTAssertEqual(groups[0].transactions.map(\.objectID), [tToday.objectID])
        XCTAssertEqual(groups[1].transactions.map(\.objectID), [tYesterday.objectID])
        XCTAssertEqual(groups[2].transactions.map(\.objectID), [tOlder.objectID])
        XCTAssertEqual(groups[0].title, String(localized: "今天"))
        XCTAssertEqual(groups[1].title, String(localized: "昨天"))
    }

    /// `.relative` 标题在往年补年份：账户明细是全量历史，跨年同月同日不能撞出两个
    /// 一模一样的「6月9日」标题（分组身份和余额都按 `Date` 分开了，但标题还要能区分年份）。
    func test_groupedByDay_relativeStyleAppendsYearOnlyForPastYears() throws {
        let ledger = context.makeLedger("L")
        let account = context.makeAccount("现金", ledger: ledger)
        let cal = Calendar.current
        let now = Date.now
        let lastYearDate = cal.date(byAdding: .year, value: -1, to: now)!
        let thisYearDate = cal.date(byAdding: .day, value: -3, to: now)!

        let txThis = context.makeTransaction(amount: -1, date: thisYearDate, account: account, ledger: ledger)
        let txLast = context.makeTransaction(amount: -2, date: lastYearDate, account: account, ledger: ledger)

        let groups = [txThis, txLast].groupedByDay()  // 默认 .relative

        func group(containing tx: Transaction) -> TransactionDayGroup? {
            groups.first { $0.transactions.contains { $0.objectID == tx.objectID } }
        }

        let lastYearNum = String(cal.component(.year, from: lastYearDate))
        let lastYearGroup = try XCTUnwrap(group(containing: txLast))
        XCTAssertTrue(lastYearGroup.title.contains(lastYearNum),
                      "往年的标题必须带年份（\(lastYearNum)），否则跨年同月同日会撞标题：\(lastYearGroup.title)")

        // 今年内的日期不补年份（仅在确实与 now 同年时断言，避免年初 -3 天跨年的边缘）
        if cal.isDate(thisYearDate, equalTo: now, toGranularity: .year) {
            let thisYearNum = String(cal.component(.year, from: thisYearDate))
            let thisYearGroup = try XCTUnwrap(group(containing: txThis))
            XCTAssertFalse(thisYearGroup.title.contains(thisYearNum),
                           "今年内的标题不应带年份，保持「6月9日」的简洁：\(thisYearGroup.title)")
        }
    }

    /// `.fullDate` 标题带年份 —— 搜索结果跨年时不能只显示月日。
    func test_groupedByDay_fullDateStyleIncludesYear() {
        let ledger = context.makeLedger("L")
        let account = context.makeAccount("现金", ledger: ledger)
        let t2026 = context.makeTransaction(amount: -1, date: TestDates.date(2026, 6, 9), account: account, ledger: ledger)
        let t2025 = context.makeTransaction(amount: -2, date: TestDates.date(2025, 6, 9), account: account, ledger: ledger)

        let titles = [t2026, t2025].groupedByDay(titleStyle: .fullDate).map(\.title)

        XCTAssertEqual(titles.count, 2)
        XCTAssertNotEqual(titles[0], titles[1], "跨年同月同日的标题必须能区分，否则用户分不清是哪一年")
        let cal = Calendar.current
        let year2026 = String(cal.component(.year, from: t2026.date))
        let year2025 = String(cal.component(.year, from: t2025.date))
        XCTAssertTrue(titles[0].contains(year2026), "完整日期标题应含年份：\(titles[0])")
        XCTAssertTrue(titles[1].contains(year2025), "完整日期标题应含年份：\(titles[1])")
    }

    /// 每日期末余额：从当前余额按组由新到旧回推，跨年不再被带偏。
    ///
    /// 旧实现下 2025-06-09 与 2026-06-09 并成一组，`running` 一次性多减了 2025 那天的
    /// 净额，于是 2026-06-08 那组显示的余额差了 30（实测过：显示 -70，正确 -100）。
    func test_dailyClosingBalances_walksBackPerCalendarDay() {
        let ledger = context.makeLedger("L")
        let account = context.makeAccount("现金", ledger: ledger)
        // 与 /tmp 复现脚本同一组数据
        let t1 = context.makeTransaction(amount: -100, date: TestDates.date(2026, 6, 9), account: account, ledger: ledger)
        let t2 = context.makeTransaction(amount: -50, date: TestDates.date(2026, 6, 8), account: account, ledger: ledger)
        let t3 = context.makeTransaction(amount: -30, date: TestDates.date(2025, 6, 9), account: account, ledger: ledger)
        let t4 = context.makeTransaction(amount: -20, date: TestDates.date(2025, 6, 8), account: account, ledger: ledger)

        let groups = [t1, t2, t3, t4].groupedByDay()
        let balances = groups.dailyClosingBalances(startingFrom: -200)

        let cal = Calendar.current
        func closingBalance(_ y: Int, _ m: Int, _ d: Int) -> Decimal? {
            balances[cal.startOfDay(for: TestDates.date(y, m, d))]
        }

        XCTAssertEqual(groups.count, 4, "四个自然日必须分成四组（旧实现只有两组）")
        XCTAssertEqual(closingBalance(2026, 6, 9), -200)
        XCTAssertEqual(closingBalance(2026, 6, 8), -100)
        XCTAssertEqual(closingBalance(2025, 6, 9), -50)
        XCTAssertEqual(closingBalance(2025, 6, 8), -20)
    }

    /// 余额口径取 `amount`（账户自身币种），与 `calculateBalance` 的回推起点一致。
    /// 外币交易带 convertedAmount 时，`ledgerAmount` 是折算后的基准币种金额，
    /// 混进账户币种的余额里就会与该行标的币种不符。
    func test_dailyClosingBalances_usesAccountCurrencyAmountNotConvertedAmount() {
        let ledger = context.makeLedger("L", defaultCurrencyCode: "CNY")
        let account = context.makeAccount("美元卡", ledger: ledger, currencyCode: "USD")
        // 关键：放两笔交易。单笔时最新一天的期末余额恒等于起始余额，减 amount 还是
        // convertedAmount 结果都一样，测不出差异；差异只出现在「更早一天」的余额上。
        let newer = context.makeTransaction(amount: -100, date: TestDates.date(2026, 6, 9), account: account, ledger: ledger)
        let older = context.makeTransaction(amount: -20, date: TestDates.date(2026, 6, 8), account: account, ledger: ledger)
        // 100 USD 按 7.2 折算为基准币种
        newer.convertedAmount = -720
        try! context.save()

        let balances = [newer, older].groupedByDay().dailyClosingBalances(startingFrom: -100)

        let cal = Calendar.current
        // 最新一天 = 起始余额（还没减当天）
        XCTAssertEqual(balances[cal.startOfDay(for: newer.date)], -100)
        // 更早一天 = -100 - (-100) = 0；若误用 convertedAmount 会得到 -100 - (-720) = 620
        XCTAssertEqual(balances[cal.startOfDay(for: older.date)], 0,
                       "期末余额必须用账户币种（USD）口径的 amount，不能用折算后的 convertedAmount/ledgerAmount")
    }
}
