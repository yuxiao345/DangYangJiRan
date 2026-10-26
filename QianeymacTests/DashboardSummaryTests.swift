import Foundation
import Testing
@preconcurrency import CoreData
@testable import Qianeymac

/// 总览卡片与明细页共用同一口径的回归测试（Mac）。
///
/// 必须 `@MainActor`：Swift Testing 默认在协作线程池跑测试，而 fixture 用的是
/// `.mainQueueConcurrencyType` context，非主线程访问会随机崩（详见 `BudgetServiceTests` 的注释）。
@MainActor
@Suite(.serialized)
struct DashboardSummaryTests {

    // MARK: - Per-test state

    let context: NSManagedObjectContext

    init() {
        context = InMemoryCoreDataStack.makeContext()
    }

    // MARK: - Fixtures

    private func save() {
        if let error = context.saveAsError() { fatalError("save failed: \(error)") }
    }

    @discardableResult
    private func makeTx(
        _ amount: Decimal,
        date: Date,
        type: TransactionType,
        ledger: Ledger,
        account: Account,
        reimbursement: ReimbursementStatus = .none,
        refundGroupId: UUID? = nil,
        isSplitParent: Bool = false,
        parent: Transaction? = nil
    ) -> Transaction {
        let t = Transaction(
            type: type,
            amount: amount,
            date: date,
            refundGroupId: refundGroupId,
            reimbursementStatus: reimbursement,
            account: account,
            isSplitParent: isSplitParent,
            parentTransaction: parent,
            context: context
        )
        t.ledger = ledger
        save()
        return t
    }

    private func date(_ day: Int, in monthStart: Date) -> Date {
        Calendar.current.date(byAdding: .day, value: day - 1, to: monthStart.addingTimeInterval(12 * 3600))!
    }

    private func loadViewModel(ledger: Ledger) -> DashboardViewModel {
        let viewModel = DashboardViewModel(
            accountService: AccountServiceImpl(),
            transactionService: TransactionServiceImpl(),
            ledger: ledger
        )
        viewModel.load(context: context, budgetService: BudgetServiceImpl())
        return viewModel
    }

    // MARK: - 收入

    @Test func incomeCardMatchesDetailList() {
        let ledger = context.makeLedger()
        let account = context.makeAccount("测试账户", ledger)
        let monthStart = Date.now.startOfMonth

        let income1 = makeTx(1000, date: date(2, in: monthStart), type: .income, ledger: ledger, account: account)
        let income2 = makeTx(500, date: date(15, in: monthStart), type: .income, ledger: ledger, account: account)
        makeTx(-300, date: date(5, in: monthStart), type: .expense, ledger: ledger, account: account)

        // 可报销支出及其报销结算收入：卡片口径两者都排除
        let reimbursable = makeTx(
            -200, date: date(6, in: monthStart), type: .expense, ledger: ledger, account: account,
            reimbursement: .pending
        )
        let settlement = makeTx(200, date: date(7, in: monthStart), type: .income, ledger: ledger, account: account)
        // 字段方向：`reimbursedById` 挂在**支出**上，指向结清它的那笔收入
        reimbursable.reimbursedById = settlement.id
        save()

        let viewModel = loadViewModel(ledger: ledger)
        #expect(viewModel.monthlyIncome == 1500)

        let entry = DashboardAmountNavEntry(kind: .income, monthStart: monthStart, ledgerID: ledger.id)
        let detail = TransactionServiceImpl().incomeTransactions(
            in: entry.incomeRange, for: ledger, context: context
        )

        #expect(Set(detail.map(\.id)) == Set([income1.id, income2.id]))
        #expect(detail.reduce(Decimal.zero) { $0 + $1.ledgerAmount } == viewModel.monthlyIncome)
    }

    // MARK: - 支出

    @Test func expenseCardMatchesDetailList() {
        let ledger = context.makeLedger()
        let account = context.makeAccount("测试账户", ledger)
        let monthStart = Date.now.startOfMonth

        let normal = makeTx(-300, date: date(3, in: monthStart), type: .expense, ledger: ledger, account: account)
        // 退款：type 仍是 expense、金额为正，netExpenseAmount 记负
        let refund = makeTx(
            100, date: date(4, in: monthStart), type: .expense, ledger: ledger, account: account,
            refundGroupId: UUID()
        )
        makeTx(
            -200, date: date(5, in: monthStart), type: .expense, ledger: ledger, account: account,
            reimbursement: .pending
        )
        // 拆分：父交易不计、子交易计入
        let splitParent = makeTx(
            -100, date: date(6, in: monthStart), type: .expense, ledger: ledger, account: account,
            isSplitParent: true
        )
        let child1 = makeTx(-50, date: date(6, in: monthStart), type: .expense, ledger: ledger, account: account, parent: splitParent)
        let child2 = makeTx(-50, date: date(6, in: monthStart), type: .expense, ledger: ledger, account: account, parent: splitParent)

        let viewModel = loadViewModel(ledger: ledger)
        // 300 - 100（退款）+ 50 + 50（拆分子项）= 300
        #expect(abs(viewModel.monthlyExpense) == 300)

        let entry = DashboardAmountNavEntry(kind: .expense, monthStart: monthStart, ledgerID: ledger.id)
        let detail = BudgetServiceImpl().expenseTransactions(
            in: entry.expenseRange, ledger: ledger, context: context
        )
        let detailIDs = Set(detail.map(\.id))

        #expect(detailIDs.contains(normal.id))
        #expect(detailIDs.contains(refund.id))
        #expect(!detailIDs.contains(splitParent.id))
        #expect(detailIDs.contains(child1.id))
        #expect(detailIDs.contains(child2.id))
        #expect(detail.reduce(Decimal.zero) { $0 + $1.netExpenseAmount } == abs(viewModel.monthlyExpense))
    }

    /// 退款多于支出时 `totalExpense` 会被截断到 0，但明细集合仍非空——
    /// 明细页不显示合计，靠口径说明避免用户困惑。与 iOS 用例对齐。
    @Test func expenseCardClampsAtZeroButDetailStaysNonEmpty() {
        let ledger = context.makeLedger()
        let account = context.makeAccount("测试账户", ledger)
        let monthStart = Date.now.startOfMonth

        makeTx(
            500, date: date(3, in: monthStart), type: .expense, ledger: ledger, account: account,
            refundGroupId: UUID()
        )

        let viewModel = loadViewModel(ledger: ledger)
        #expect(viewModel.monthlyExpense == 0)

        let entry = DashboardAmountNavEntry(kind: .expense, monthStart: monthStart, ledgerID: ledger.id)
        let detail = BudgetServiceImpl().expenseTransactions(
            in: entry.expenseRange, ledger: ledger, context: context
        )
        #expect(detail.count == 1)
    }

    // MARK: - 区间边界

    @Test func detailRangesIncludeWholeMonthAndExcludeNextMonth() {
        let ledger = context.makeLedger()
        let account = context.makeAccount("测试账户", ledger)

        let monthStart = Date.now.startOfMonth
        let nextMonthStart = Calendar.current.date(byAdding: .month, value: 1, to: monthStart)!
        let lastSecond = nextMonthStart.addingTimeInterval(-1)

        let firstSecondIncome = makeTx(10, date: monthStart, type: .income, ledger: ledger, account: account)
        let lastSecondIncome = makeTx(20, date: lastSecond, type: .income, ledger: ledger, account: account)
        makeTx(30, date: nextMonthStart, type: .income, ledger: ledger, account: account)

        let firstSecondExpense = makeTx(-10, date: monthStart, type: .expense, ledger: ledger, account: account)
        let lastSecondExpense = makeTx(-20, date: lastSecond, type: .expense, ledger: ledger, account: account)
        makeTx(-30, date: nextMonthStart, type: .expense, ledger: ledger, account: account)

        let entry = DashboardAmountNavEntry(kind: .income, monthStart: monthStart, ledgerID: ledger.id)
        let incomeIDs = Set(TransactionServiceImpl().incomeTransactions(
            in: entry.incomeRange, for: ledger, context: context
        ).map(\.id))
        #expect(incomeIDs == Set([firstSecondIncome.id, lastSecondIncome.id]))

        let expenseIDs = Set(BudgetServiceImpl().expenseTransactions(
            in: entry.expenseRange, ledger: ledger, context: context
        ).map(\.id))
        #expect(expenseIDs == Set([firstSecondExpense.id, lastSecondExpense.id]))
    }
}
