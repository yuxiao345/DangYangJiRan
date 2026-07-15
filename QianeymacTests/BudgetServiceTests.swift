import Foundation
import Testing
@preconcurrency import CoreData
@testable import Qianeymac

@Suite(.serialized) struct BudgetServiceTests {

    // MARK: - Per-test state

    let context: NSManagedObjectContext
    let service: BudgetServiceImpl

    init() {
        context = Self.makeContext()
        service = BudgetServiceImpl()
    }

    // MARK: - Infrastructure

    /// 缓存的 NSManagedObjectModel（不可变，线程安全），带重试应对并行测试启动竞态
    private static let cachedModel: NSManagedObjectModel = {
        for _ in 0..<20 {
            if let model = NSManagedObjectModel.mergedModel(from: nil) {
                return model
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        if let model = NSManagedObjectModel.mergedModel(from: Bundle.allBundles) {
            return model
        }
        if let url = Bundle(for: BudgetBook.self).url(forResource: "FirstCC", withExtension: "momd"),
           let model = NSManagedObjectModel(contentsOf: url) {
            return model
        }
        fatalError("Cannot find CoreData model 'FirstCC.momd' in any bundle")
    }()

    /// 每次调用创建独立的 in-memory CoreData stack（每个 test 拥有隔离的数据空间）
    static func makeContext() -> NSManagedObjectContext {
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: cachedModel)
        try! coordinator.addPersistentStore(ofType: NSInMemoryStoreType, configurationName: nil, at: nil)
        let ctx = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        ctx.persistentStoreCoordinator = coordinator
        return ctx
    }

    // MARK: Helpers

    private func date(_ y: Int, _ m: Int, _ d: Int, hr: Int = 12) -> Date {
        Calendar.current.date(from: DateComponents(year: y, month: m, day: d, hour: hr))!
    }

    @discardableResult
    private func makeLedger(_ name: String = "测试账本") -> Ledger {
        let l = Ledger(name: name, context: context)
        l.defaultCurrencyCode = "CNY"
        try! context.save()
        return l
    }

    @discardableResult
    private func makeAccount(_ name: String = "测试账户", _ ledger: Ledger) -> Account {
        let a = Account(name: name, context: context)
        a.ledger = ledger
        try! context.save()
        return a
    }

    @discardableResult
    private func makeCategory(_ name: String, _ ledger: Ledger, type: TransactionType = .expense, parent: Qianeymac.Category? = nil) -> Qianeymac.Category {
        let c = Qianeymac.Category(name: name, type: type, parent: parent, context: context)
        c.ledger = ledger
        try! context.save()
        return c
    }

    @discardableResult
    private func makeBook(_ name: String, start: Date, end: Date, _ ledger: Ledger) -> BudgetBook {
        let b = BudgetBook(name: name, startDate: start, endDate: end, context: context)
        b.ledger = ledger
        try! context.save()
        return b
    }

    @discardableResult
    private func makeItem(amount: Decimal, period: BudgetPeriod = .monthly, category: Qianeymac.Category, book: BudgetBook) -> BudgetItem {
        let i = BudgetItem(amount: amount, period: period, category: category, context: context)
        i.book = book
        try! context.save()
        return i
    }

    @discardableResult
    private func makeTx(
        amount: Decimal,
        date: Date,
        category: Qianeymac.Category,
        account: Account,
        ledger: Ledger,
        type: TransactionType = .expense,
        isSplitParent: Bool = false,
        parent: Transaction? = nil,
        reimbursement: ReimbursementStatus = .none,
        currency: String = "CNY",
        converted: Decimal? = nil,
        refundGroupId: UUID? = nil
    ) -> Transaction {
        let t = Transaction(
            type: type,
            amount: amount,
            currencyCode: currency,
            convertedAmount: converted,
            date: date,
            refundGroupId: refundGroupId,
            reimbursementStatus: reimbursement,
            account: account,
            category: category,
            isSplitParent: isSplitParent,
            parentTransaction: parent,
            context: context
        )
        t.ledger = ledger
        try! context.save()
        return t
    }

    // MARK: - 1. 预算周期计算

    /// 同自然年整年：2026-01-01 → 2026-12-31，年度预算
    @Test func periodCount_sameCalendarYear_fullYear() {
        let ledger = makeLedger()
        let cat = makeCategory("餐饮", ledger)
        let book = makeBook("2026年度预算", start: date(2026, 1, 1), end: date(2026, 12, 31), ledger)
        let item = makeItem(amount: 12000, period: .yearly, category: cat, book: book)

        #expect(abs(item.periodCount - 1.0) < 0.1)
        #expect(item.totalBudget == 12000)
    }

    /// 同自然年非整年：2026-03-01 → 2026-11-30（约9个月），月度预算
    @Test func periodCount_sameCalendarYear_partialYear() {
        let ledger = makeLedger()
        let cat = makeCategory("交通", ledger)
        let book = makeBook("春季预算", start: date(2026, 3, 1), end: date(2026, 11, 30), ledger)
        let item = makeItem(amount: 500, period: .monthly, category: cat, book: book)

        #expect(abs(item.periodCount - 9.0) < 1.5)
        #expect(item.totalBudget == Decimal(item.periodCount) * 500)
    }

    /// 跨自然年整年：2025-07-01 → 2026-06-30，年度预算
    @Test func periodCount_crossYear_fullYear() {
        let ledger = makeLedger()
        let cat = makeCategory("教育", ledger)
        let book = makeBook("学年预算", start: date(2025, 7, 1), end: date(2026, 6, 30), ledger)
        let item = makeItem(amount: 50000, period: .yearly, category: cat, book: book)

        #expect(abs(item.periodCount - 1.0) < 0.1)
        #expect(item.totalBudget == 50000)
    }

    /// 跨自然年非整年：2025-11-01 → 2026-02-28（约4个月），月度预算
    @Test func periodCount_crossYear_partial() {
        let ledger = makeLedger()
        let cat = makeCategory("取暖", ledger)
        let book = makeBook("冬季预算", start: date(2025, 11, 1), end: date(2026, 2, 28), ledger)
        let item = makeItem(amount: 2000, period: .monthly, category: cat, book: book)

        #expect(abs(item.periodCount - 4.0) < 1.0)
        #expect(item.totalBudget == Decimal(item.periodCount) * 2000)
    }

    /// 多年：2025-01-01 → 2027-12-31（3年），年度预算
    @Test func periodCount_multiYear() {
        let ledger = makeLedger()
        let cat = makeCategory("住房", ledger)
        let book = makeBook("三年预算", start: date(2025, 1, 1), end: date(2027, 12, 31), ledger)
        let item = makeItem(amount: 36000, period: .yearly, category: cat, book: book)

        #expect(abs(item.periodCount - 3.0) < 0.5)
        #expect(item.totalBudget == Decimal(item.periodCount) * 36000)
    }

    /// 周期归一化：不同周期的预算项在 totalCurrentPeriodBudget 中被归一化到月度
    @Test func periodNormalization_differentPeriods_normalizedToMonthly() {
        let ledger = makeLedger()
        let cat1 = makeCategory("餐饮", ledger)
        let cat2 = makeCategory("交通", ledger)
        let cat3 = makeCategory("购物", ledger)
        let book = makeBook("混合周期", start: date(2026, 1, 1), end: date(2026, 12, 31), ledger)

        makeItem(amount: 12000, period: .yearly, category: cat1, book: book)
        makeItem(amount: 3000, period: .quarterly, category: cat2, book: book)
        makeItem(amount: 1000, period: .monthly, category: cat3, book: book)

        let monthlyBudget = service.totalCurrentPeriodBudget(for: book)
        #expect(abs(monthlyBudget - 3000) <= 10)
    }

    // MARK: - 2. 分类层级

    // MARK: 2.1 只做一级分类预算

    /// 只给一级分类做预算，子分类的支出应被计入
    @Test func categoryHierarchy_onlyParentBudgeted_childSpendingIncluded() {
        let ledger = makeLedger()
        let account = makeAccount("现金", ledger)
        let parentCat = makeCategory("餐饮", ledger)
        let childCat = makeCategory("午餐", ledger, parent: parentCat)
        let book = makeBook("餐饮预算", start: date(2026, 1, 1), end: date(2026, 12, 31), ledger)
        let item = makeItem(amount: 3000, period: .monthly, category: parentCat, book: book)

        makeTx(amount: -500, date: date(2026, 7, 5), category: parentCat, account: account, ledger: ledger)
        makeTx(amount: -300, date: date(2026, 7, 8), category: childCat, account: account, ledger: ledger)

        let spending = service.cumulativeSpending(for: item, context: context)
        #expect(spending == 800)
    }

    /// 只给一级分类做预算，不相关的分类支出不应被计入
    @Test func categoryHierarchy_onlyParentBudgeted_unrelatedExcluded() {
        let ledger = makeLedger()
        let account = makeAccount("现金", ledger)
        let parentCat = makeCategory("餐饮", ledger)
        let childCat = makeCategory("午餐", ledger, parent: parentCat)
        let unrelatedCat = makeCategory("交通", ledger)
        let book = makeBook("餐饮预算", start: date(2026, 1, 1), end: date(2026, 12, 31), ledger)
        let item = makeItem(amount: 3000, period: .monthly, category: parentCat, book: book)

        makeTx(amount: -500, date: date(2026, 7, 5), category: childCat, account: account, ledger: ledger)
        makeTx(amount: -200, date: date(2026, 7, 6), category: unrelatedCat, account: account, ledger: ledger)

        let spending = service.cumulativeSpending(for: item, context: context)
        #expect(spending == 500)
    }

    // MARK: 2.2 只做二级分类预算

    /// 只给二级分类做预算，仅该子分类的支出被计入
    @Test func categoryHierarchy_onlyChildBudgeted_onlyChildSpending() {
        let ledger = makeLedger()
        let account = makeAccount("现金", ledger)
        let parentCat = makeCategory("餐饮", ledger)
        let childCat = makeCategory("午餐", ledger, parent: parentCat)
        let siblingCat = makeCategory("晚餐", ledger, parent: parentCat)
        let book = makeBook("午餐预算", start: date(2026, 1, 1), end: date(2026, 12, 31), ledger)
        let item = makeItem(amount: 1000, period: .monthly, category: childCat, book: book)

        makeTx(amount: -200, date: date(2026, 7, 5), category: childCat, account: account, ledger: ledger)
        makeTx(amount: -300, date: date(2026, 7, 5), category: siblingCat, account: account, ledger: ledger)
        makeTx(amount: -400, date: date(2026, 7, 5), category: parentCat, account: account, ledger: ledger)

        let spending = service.cumulativeSpending(for: item, context: context)
        #expect(spending == 200)
    }

    // MARK: 2.3 一级和二级分类都有预算

    /// 父分类和子分类都有预算时，子分类在汇总时被视作子限额，不计入 book-level totalBudget
    @Test func categoryHierarchy_bothBudgeted_childExcludedFromTotalBudget() {
        let ledger = makeLedger()
        let parentCat = makeCategory("餐饮", ledger)
        let childCat = makeCategory("午餐", ledger, parent: parentCat)
        let book = makeBook("餐饮详细预算", start: date(2026, 1, 1), end: date(2026, 12, 31), ledger)

        let parentItem = makeItem(amount: 3000, period: .monthly, category: parentCat, book: book)
        let childItem = makeItem(amount: 1000, period: .monthly, category: childCat, book: book)

        let parentTotal = parentItem.totalBudget
        #expect(service.totalBudget(for: book) == parentTotal)
        #expect(service.totalBudget(for: book) != parentItem.totalBudget + childItem.totalBudget)
    }

    /// 父分类和子分类都有预算时，父项的 spending 仍包含子分类的全部交易
    @Test func categoryHierarchy_bothBudgeted_parentSpendingIncludesChild() {
        let ledger = makeLedger()
        let account = makeAccount("现金", ledger)
        let parentCat = makeCategory("餐饮", ledger)
        let childCat = makeCategory("午餐", ledger, parent: parentCat)
        let book = makeBook("餐饮详细预算", start: date(2026, 1, 1), end: date(2026, 12, 31), ledger)

        let parentItem = makeItem(amount: 3000, period: .monthly, category: parentCat, book: book)
        let childItem = makeItem(amount: 1000, period: .monthly, category: childCat, book: book)

        makeTx(amount: -500, date: date(2026, 7, 5), category: parentCat, account: account, ledger: ledger)
        makeTx(amount: -300, date: date(2026, 7, 6), category: childCat, account: account, ledger: ledger)

        #expect(service.cumulativeSpending(for: parentItem, context: context) == 800)
        #expect(service.cumulativeSpending(for: childItem, context: context) == 300)
    }

    // MARK: - 3. 预算执行准确性（一级包含二级）

    /// categorySpending 将子分类金额向上展开到所有祖先
    @Test func categorySpending_ancestorExpansion() {
        let ledger = makeLedger()
        let account = makeAccount("现金", ledger)
        let grandparent = makeCategory("生活", ledger)
        let parent = makeCategory("餐饮", ledger, parent: grandparent)
        let child = makeCategory("午餐", ledger, parent: parent)
        let book = makeBook("生活预算", start: date(2026, 1, 1), end: date(2026, 12, 31), ledger)

        makeTx(amount: -100, date: date(2026, 7, 5), category: child, account: account, ledger: ledger)

        let spending = service.categorySpending(in: date(2026, 1, 1)...date(2026, 12, 31), for: book, context: context)

        #expect(spending[child.id] == 100)
        #expect(spending[parent.id] == 100)
        #expect(spending[grandparent.id] == 100)
    }

    /// 一级预算通过 cumulativeSpending 正确汇总所有子分类
    @Test func budgetExecution_parentCumulativeSpending_matchesActualTransactions() {
        let ledger = makeLedger()
        let account = makeAccount("现金", ledger)
        let parentCat = makeCategory("购物", ledger)
        let child1 = makeCategory("衣服", ledger, parent: parentCat)
        let child2 = makeCategory("电子", ledger, parent: parentCat)
        let book = makeBook("购物预算", start: date(2026, 1, 1), end: date(2026, 12, 31), ledger)
        let item = makeItem(amount: 5000, period: .monthly, category: parentCat, book: book)

        makeTx(amount: -800, date: date(2026, 3, 10), category: parentCat, account: account, ledger: ledger)
        makeTx(amount: -1200, date: date(2026, 5, 15), category: child1, account: account, ledger: ledger)
        makeTx(amount: -3000, date: date(2026, 7, 1), category: child2, account: account, ledger: ledger)

        let spending = service.cumulativeSpending(for: item, context: context)
        #expect(spending == 5000)
    }

    // MARK: - 4. 拆分交易

    /// 拆分父交易被排除，拆分子交易按各自分类参与统计
    @Test func split_parentExcluded_childrenIncluded() {
        let ledger = makeLedger()
        let account = makeAccount("现金", ledger)
        let catA = makeCategory("餐饮", ledger)
        let catB = makeCategory("交通", ledger)
        let book = makeBook("总预算", start: date(2026, 1, 1), end: date(2026, 12, 31), ledger)
        let item = makeItem(amount: 10000, period: .monthly, category: catA, book: book)

        let splitParent = makeTx(amount: -500, date: date(2026, 7, 5), category: catA, account: account, ledger: ledger, isSplitParent: true)

        makeTx(amount: -300, date: date(2026, 7, 5), category: catA, account: account, ledger: ledger, parent: splitParent)
        makeTx(amount: -200, date: date(2026, 7, 5), category: catB, account: account, ledger: ledger, parent: splitParent)

        let spending = service.cumulativeSpending(for: item, context: context)
        #expect(spending == 300)
    }

    /// 拆分子交易按各自分类正确归入不同预算项
    @Test func split_childrenDifferentCategories_countedCorrectly() {
        let ledger = makeLedger()
        let account = makeAccount("现金", ledger)
        let catFood = makeCategory("餐饮", ledger)
        let catTransport = makeCategory("交通", ledger)
        let book = makeBook("总预算", start: date(2026, 1, 1), end: date(2026, 12, 31), ledger)

        let foodItem = makeItem(amount: 3000, period: .monthly, category: catFood, book: book)
        let transportItem = makeItem(amount: 1000, period: .monthly, category: catTransport, book: book)

        let splitParent = makeTx(amount: -800, date: date(2026, 7, 5), category: catFood, account: account, ledger: ledger, isSplitParent: true)

        makeTx(amount: -500, date: date(2026, 7, 5), category: catFood, account: account, ledger: ledger, parent: splitParent)
        makeTx(amount: -300, date: date(2026, 7, 5), category: catTransport, account: account, ledger: ledger, parent: splitParent)

        #expect(service.cumulativeSpending(for: foodItem, context: context) == 500)
        #expect(service.cumulativeSpending(for: transportItem, context: context) == 300)
    }

    // MARK: - 5. 退款

    /// 全额退款：支出 100 后退款 100，净支出为 0
    @Test func refund_fullRefund_netSpendingZero() {
        let ledger = makeLedger()
        let account = makeAccount("现金", ledger)
        let cat = makeCategory("购物", ledger)
        let book = makeBook("购物预算", start: date(2026, 1, 1), end: date(2026, 12, 31), ledger)
        let item = makeItem(amount: 3000, period: .monthly, category: cat, book: book)

        let original = makeTx(amount: -100, date: date(2026, 7, 5), category: cat, account: account, ledger: ledger)
        makeTx(amount: 100, date: date(2026, 7, 6), category: cat, account: account, ledger: ledger, refundGroupId: original.id)

        let spending = service.cumulativeSpending(for: item, context: context)
        #expect(spending == 0)
    }

    /// 部分退款：支出 100 后退款 40，净支出为 60
    @Test func refund_partialRefund_correctNetSpending() {
        let ledger = makeLedger()
        let account = makeAccount("现金", ledger)
        let cat = makeCategory("购物", ledger)
        let book = makeBook("购物预算", start: date(2026, 1, 1), end: date(2026, 12, 31), ledger)
        let item = makeItem(amount: 3000, period: .monthly, category: cat, book: book)

        let original = makeTx(amount: -100, date: date(2026, 7, 5), category: cat, account: account, ledger: ledger)
        makeTx(amount: 40, date: date(2026, 7, 7), category: cat, account: account, ledger: ledger, refundGroupId: original.id)

        #expect(service.cumulativeSpending(for: item, context: context) == 60)
    }

    /// 退款金额超过原支出：净支出 capped 为 0，不出现负数
    @Test func refund_exceedsOriginal_doesNotGoNegative() {
        let ledger = makeLedger()
        let account = makeAccount("现金", ledger)
        let cat = makeCategory("购物", ledger)
        let book = makeBook("购物预算", start: date(2026, 1, 1), end: date(2026, 12, 31), ledger)
        let item = makeItem(amount: 3000, period: .monthly, category: cat, book: book)

        let original = makeTx(amount: -100, date: date(2026, 7, 5), category: cat, account: account, ledger: ledger)
        makeTx(amount: 150, date: date(2026, 7, 6), category: cat, account: account, ledger: ledger, refundGroupId: original.id)

        #expect(service.cumulativeSpending(for: item, context: context) == 0)
    }

    // MARK: - 6. 报销排除

    /// 待报销支出被排除
    @Test func reimbursable_pending_excluded() {
        let ledger = makeLedger()
        let account = makeAccount("现金", ledger)
        let cat = makeCategory("差旅", ledger)
        let book = makeBook("差旅预算", start: date(2026, 1, 1), end: date(2026, 12, 31), ledger)
        let item = makeItem(amount: 5000, period: .monthly, category: cat, book: book)

        makeTx(amount: -300, date: date(2026, 7, 5), category: cat, account: account, ledger: ledger)
        makeTx(amount: -1000, date: date(2026, 7, 6), category: cat, account: account, ledger: ledger, reimbursement: .pending)

        #expect(service.cumulativeSpending(for: item, context: context) == 300)
    }

    /// 已批准待报销支出被排除
    @Test func reimbursable_approved_excluded() {
        let ledger = makeLedger()
        let account = makeAccount("现金", ledger)
        let cat = makeCategory("差旅", ledger)
        let book = makeBook("差旅预算", start: date(2026, 1, 1), end: date(2026, 12, 31), ledger)
        let item = makeItem(amount: 5000, period: .monthly, category: cat, book: book)

        makeTx(amount: -500, date: date(2026, 7, 5), category: cat, account: account, ledger: ledger)
        makeTx(amount: -2000, date: date(2026, 7, 6), category: cat, account: account, ledger: ledger, reimbursement: .approved)

        #expect(service.cumulativeSpending(for: item, context: context) == 500)
    }

    /// 已报销支出被排除
    @Test func reimbursable_reimbursed_excluded() {
        let ledger = makeLedger()
        let account = makeAccount("现金", ledger)
        let cat = makeCategory("差旅", ledger)
        let book = makeBook("差旅预算", start: date(2026, 1, 1), end: date(2026, 12, 31), ledger)
        let item = makeItem(amount: 5000, period: .monthly, category: cat, book: book)

        makeTx(amount: -400, date: date(2026, 7, 5), category: cat, account: account, ledger: ledger)
        makeTx(amount: -1500, date: date(2026, 7, 6), category: cat, account: account, ledger: ledger, reimbursement: .reimbursed)

        #expect(service.cumulativeSpending(for: item, context: context) == 400)
    }

    // MARK: - 7. 日期范围排除

    /// 预算书开始日期之前的交易不被计入
    @Test func dateRange_beforeBookStart_excluded() {
        let ledger = makeLedger()
        let account = makeAccount("现金", ledger)
        let cat = makeCategory("餐饮", ledger)
        let book = makeBook("2026预算", start: date(2026, 3, 1), end: date(2026, 12, 31), ledger)
        let item = makeItem(amount: 3000, period: .monthly, category: cat, book: book)

        makeTx(amount: -500, date: date(2026, 1, 15), category: cat, account: account, ledger: ledger)
        makeTx(amount: -800, date: date(2026, 7, 5), category: cat, account: account, ledger: ledger)

        let spending = service.cumulativeSpending(for: item, context: context)
        #expect(spending == 800)
    }

    /// 不在当前周期内的交易不被 currentPeriodSpending 计入
    @Test func dateRange_outsideCurrentPeriod_excluded() {
        let ledger = makeLedger()
        let account = makeAccount("现金", ledger)
        let cat = makeCategory("餐饮", ledger)
        let book = makeBook("2026预算", start: date(2026, 1, 1), end: date(2026, 12, 31), ledger)
        let item = makeItem(amount: 3000, period: .monthly, category: cat, book: book)

        makeTx(amount: -900, date: date(2026, 6, 20), category: cat, account: account, ledger: ledger)
        makeTx(amount: -400, date: date(2026, 7, 10), category: cat, account: account, ledger: ledger)

        let thisMonthSpending = service.currentPeriodSpending(for: item, context: context)
        #expect(thisMonthSpending == 400)

        let cumulative = service.cumulativeSpending(for: item, context: context)
        #expect(cumulative == 1300)
    }

    // MARK: - 8. 多币种

    /// 外币交易有 convertedAmount → 预算使用换算后的 CNY 金额
    @Test func multiCurrency_withConversion_usesConvertedAmount() {
        let ledger = makeLedger()
        let account = makeAccount("双币卡", ledger)
        let cat = makeCategory("购物", ledger)
        let book = makeBook("购物预算", start: date(2026, 1, 1), end: date(2026, 12, 31), ledger)
        let item = makeItem(amount: 5000, period: .monthly, category: cat, book: book)

        makeTx(amount: -500, date: date(2026, 7, 5), category: cat, account: account, ledger: ledger)
        makeTx(amount: -10, date: date(2026, 7, 8), category: cat, account: account, ledger: ledger, currency: "USD", converted: -72)

        let spending = service.cumulativeSpending(for: item, context: context)
        #expect(spending == 572)
    }

    /// 外币交易无 convertedAmount → 回退使用原始 amount
    @Test func multiCurrency_withoutConversion_fallsBackToRawAmount() {
        let ledger = makeLedger()
        let account = makeAccount("双币卡", ledger)
        let cat = makeCategory("购物", ledger)
        let book = makeBook("购物预算", start: date(2026, 1, 1), end: date(2026, 12, 31), ledger)
        let item = makeItem(amount: 5000, period: .monthly, category: cat, book: book)

        makeTx(amount: -10, date: date(2026, 7, 5), category: cat, account: account, ledger: ledger, currency: "USD")

        let spending = service.cumulativeSpending(for: item, context: context)
        #expect(spending == 10)
    }

    /// 同币种交易 → 直接使用 amount
    @Test func multiCurrency_sameCurrency_usesRawAmount() {
        let ledger = makeLedger()
        let account = makeAccount("人民币卡", ledger)
        let cat = makeCategory("餐饮", ledger)
        let book = makeBook("餐饮预算", start: date(2026, 1, 1), end: date(2026, 12, 31), ledger)
        let item = makeItem(amount: 3000, period: .monthly, category: cat, book: book)

        makeTx(amount: -200, date: date(2026, 7, 5), category: cat, account: account, ledger: ledger)
        makeTx(amount: -350, date: date(2026, 7, 8), category: cat, account: account, ledger: ledger)

        #expect(service.cumulativeSpending(for: item, context: context) == 550)
    }

    /// 混合币种：CNY + USD + JPY 同时存在
    @Test func multiCurrency_mixedCurrencies_correctTotal() {
        let ledger = makeLedger()
        let account = makeAccount("多币卡", ledger)
        let cat = makeCategory("购物", ledger)
        let book = makeBook("购物预算", start: date(2026, 1, 1), end: date(2026, 12, 31), ledger)
        let item = makeItem(amount: 10000, period: .monthly, category: cat, book: book)

        makeTx(amount: -500, date: date(2026, 7, 5), category: cat, account: account, ledger: ledger)
        makeTx(amount: -10, date: date(2026, 7, 6), category: cat, account: account, ledger: ledger, currency: "USD", converted: -72)
        makeTx(amount: -1000, date: date(2026, 7, 7), category: cat, account: account, ledger: ledger, currency: "JPY", converted: -50)

        #expect(service.cumulativeSpending(for: item, context: context) == 622)
    }

    /// 多币种退款：汇率波动导致净支出非零
    @Test func multiCurrency_refundWithExchangeRateChange() {
        let ledger = makeLedger()
        let account = makeAccount("双币卡", ledger)
        let cat = makeCategory("购物", ledger)
        let book = makeBook("购物预算", start: date(2026, 1, 1), end: date(2026, 12, 31), ledger)
        let item = makeItem(amount: 5000, period: .monthly, category: cat, book: book)

        let original = makeTx(amount: -100, date: date(2026, 7, 5), category: cat, account: account, ledger: ledger, currency: "USD", converted: -720)
        makeTx(amount: 100, date: date(2026, 7, 8), category: cat, account: account, ledger: ledger, currency: "USD", converted: 710, refundGroupId: original.id)

        let spending = service.cumulativeSpending(for: item, context: context)
        #expect(spending == 10)
    }
}
