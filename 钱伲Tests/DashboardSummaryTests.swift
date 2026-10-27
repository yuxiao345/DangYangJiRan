import XCTest
@preconcurrency import CoreData
@testable import 钱伲

/// 总览卡片与明细页共用同一口径的回归测试。
///
/// 卡片金额由 `DashboardViewModel` 算，明细集合由 service 算；两边若各用一套过滤规则，
/// 就会出现「卡片 3000、点进去 3500」的差。这里把两边钉在一起：
/// 明细 `Σ ledgerAmount` / `Σ netExpenseAmount` 必须等于卡片数字。
@MainActor
final class DashboardSummaryTests: CoreDataTestCase {

    // MARK: - Helpers

    private func date(_ day: Int, in monthStart: Date) -> Date {
        Calendar.current.date(byAdding: .day, value: day - 1, to: monthStart.addingTimeInterval(12 * 3600))!
    }

    // MARK: - 收入

    func testIncomeCardMatchesDetailList() {
        let ledger = context.makeLedger()
        let account = context.makeAccount(ledger: ledger)
        let monthStart = Date.now.startOfMonth

        let income1 = context.makeTransaction(amount: 1000, date: date(2, in: monthStart), account: account, ledger: ledger, type: .income)
        let income2 = context.makeTransaction(amount: 500, date: date(15, in: monthStart), account: account, ledger: ledger, type: .income)
        context.makeTransaction(amount: -300, date: date(5, in: monthStart), account: account, ledger: ledger, type: .expense)
        // 可报销支出和它的报销结算收入：卡片口径两者都排除
        let reimbursable = context.makeTransaction(
            amount: -200, date: date(6, in: monthStart), account: account, ledger: ledger,
            type: .expense, reimbursementStatus: .pending
        )
        let settlement = context.makeTransaction(
            amount: 200, date: date(7, in: monthStart), account: account, ledger: ledger, type: .income
        )
        // 字段方向：`reimbursedById` 挂在**支出**上，指向结清它的那笔收入
        reimbursable.reimbursedById = settlement.id
        try! context.save()

        let viewModel = DashboardViewModel(
            accountService: AccountServiceImpl(),
            transactionService: TransactionServiceImpl(),
            ledger: ledger
        )
        viewModel.load(context: context, budgetService: BudgetServiceImpl())

        XCTAssertEqual(viewModel.monthlyIncome, 1500)

        let entry = DashboardAmountNavEntry(kind: .income, monthStart: monthStart, ledgerID: ledger.id)
        let detail = TransactionServiceImpl().incomeTransactions(
            in: entry.incomeRange, for: ledger, context: context
        )

        XCTAssertEqual(Set(detail.map(\.id)), Set([income1.id, income2.id]))
        XCTAssertEqual(detail.reduce(Decimal.zero) { $0 + $1.ledgerAmount }, viewModel.monthlyIncome)
    }

    // MARK: - 支出

    func testExpenseCardMatchesDetailList() {
        let ledger = context.makeLedger()
        let account = context.makeAccount(ledger: ledger)
        let monthStart = Date.now.startOfMonth

        let normal = context.makeTransaction(amount: -300, date: date(3, in: monthStart), account: account, ledger: ledger, type: .expense)
        // 退款：type 仍是 expense，金额为正，netExpenseAmount 记负
        let refund = context.makeTransaction(
            amount: 100, date: date(4, in: monthStart), account: account, ledger: ledger,
            type: .expense, refundGroupId: UUID()
        )
        context.makeTransaction(
            amount: -200, date: date(5, in: monthStart), account: account, ledger: ledger,
            type: .expense, reimbursementStatus: .pending
        )
        // 拆分：父交易不计、子交易计入
        let splitParent = context.makeSplitTransaction(
            [SplitItemFixture(amount: 50), SplitItemFixture(amount: 50)],
            date: date(6, in: monthStart), account: account, ledger: ledger
        )
        let childRequest = NSFetchRequest<Transaction>(entityName: "Transaction")
        childRequest.predicate = NSPredicate(format: "parentTransaction == %@", splitParent)
        let childIDs = Set(try! context.fetch(childRequest).map(\.id))

        let viewModel = DashboardViewModel(
            accountService: AccountServiceImpl(),
            transactionService: TransactionServiceImpl(),
            ledger: ledger
        )
        viewModel.load(context: context, budgetService: BudgetServiceImpl())

        // 300 - 100（退款）+ 50 + 50（拆分子项）= 300
        XCTAssertEqual(abs(viewModel.monthlyExpense), 300)

        let entry = DashboardAmountNavEntry(kind: .expense, monthStart: monthStart, ledgerID: ledger.id)
        let detail = BudgetServiceImpl().expenseTransactions(
            in: entry.expenseRange, ledger: ledger, context: context
        )

        let detailIDs = Set(detail.map(\.id))
        XCTAssertTrue(detailIDs.contains(normal.id))
        XCTAssertTrue(detailIDs.contains(refund.id))
        XCTAssertFalse(detailIDs.contains(splitParent.id), "拆分父交易不应计入，否则与子项双计")
        XCTAssertTrue(childIDs.isSubset(of: detailIDs), "拆分子交易必须计入")
        XCTAssertEqual(detail.reduce(Decimal.zero) { $0 + $1.netExpenseAmount }, abs(viewModel.monthlyExpense))
    }

    /// 退款多于支出时 `totalExpense` 会被截断到 0，但明细集合仍非空——
    /// 明细页不显示合计，靠口径说明避免用户困惑。这里固定住这个已知边界。
    func testExpenseCardClampsAtZeroButDetailStaysNonEmpty() {
        let ledger = context.makeLedger()
        let account = context.makeAccount(ledger: ledger)
        let monthStart = Date.now.startOfMonth

        context.makeTransaction(
            amount: 500, date: date(3, in: monthStart), account: account, ledger: ledger,
            type: .expense, refundGroupId: UUID()
        )

        let viewModel = DashboardViewModel(
            accountService: AccountServiceImpl(),
            transactionService: TransactionServiceImpl(),
            ledger: ledger
        )
        viewModel.load(context: context, budgetService: BudgetServiceImpl())

        XCTAssertEqual(viewModel.monthlyExpense, 0)

        let entry = DashboardAmountNavEntry(kind: .expense, monthStart: monthStart, ledgerID: ledger.id)
        let detail = BudgetServiceImpl().expenseTransactions(
            in: entry.expenseRange, ledger: ledger, context: context
        )
        XCTAssertEqual(detail.count, 1)
    }

    // MARK: - 区间边界

    func testDetailRangesIncludeWholeMonthAndExcludeNextMonth() {
        let ledger = context.makeLedger()
        let account = context.makeAccount(ledger: ledger)

        let monthStart = Date.now.startOfMonth
        let nextMonthStart = Calendar.current.date(byAdding: .month, value: 1, to: monthStart)!
        let lastSecond = nextMonthStart.addingTimeInterval(-1)

        let firstSecondIncome = context.makeTransaction(amount: 10, date: monthStart, account: account, ledger: ledger, type: .income)
        let lastSecondIncome = context.makeTransaction(amount: 20, date: lastSecond, account: account, ledger: ledger, type: .income)
        context.makeTransaction(amount: 30, date: nextMonthStart, account: account, ledger: ledger, type: .income)

        let firstSecondExpense = context.makeTransaction(amount: -10, date: monthStart, account: account, ledger: ledger, type: .expense)
        let lastSecondExpense = context.makeTransaction(amount: -20, date: lastSecond, account: account, ledger: ledger, type: .expense)
        context.makeTransaction(amount: -30, date: nextMonthStart, account: account, ledger: ledger, type: .expense)

        let entry = DashboardAmountNavEntry(kind: .income, monthStart: monthStart, ledgerID: ledger.id)
        let incomeIDs = Set(TransactionServiceImpl().incomeTransactions(
            in: entry.incomeRange, for: ledger, context: context
        ).map(\.id))
        XCTAssertEqual(incomeIDs, Set([firstSecondIncome.id, lastSecondIncome.id]))

        let expenseIDs = Set(BudgetServiceImpl().expenseTransactions(
            in: entry.expenseRange, ledger: ledger, context: context
        ).map(\.id))
        XCTAssertEqual(expenseIDs, Set([firstSecondExpense.id, lastSecondExpense.id]))
    }

    // MARK: - 较上月（净资产变化）

    /// 借贷交易只记现金侧金额，另一侧应收/应付由 `calculateBalance` 补上。
    /// 「较上月」必须按余额差算，不能拿当月交易金额求和——否则借出月会显示假下跌。
    func testBalanceChangeTreatsLendingAsNeutral() {
        let ledger = context.makeLedger()
        let cash = context.makeAccount("现金", ledger: ledger, initialBalance: 10_000)
        let lending = context.makeAccount("借给朋友", ledger: ledger, type: .lending)
        let monthStart = Date.now.startOfMonth

        context.makeTransaction(
            amount: 5_000, date: date(2, in: monthStart), account: cash, ledger: ledger, type: .income
        )
        // 借出 2,000：现金 -2,000，借贷账户 +2,000 应收，净资产不变
        context.makeTransaction(
            amount: -2_000, date: date(3, in: monthStart), account: cash, toAccount: lending,
            ledger: ledger, type: .lending, lendingDirection: .lendOut, lendingStatus: .pending
        )

        let viewModel = DashboardViewModel(
            accountService: AccountServiceImpl(),
            transactionService: TransactionServiceImpl(),
            ledger: ledger
        )
        viewModel.load(context: context, budgetService: BudgetServiceImpl())

        XCTAssertEqual(viewModel.totalBalance, 15_000)
        XCTAssertEqual(viewModel.balanceChange, 5_000, "借出不应让净资产变化变负")
    }
}
