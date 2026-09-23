import XCTest
@preconcurrency import CoreData
@testable import 钱伲

/// SplitService 单元测试
/// 覆盖拆分创建（equal/percentage/fixed）、markEntryPaid、settleSplit、fetchSplits
final class SplitServiceTests: CoreDataTestCase {

    var service: SplitServiceImpl!

    override func setUp() {
        super.setUp()
        service = SplitServiceImpl()
    }

    override func tearDown() {
        service = nil
        super.tearDown()
    }

    // MARK: - createSplit (equal)

    /// equal 模式：每个 member 平分 totalAmount
    func test_createSplit_equal_dividesEvenly() throws {
        let ledger = context.makeLedger()
        let account = context.makeAccount("现金", ledger: ledger)
        let m1 = context.makeMember("张三", ledger: ledger)
        let m2 = context.makeMember("李四", ledger: ledger)
        let m3 = context.makeMember("王五", ledger: ledger)
        let tx = context.makeTransaction(amount: -300, account: account, ledger: ledger)

        let group = try service.createSplit(
            totalAmount: 300,
            currencyCode: "CNY",
            splitType: .equal,
            members: [m1, m2, m3],
            amounts: nil,
            note: "聚餐",
            date: Date(),
            transaction: tx,
            ledger: ledger,
            context: context
        )

        XCTAssertEqual(group.entries?.count, 3)
        XCTAssertEqual(group.totalAmount, 300)
        XCTAssertEqual(group.splitType, .equal)
        let entries = (group.entries ?? [])
        let amounts = entries.map { $0.amount }.sorted()
        XCTAssertEqual(amounts, [100, 100, 100], "equal 应每人 100")
        // transaction 设置 isSplitParent
        XCTAssertTrue(tx.isSplitParent)
        XCTAssertEqual(tx.splitGroup, group)
    }

    /// equal 模式：金额不能整除时按分均分，余数补给**最后一名**成员
    ///
    /// ¥100 分 3 人 → 3333 / 3333 / 3334（合计正好 10000）。
    ///
    /// 曾经的期望是「每人都是 3333」——那是 `Int64(truncating:)` 修好之后、
    /// 余数分配修好之前的中间状态：每人 3333 合计只有 9999，永远补不齐总额，
    /// 于是 `settlementStatus` 到不了 `.settled`（症状见下一条 `test_settleSplit_...`）。
    func test_createSplit_equal_unevenDivision_remainderGoesToLastMember() throws {
        let ledger = context.makeLedger()
        let account = context.makeAccount("现金", ledger: ledger)
        let members = (1...3).map { context.makeMember("成员\($0)", ledger: ledger) }
        let tx = context.makeTransaction(amount: -100, account: account, ledger: ledger)

        let group = try service.createSplit(
            totalAmount: 100,
            currencyCode: "CNY",
            splitType: .equal,
            members: members,
            amounts: nil,
            note: nil,
            date: Date(),
            transaction: tx,
            ledger: ledger,
            context: context
        )

        let entries = (group.entries ?? [])
        XCTAssertEqual(entries.count, 3)
        XCTAssertEqual(entries.map(\.amountInFen).sorted(), [3333, 3333, 3334])

        // 余数落在最后一名成员身上（entries 是 Set，顺序不定，只能按成员反查）
        let fenByMember = Dictionary(
            uniqueKeysWithValues: entries.compactMap { e in e.member.map { ($0.id, e.amountInFen) } }
        )
        XCTAssertEqual(fenByMember[members[0].id], 3333)
        XCTAssertEqual(fenByMember[members[1].id], 3333)
        XCTAssertEqual(fenByMember[members[2].id], 3334, "多出的 1 分应补给最后一名成员")

        // 核心不变量：分账各份之和必须等于分账总额
        XCTAssertEqual(
            entries.reduce(Int64(0)) { $0 + $1.amountInFen },
            group.totalAmountInFen,
            "sum(entries) 必须等于 totalAmountInFen，否则 settlementStatus 永远到不了 .settled"
        )
        XCTAssertEqual(group.totalPaid, 0, "刚创建时无人已付")
        XCTAssertEqual(group.remainingAmount, group.totalAmount, "刚创建时剩余应等于总额")
    }

    /// `SplitServiceImpl.equalShares` 的性质测试：任意总额 × 任意人数，都凑得齐
    ///
    /// 三个不变量：① `sum(shares) == 总额`（分账能结清的前提，就是这个 bug 的核心）；
    /// ② 除最后一份外完全相等；③ 余数（全落在最后一份上）不超过 人数−1 分。
    /// 顺带覆盖 0 人（不能触发 Int64 除以 0 的 trap）、0 元、负数总额。
    func test_equalShares_invariants_hold() {
        let counts = [1, 2, 3, 4, 7, 100]
        let totalFens: [Int64] = [0, 1, 2, 99, 100, 3333, 10000, 99999, -1, -100, -10000, -99999]

        for count in counts {
            for totalFen in totalFens {
                let shares = SplitServiceImpl.equalShares(totalAmount: Decimal(totalFen) / 100, count: count)
                let fen = shares.map(\.fenValue)
                let label = "count=\(count) totalFen=\(totalFen)"

                XCTAssertEqual(fen.count, count, label)
                XCTAssertEqual(fen.reduce(Int64(0), +), totalFen, "合计必须等于总额 | \(label)")
                guard count > 1 else { continue }

                let others = fen.dropLast()
                XCTAssertEqual(Set(others).count, 1, "除最后一份外应完全相等 | \(label)")
                let base = others.first ?? 0
                XCTAssertLessThan(
                    abs(totalFen - base * Int64(count)), Int64(count),
                    "余数应小于 人数 分（全补给最后一份）| \(label)"
                )
            }
        }

        XCTAssertTrue(SplitServiceImpl.equalShares(totalAmount: 100, count: 0).isEmpty, "0 人应返回空数组")
    }

    // MARK: - createSplit (percentage/fixed)

    /// percentage 模式：按 amounts 数组分摊
    func test_createSplit_percentage_usesProvidedAmounts() throws {
        let ledger = context.makeLedger()
        let account = context.makeAccount("现金", ledger: ledger)
        let m1 = context.makeMember("A", ledger: ledger)
        let m2 = context.makeMember("B", ledger: ledger)
        let tx = context.makeTransaction(amount: -200, account: account, ledger: ledger)

        let group = try service.createSplit(
            totalAmount: 200,
            currencyCode: "CNY",
            splitType: .percentage,
            members: [m1, m2],
            amounts: [120, 80],
            note: nil,
            date: Date(),
            transaction: tx,
            ledger: ledger,
            context: context
        )

        let entries = (group.entries ?? [])
        let amounts = entries.map { $0.amount }.sorted()
        XCTAssertEqual(amounts, [80, 120])
    }

    /// fixed 模式：按 amounts 数组分摊（不等额）
    func test_createSplit_fixed_usesProvidedAmounts() throws {
        let ledger = context.makeLedger()
        let account = context.makeAccount("现金", ledger: ledger)
        let m1 = context.makeMember("A", ledger: ledger)
        let m2 = context.makeMember("B", ledger: ledger)
        let tx = context.makeTransaction(amount: -150, account: account, ledger: ledger)

        let group = try service.createSplit(
            totalAmount: 150,
            currencyCode: "CNY",
            splitType: .fixed,
            members: [m1, m2],
            amounts: [100, 50],
            note: "A付100 B付50",
            date: Date(),
            transaction: tx,
            ledger: ledger,
            context: context
        )

        XCTAssertEqual(group.splitType, .fixed)
        let entries = (group.entries ?? [])
        let amounts = entries.map { $0.amount }.sorted()
        XCTAssertEqual(amounts, [50, 100])
    }

    /// percentage 模式缺 amounts：应抛 invalidAmounts
    func test_createSplit_percentage_missingAmounts_throws() {
        let ledger = context.makeLedger()
        let account = context.makeAccount("现金", ledger: ledger)
        let m1 = context.makeMember("A", ledger: ledger)
        let tx = context.makeTransaction(amount: -100, account: account, ledger: ledger)

        XCTAssertThrowsError(try service.createSplit(
            totalAmount: 100,
            currencyCode: "CNY",
            splitType: .percentage,
            members: [m1],
            amounts: nil,
            note: nil,
            date: Date(),
            transaction: tx,
            ledger: ledger,
            context: context
        )) { error in
            guard case SplitError.invalidAmounts = error else {
                XCTFail("期望 SplitError.invalidAmounts，得到 \(error)")
                return
            }
        }
    }

    /// fixed 模式缺 amounts：应抛 invalidAmounts
    func test_createSplit_fixed_missingAmounts_throws() {
        let ledger = context.makeLedger()
        let account = context.makeAccount("现金", ledger: ledger)
        let m1 = context.makeMember("A", ledger: ledger)
        let tx = context.makeTransaction(amount: -100, account: account, ledger: ledger)

        XCTAssertThrowsError(try service.createSplit(
            totalAmount: 100,
            currencyCode: "CNY",
            splitType: .fixed,
            members: [m1],
            amounts: nil,
            note: nil,
            date: Date(),
            transaction: tx,
            ledger: ledger,
            context: context
        )) { error in
            guard case SplitError.invalidAmounts = error else {
                XCTFail("期望 SplitError.invalidAmounts，得到 \(error)")
                return
            }
        }
    }

    // MARK: - markEntryPaid

    /// 标记单个 entry 已支付
    func test_markEntryPaid_setsIsPaidAndPaidDate() throws {
        let ledger = context.makeLedger()
        let account = context.makeAccount("现金", ledger: ledger)
        let m1 = context.makeMember("A", ledger: ledger)
        let tx = context.makeTransaction(amount: -100, account: account, ledger: ledger)
        let group = try service.createSplit(
            totalAmount: 100, currencyCode: "CNY", splitType: .equal,
            members: [m1], amounts: nil, note: nil, date: Date(),
            transaction: tx, ledger: ledger, context: context
        )

        let entry = group.entries!.first!
        XCTAssertFalse(entry.isPaid)
        XCTAssertNil(entry.paidDate)

        let before = Date()
        try service.markEntryPaid(entry, context: context)
        let after = Date()

        XCTAssertTrue(entry.isPaid)
        XCTAssertNotNil(entry.paidDate)
        XCTAssertGreaterThanOrEqual(entry.paidDate ?? .distantPast, before)
        XCTAssertLessThanOrEqual(entry.paidDate ?? .distantFuture, after)
    }

    // MARK: - settleSplit

    /// 一键结算：所有未付的 entry 都标记为已付
    func test_settleSplit_marksAllEntriesAsPaid() throws {
        let ledger = context.makeLedger()
        let account = context.makeAccount("现金", ledger: ledger)
        let members = (1...3).map { context.makeMember("成员\($0)", ledger: ledger) }
        let tx = context.makeTransaction(amount: -300, account: account, ledger: ledger)
        let group = try service.createSplit(
            totalAmount: 300, currencyCode: "CNY", splitType: .equal,
            members: members, amounts: nil, note: nil, date: Date(),
            transaction: tx, ledger: ledger, context: context
        )

        // 初始：所有未付
        for entry in group.entries ?? [] {
            XCTAssertFalse(entry.isPaid)
        }

        try service.settleSplit(group, context: context)

        for entry in group.entries ?? [] {
            XCTAssertTrue(entry.isPaid, "所有 entry 应在 settleSplit 后标记为已付")
            XCTAssertNotNil(entry.paidDate)
        }
    }

    /// 除不尽的 equal 分摊：付清后 `settlementStatus` 必须真的变成 `.settled`
    ///
    /// 这是「AA 分账余数不分配」那个 bug 的**症状回归锁**。旧算法每人截断成 3333，
    /// 合计 9999 < 总额 10000，`settlementStatus` 里 `totalPaid >= totalAmount` 永不成立
    /// —— 全部付清也停在 `.partial`。而 `SplitDetailView:63` 的「一键结算」按钮门控正是
    /// `settlementStatus != .settled`，于是按钮永不消失、还一直挂着「剩余 ¥0.01」。
    func test_settleSplit_unevenEqual_reachesSettled() throws {
        let ledger = context.makeLedger()
        let account = context.makeAccount("现金", ledger: ledger)
        let members = (1...3).map { context.makeMember("成员\($0)", ledger: ledger) }
        let tx = context.makeTransaction(amount: -100, account: account, ledger: ledger)
        let group = try service.createSplit(
            totalAmount: 100, currencyCode: "CNY", splitType: .equal,
            members: members, amounts: nil, note: nil, date: Date(),
            transaction: tx, ledger: ledger, context: context
        )

        XCTAssertEqual(group.settlementStatus, .unsettled)

        // 付掉 2 人 → 部分结清（任意 2 人：每人 3333 或 3334，都落在 (0, 10000) 内）
        for entry in (group.entries ?? []).prefix(2) {
            try service.markEntryPaid(entry, context: context)
        }
        XCTAssertEqual(group.settlementStatus, .partial)
        XCTAssertGreaterThan(group.remainingAmount, 0, "还有人没付，剩余应大于 0")

        try service.settleSplit(group, context: context)

        XCTAssertEqual(group.totalPaid, group.totalAmount, "付清后已付金额应等于总额")
        XCTAssertEqual(group.remainingAmount, 0)
        XCTAssertEqual(group.settlementStatus, .settled, "付清后必须能到 .settled，否则「一键结算」按钮永不消失")
    }

    /// ⚠️ **已知缺口（刻意没修）**：`.percentage` 模式合计仍可能少于总额，症状与 `equal` 同源
    ///
    /// `equalShares` 只让 `.equal` 满足 `sum(entries) == totalAmount`。百分比/定额模式仍直接
    /// 用调用方传来的金额、每份各按分截断，于是**同一个症状仍在**：合计补不齐
    /// → `settlementStatus` 永远到不了 `.settled` → `SplitDetailView` 的「一键结算」按钮永不消失。
    ///
    /// 这条**刻意断言当前的错误结果**（characterization test），作用有二：
    /// ① 让缺口可执行、不会被忘掉；② 将来谁修了百分比模式，这条会立刻变红，逼他更新清单。
    /// 待办与修法（约 3 行归一化）见 `.claude/plans/release-checklist.md` §六-8-2。
    ///
    /// 数字实测而来，**注意用 `Decimal(string:)` 而不是 `Decimal(7.77)`** ——
    /// 后者是 Double 字面量转换，实际是 `7.769999999999997952`，会让探针误报「合计正好相等」。
    func test_percentage_knownGap_sumCanBeLessThanTotal() throws {
        let ledger = context.makeLedger()
        let account = context.makeAccount("现金", ledger: ledger)
        let members = (1...3).map { context.makeMember("成员\($0)", ledger: ledger) }

        let total = Decimal(string: "7.77")!
        let percentages = [Decimal(33), Decimal(33), Decimal(34)]
        XCTAssertEqual(percentages.reduce(0, +), 100, "百分比确实凑满 100%，View 的 isAmountValid 拦不住这种")
        // 与 SplitFormView 的百分比算法逐字一致
        let amounts = percentages.map { total * $0 / 100 }

        let tx = context.makeTransaction(amount: -total, account: account, ledger: ledger)
        let group = try service.createSplit(
            totalAmount: total, currencyCode: "CNY", splitType: .percentage,
            members: members, amounts: amounts, note: nil, date: Date(),
            transaction: tx, ledger: ledger, context: context
        )

        XCTAssertEqual(group.totalAmountInFen, 777)
        let fenSum = (group.entries ?? []).reduce(Int64(0)) { $0 + $1.amountInFen }
        XCTAssertEqual(fenSum, 776, "已知缺口：256+256+264，比总额少 1 分")

        try service.settleSplit(group, context: context)
        XCTAssertNotEqual(
            group.settlementStatus, .settled,
            "已知缺口：付清也到不了 .settled。修好后这条会红 —— 届时改成 XCTAssertEqual 并更新清单 §六-8-2"
        )
    }

    /// settleSplit：已付的 entry 不修改
    func test_settleSplit_doesNotResetPaidEntries() throws {
        let ledger = context.makeLedger()
        let account = context.makeAccount("现金", ledger: ledger)
        let m1 = context.makeMember("A", ledger: ledger)
        let m2 = context.makeMember("B", ledger: ledger)
        let tx = context.makeTransaction(amount: -200, account: account, ledger: ledger)
        let group = try service.createSplit(
            totalAmount: 200, currencyCode: "CNY", splitType: .equal,
            members: [m1, m2], amounts: nil, note: nil, date: Date(),
            transaction: tx, ledger: ledger, context: context
        )

        let firstEntry = group.entries!.first!
        let firstOriginalDate = Date(timeIntervalSince1970: 1_000_000)
        firstEntry.isPaid = true
        firstEntry.paidDate = firstOriginalDate
        try context.save()

        try service.settleSplit(group, context: context)

        // 已付的 paidDate 不应被覆盖
        XCTAssertEqual(firstEntry.paidDate, firstOriginalDate)
        // 全部已付
        XCTAssertTrue(group.entries!.allSatisfy { $0.isPaid })
    }

    // MARK: - fetchSplits

    /// fetchSplits：返回该 ledger 的全部 split groups
    func test_fetchSplits_returnsAllInLedger() throws {
        let ledger = context.makeLedger()
        let account = context.makeAccount("现金", ledger: ledger)
        let m1 = context.makeMember("A", ledger: ledger)

        for _ in 1...3 {
            let tx = context.makeTransaction(amount: -100, account: account, ledger: ledger)
            _ = try service.createSplit(
                totalAmount: 100, currencyCode: "CNY", splitType: .equal,
                members: [m1], amounts: nil, note: nil, date: Date(),
                transaction: tx, ledger: ledger, context: context
            )
        }

        let results = try service.fetchSplits(for: ledger, context: context)
        XCTAssertEqual(results.count, 3)
    }

    /// fetchSplits：不同 ledger 隔离
    func test_fetchSplits_isolatesByLedger() throws {
        let ledgerA = context.makeLedger("A")
        let ledgerB = context.makeLedger("B")
        let accountA = context.makeAccount("A账户", ledger: ledgerA)
        let accountB = context.makeAccount("B账户", ledger: ledgerB)
        let mA = context.makeMember("A成员", ledger: ledgerA)
        let mB = context.makeMember("B成员", ledger: ledgerB)

        for _ in 1...2 {
            let tx = context.makeTransaction(amount: -50, account: accountA, ledger: ledgerA)
            _ = try service.createSplit(
                totalAmount: 50, currencyCode: "CNY", splitType: .equal,
                members: [mA], amounts: nil, note: nil, date: Date(),
                transaction: tx, ledger: ledgerA, context: context
            )
        }
        let tx = context.makeTransaction(amount: -100, account: accountB, ledger: ledgerB)
        _ = try service.createSplit(
            totalAmount: 100, currencyCode: "CNY", splitType: .equal,
            members: [mB], amounts: nil, note: nil, date: Date(),
            transaction: tx, ledger: ledgerB, context: context
        )

        let resultsA = try service.fetchSplits(for: ledgerA, context: context)
        let resultsB = try service.fetchSplits(for: ledgerB, context: context)
        XCTAssertEqual(resultsA.count, 2)
        XCTAssertEqual(resultsB.count, 1)
        XCTAssertEqual(resultsA.first?.ledger, ledgerA)
    }

    /// fetchSplits 按 date 倒序
    func test_fetchSplits_sortedByDateDescending() throws {
        let ledger = context.makeLedger()
        let account = context.makeAccount("现金", ledger: ledger)
        let m1 = context.makeMember("A", ledger: ledger)

        let tx1 = context.makeTransaction(amount: -50, date: TestDates.date(2024, 1, 1), account: account, ledger: ledger)
        _ = try service.createSplit(
            totalAmount: 50, currencyCode: "CNY", splitType: .equal,
            members: [m1], amounts: nil, note: nil,
            date: TestDates.date(2024, 1, 1),
            transaction: tx1, ledger: ledger, context: context
        )
        let tx2 = context.makeTransaction(amount: -100, date: TestDates.date(2024, 6, 1), account: account, ledger: ledger)
        _ = try service.createSplit(
            totalAmount: 100, currencyCode: "CNY", splitType: .equal,
            members: [m1], amounts: nil, note: nil,
            date: TestDates.date(2024, 6, 1),
            transaction: tx2, ledger: ledger, context: context
        )
        let tx3 = context.makeTransaction(amount: -30, date: TestDates.date(2024, 3, 1), account: account, ledger: ledger)
        _ = try service.createSplit(
            totalAmount: 30, currencyCode: "CNY", splitType: .equal,
            members: [m1], amounts: nil, note: nil,
            date: TestDates.date(2024, 3, 1),
            transaction: tx3, ledger: ledger, context: context
        )

        let results = try service.fetchSplits(for: ledger, context: context)
        XCTAssertEqual(results.count, 3)
        // 倒序：6月 > 3月 > 1月
        XCTAssertGreaterThan(results[0].date, results[1].date)
        XCTAssertGreaterThan(results[1].date, results[2].date)
    }

    // MARK: - 边界场景

    /// empty members + equal 模式：仍能创建 0 entries 的 group
    /// 注：service 不阻止 empty members（上层 UI 责任）
    func test_createSplit_emptyMembers_createsEmptyGroup() throws {
        let ledger = context.makeLedger()
        let account = context.makeAccount("现金", ledger: ledger)
        let tx = context.makeTransaction(amount: -100, account: account, ledger: ledger)

        let group = try service.createSplit(
            totalAmount: 100, currencyCode: "CNY", splitType: .equal,
            members: [], amounts: nil, note: nil, date: Date(),
            transaction: tx, ledger: ledger, context: context
        )

        XCTAssertEqual(group.entries?.count ?? 0, 0)
        XCTAssertEqual(group.totalAmount, 100)
    }

    /// equal 模式下 totalAmount = 0：每人分 0
    func test_createSplit_equal_zeroAmount_allZero() throws {
        let ledger = context.makeLedger()
        let account = context.makeAccount("现金", ledger: ledger)
        let m1 = context.makeMember("A", ledger: ledger)
        let m2 = context.makeMember("B", ledger: ledger)
        let tx = context.makeTransaction(amount: 0, account: account, ledger: ledger)

        let group = try service.createSplit(
            totalAmount: 0, currencyCode: "CNY", splitType: .equal,
            members: [m1, m2], amounts: nil, note: nil, date: Date(),
            transaction: tx, ledger: ledger, context: context
        )

        let entries = (group.entries ?? [])
        let amounts = entries.map { $0.amount }
        XCTAssertEqual(amounts, [0, 0])
    }
}