import XCTest
@preconcurrency import CoreData
@testable import 钱伲

/// SearchViewModel 搜索结果排序 / 按天分组测试。
///
/// 背景：分组逻辑原先在 `SearchView` 和 `MacSearchView` 里各有一份逐字相同的实现，
/// 都用 `t.date.formatted(date: .complete, time: .omitted)` 当分组 key、再对 key 做
/// 字符串 `>` 比较。那是「给人看的字符串」的 Unicode 码位序，不是日期序 ——
/// zh-Hans 下「2026年6月9日」的码位序大于「2026年6月30日」（'9' > '3'），
/// 英语环境下模板是 `EEEE, MMMM d, y`，退化成按星期名的字母序。
///
/// 所以这里断言的全是 **`Date` 序列**（日号、小时），不涉及任何本地化字符串 ——
/// 无论测试跑在哪个 locale 下都成立，旧实现则必挂。
@MainActor
final class SearchViewModelTests: CoreDataTestCase {

    private func makeViewModel(_ ledger: Ledger) -> SearchViewModel {
        SearchViewModel(ledger: ledger, transactionService: TransactionServiceImpl())
    }

    /// 组间必须按真实日期倒序。
    /// 故意把 30 日放中间传入，证明排序发生在 ViewModel 而不是输入顺序。
    /// 旧实现（字符串 key 比较）给出的是 6/9 → 6/30 → 6/10。
    func test_dayGroups_ordersDaysByRealDateDescending() {
        let ledger = context.makeLedger("L")
        let account = context.makeAccount("现金", ledger: ledger)

        let t9 = context.makeTransaction(amount: -100, date: TestDates.date(2026, 6, 9), account: account, ledger: ledger)
        let t10 = context.makeTransaction(amount: -200, date: TestDates.date(2026, 6, 10), account: account, ledger: ledger)
        let t30 = context.makeTransaction(amount: -300, date: TestDates.date(2026, 6, 30), account: account, ledger: ledger)

        let vm = makeViewModel(ledger)
        vm.searchResults = [t9, t30, t10]

        XCTAssertEqual(vm.dayGroups.count, 3, "三个不同的自然日应分成三组，不能因字符串 key 相同而合并")
        let dayNumbers = vm.dayGroups.map { Calendar.current.component(.day, from: $0.day) }
        XCTAssertEqual(dayNumbers, [30, 10, 9], "组间必须按真实日期倒序，而不是本地化日期字符串的码位序")
    }

    /// 同一天的早/晚两笔（8:00 与 20:00），用于「组身份」和「组内顺序」两个断言方向。
    /// 两个测试各自调用、各自保留失败信号 —— 合并会让两个失败点变成同一条。
    private func makeSameDayFixture() -> (vm: SearchViewModel, morning: Transaction, evening: Transaction) {
        let ledger = context.makeLedger("L")
        let account = context.makeAccount("现金", ledger: ledger)
        let morning = context.makeTransaction(amount: -100, date: TestDates.date(2026, 6, 9, hr: 8), account: account, ledger: ledger)
        let evening = context.makeTransaction(amount: -200, date: TestDates.date(2026, 6, 9, hr: 20), account: account, ledger: ledger)
        let vm = makeViewModel(ledger)
        vm.searchResults = [morning, evening]
        return (vm, morning, evening)
    }

    /// 每个组的 `day` 必须是该组的身份：归零到日界，且组内交易确实落在这一天。
    func test_dayGroups_dayIdentityIsStartOfDay() throws {
        let (vm, morning, evening) = makeSameDayFixture()

        XCTAssertEqual(vm.dayGroups.count, 1, "同一天的交易必须在同一组")
        let group = try XCTUnwrap(vm.dayGroups.first)
        XCTAssertEqual(group.day, Calendar.current.startOfDay(for: morning.date))
        XCTAssertEqual(Set(group.transactions.map(\.objectID)), Set([morning.objectID, evening.objectID]))
    }

    /// 同一天内按真实时间倒序。
    func test_dayGroups_ordersTransactionsWithinDayByTimeDescending() {
        let (vm, _, _) = makeSameDayFixture()

        let hours = vm.dayGroups.first?.transactions.map { Calendar.current.component(.hour, from: $0.date) }
        XCTAssertEqual(hours, [20, 8], "组内必须按真实时间倒序")
    }

    /// 只有按日期排序才分天；按金额排序时日期标题没有意义，视图靠 `groupsByDay` 铺平渲染。
    func test_groupsByDay_onlyForDateSort() {
        let ledger = context.makeLedger("L")
        let vm = makeViewModel(ledger)

        vm.sortOrder = .dateDesc
        XCTAssertTrue(vm.groupsByDay)

        vm.sortOrder = .amountDesc
        XCTAssertFalse(vm.groupsByDay, "按金额降序不应出日期分组标题")

        vm.sortOrder = .amountAsc
        XCTAssertFalse(vm.groupsByDay, "按金额升序不应出日期分组标题")
    }

    /// 金额排序用绝对值：收入与支出混排，不因符号被推到两端。
    func test_sortedResults_amountOrderUsesAbsoluteValue() {
        let ledger = context.makeLedger("L")
        let account = context.makeAccount("现金", ledger: ledger)
        let smallIncome = context.makeTransaction(amount: 100, date: TestDates.date(2026, 6, 9), account: account, ledger: ledger, type: .income)
        let bigExpense = context.makeTransaction(amount: -500, date: TestDates.date(2026, 6, 10), account: account, ledger: ledger)
        let midExpense = context.makeTransaction(amount: -250, date: TestDates.date(2026, 6, 11), account: account, ledger: ledger)

        let vm = makeViewModel(ledger)
        vm.searchResults = [smallIncome, bigExpense, midExpense]

        vm.sortOrder = .amountDesc
        XCTAssertEqual(vm.sortedResults.map { abs($0.amount) }, [500, 250, 100])
        vm.sortOrder = .amountAsc
        XCTAssertEqual(vm.sortedResults.map { abs($0.amount) }, [100, 250, 500])
    }

    /// 按日期排序时，日期是唯一排序依据（组间与组内同向倒序，合成后整体就是日期倒序）。
    func test_sortedResults_dateDescIsGlobalDescending() {
        let ledger = context.makeLedger("L")
        let account = context.makeAccount("现金", ledger: ledger)
        let a = context.makeTransaction(amount: -100, date: TestDates.date(2026, 6, 9), account: account, ledger: ledger)
        let b = context.makeTransaction(amount: -200, date: TestDates.date(2026, 6, 30), account: account, ledger: ledger)
        let c = context.makeTransaction(amount: -300, date: TestDates.date(2026, 6, 10), account: account, ledger: ledger)

        let vm = makeViewModel(ledger)
        vm.searchResults = [a, b, c]

        XCTAssertEqual(vm.sortedResults.map(\.objectID), [b.objectID, c.objectID, a.objectID])
        XCTAssertEqual(vm.dayGroups.flatMap { $0.transactions.map(\.objectID) }, [b.objectID, c.objectID, a.objectID],
                       "分组后的扁平序列必须与 sortedResults 一致")
    }
}
