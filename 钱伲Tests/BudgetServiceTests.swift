import XCTest
@preconcurrency import CoreData
@testable import 钱伲

final class BudgetServiceTests: XCTestCase {

    var context: NSManagedObjectContext!
    var service: BudgetServiceImpl!

    override func setUp() {
        super.setUp()
        context = createInMemoryContext()
        service = BudgetServiceImpl()
    }

    override func tearDown() {
        context = nil
        service = nil
        super.tearDown()
    }

    // MARK: - Test Infrastructure

    private func createInMemoryContext() -> NSManagedObjectContext {
        guard let modelURL = Bundle(for: BudgetBook.self).url(forResource: "FirstCC", withExtension: "momd"),
              let model = NSManagedObjectModel(contentsOf: modelURL) else {
            fatalError("Failed to load CoreData model from bundle")
        }
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
        try! coordinator.addPersistentStore(ofType: NSInMemoryStoreType, configurationName: nil, at: nil)
        let ctx = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        ctx.persistentStoreCoordinator = coordinator
        return ctx
    }

    // MARK: Helpers

    private func date(_ y: Int, _ m: Int, _ d: Int, hr: Int = 12) -> Date {
        Calendar.current.date(from: DateComponents(year: y, month: m, day: d, hour: hr))!
    }

    private func today() -> Date { Date() }

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
    private func makeCategory(_ name: String, _ ledger: Ledger, type: TransactionType = .expense, parent: 钱伲.Category? = nil) -> 钱伲.Category {
        let c = Category(name: name, type: type, parent: parent, context: context)
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
    private func makeItem(amount: Decimal, period: BudgetPeriod = .monthly, category: 钱伲.Category, book: BudgetBook) -> BudgetItem {
        let i = BudgetItem(amount: amount, period: period, category: category, context: context)
        i.book = book
        try! context.save()
        return i
    }

    @discardableResult
    private func makeTx(
        amount: Decimal,
        date: Date,
        category: 钱伲.Category,
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
    func testPeriodCount_sameCalendarYear_fullYear() {
        let ledger = makeLedger()
        let cat = makeCategory("餐饮", ledger)
        let book = makeBook("2026年度预算", start: date(2026, 1, 1), end: date(2026, 12, 31), ledger)
        let item = makeItem(amount: 12000, period: .yearly, category: cat, book: book)

        // periodCount 应约等于 1.0
        XCTAssertEqual(item.periodCount, 1.0, accuracy: 0.1)
        // totalBudget = periodCount × amount = 1.0 × 12000
        XCTAssertEqual(item.totalBudget, 12000)
    }

    /// 同自然年非整年：2026-03-01 → 2026-11-30（约9个月），月度预算
    func testPeriodCount_sameCalendarYear_partialYear() {
        let ledger = makeLedger()
        let cat = makeCategory("交通", ledger)
        let book = makeBook("春季预算", start: date(2026, 3, 1), end: date(2026, 11, 30), ledger)
        let item = makeItem(amount: 500, period: .monthly, category: cat, book: book)

        // 3月到11月共9个月，periodCount 应接近 9
        XCTAssertEqual(item.periodCount, 9.0, accuracy: 1.0)
        XCTAssertEqual(item.totalBudget, Decimal(item.periodCount) * 500)
    }

    /// 跨自然年整年：2025-07-01 → 2026-06-30，年度预算
    func testPeriodCount_crossYear_fullYear() {
        let ledger = makeLedger()
        let cat = makeCategory("教育", ledger)
        let book = makeBook("学年预算", start: date(2025, 7, 1), end: date(2026, 6, 30), ledger)
        let item = makeItem(amount: 50000, period: .yearly, category: cat, book: book)

        XCTAssertEqual(item.periodCount, 1.0, accuracy: 0.1)
        XCTAssertEqual(item.totalBudget, 50000)
    }

    /// 跨自然年非整年：2025-11-01 → 2026-02-28（约4个月），月度预算
    func testPeriodCount_crossYear_partial() {
        let ledger = makeLedger()
        let cat = makeCategory("取暖", ledger)
        let book = makeBook("冬季预算", start: date(2025, 11, 1), end: date(2026, 2, 28), ledger)
        let item = makeItem(amount: 2000, period: .monthly, category: cat, book: book)

        // 11月到次年2月共约4个月
        XCTAssertEqual(item.periodCount, 4.0, accuracy: 1.0)
        XCTAssertEqual(item.totalBudget, Decimal(item.periodCount) * 2000)
    }

    /// 多年：2025-01-01 → 2027-12-31（3年），年度预算
    func testPeriodCount_multiYear() {
        let ledger = makeLedger()
        let cat = makeCategory("住房", ledger)
        let book = makeBook("三年预算", start: date(2025, 1, 1), end: date(2027, 12, 31), ledger)
        let item = makeItem(amount: 36000, period: .yearly, category: cat, book: book)

        // 约3年
        XCTAssertEqual(item.periodCount, 3.0, accuracy: 0.2)
        XCTAssertEqual(item.totalBudget, Decimal(item.periodCount) * 36000)
    }

    /// 周期归一化：不同周期的预算项在 totalCurrentPeriodBudget 中被归一化到月度
    func testPeriodNormalization_differentPeriods_normalizedToMonthly() {
        let ledger = makeLedger()
        let cat1 = makeCategory("餐饮", ledger)
        let cat2 = makeCategory("交通", ledger)
        let cat3 = makeCategory("购物", ledger)
        let book = makeBook("混合周期", start: date(2026, 1, 1), end: date(2026, 12, 31), ledger)

        makeItem(amount: 12000, period: .yearly, category: cat1, book: book)     // 月均 1000
        makeItem(amount: 3000, period: .quarterly, category: cat2, book: book)    // 月均 1000
        makeItem(amount: 1000, period: .monthly, category: cat3, book: book)      // 月均 1000

        let monthlyBudget = service.totalCurrentPeriodBudget(for: book)
        // 三项月均均 ≈ 1000，合计 ≈ 3000
        XCTAssertEqual(monthlyBudget, 3000, accuracy: 10)
    }

    // MARK: - 2. 分类层级

    // MARK: 2.1 只做一级分类预算

    /// 只给一级分类做预算，子分类的支出应被计入
    func testCategoryHierarchy_onlyParentBudgeted_childSpendingIncluded() {
        let ledger = makeLedger()
        let account = makeAccount("现金", ledger)
        let parentCat = makeCategory("餐饮", ledger)
        let childCat = makeCategory("午餐", ledger, parent: parentCat)
        let book = makeBook("餐饮预算", start: date(2026, 1, 1), end: date(2026, 12, 31), ledger)
        let item = makeItem(amount: 3000, period: .monthly, category: parentCat, book: book)

        // 父分类下的直接支出
        makeTx(amount: -500, date: date(2026, 7, 5), category: parentCat, account: account, ledger: ledger)
        // 子分类支出
        makeTx(amount: -300, date: date(2026, 7, 8), category: childCat, account: account, ledger: ledger)

        let spending = service.cumulativeSpending(for: item, context: context)
        // 应包含父分类和子分类的全部支出
        XCTAssertEqual(spending, 800)
    }

    /// 只给一级分类做预算，不相关的分类支出不应被计入
    func testCategoryHierarchy_onlyParentBudgeted_unrelatedExcluded() {
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
        // 只包含餐饮相关的，交通不应计入
        XCTAssertEqual(spending, 500)
    }

    // MARK: 2.2 只做二级分类预算

    /// 只给二级分类做预算，仅该子分类的支出被计入
    func testCategoryHierarchy_onlyChildBudgeted_onlyChildSpending() {
        let ledger = makeLedger()
        let account = makeAccount("现金", ledger)
        let parentCat = makeCategory("餐饮", ledger)
        let childCat = makeCategory("午餐", ledger, parent: parentCat)
        let siblingCat = makeCategory("晚餐", ledger, parent: parentCat)
        let book = makeBook("午餐预算", start: date(2026, 1, 1), end: date(2026, 12, 31), ledger)
        let item = makeItem(amount: 1000, period: .monthly, category: childCat, book: book)

        // 目标子分类支出
        makeTx(amount: -200, date: date(2026, 7, 5), category: childCat, account: account, ledger: ledger)
        // 兄弟分类支出
        makeTx(amount: -300, date: date(2026, 7, 5), category: siblingCat, account: account, ledger: ledger)
        // 父分类直接支出
        makeTx(amount: -400, date: date(2026, 7, 5), category: parentCat, account: account, ledger: ledger)

        let spending = service.cumulativeSpending(for: item, context: context)
        // 只包含"午餐"分类的支出
        XCTAssertEqual(spending, 200)
    }

    // MARK: 2.3 一级和二级分类都有预算

    /// 父分类和子分类都有预算时，子分类在汇总时被视作子限额，不计入 book-level totalBudget
    func testCategoryHierarchy_bothBudgeted_childExcludedFromTotalBudget() {
        let ledger = makeLedger()
        let parentCat = makeCategory("餐饮", ledger)
        let childCat = makeCategory("午餐", ledger, parent: parentCat)
        let book = makeBook("餐饮详细预算", start: date(2026, 1, 1), end: date(2026, 12, 31), ledger)

        let parentItem = makeItem(amount: 3000, period: .monthly, category: parentCat, book: book)
        let childItem = makeItem(amount: 1000, period: .monthly, category: childCat, book: book)

        // totalBudget 应只计父项（子项是子限额）
        let parentTotal = parentItem.totalBudget
        let expectedTotal = parentTotal  // 不应 = parentTotal + childItem.totalBudget
        XCTAssertEqual(service.totalBudget(for: book), expectedTotal)
        // 明确验证不是简单相加
        XCTAssertNotEqual(service.totalBudget(for: book), parentItem.totalBudget + childItem.totalBudget)
    }

    /// 父分类和子分类都有预算时，父项的 spending 仍包含子分类的全部交易
    func testCategoryHierarchy_bothBudgeted_parentSpendingIncludesChild() {
        let ledger = makeLedger()
        let account = makeAccount("现金", ledger)
        let parentCat = makeCategory("餐饮", ledger)
        let childCat = makeCategory("午餐", ledger, parent: parentCat)
        let book = makeBook("餐饮详细预算", start: date(2026, 1, 1), end: date(2026, 12, 31), ledger)

        let parentItem = makeItem(amount: 3000, period: .monthly, category: parentCat, book: book)
        let childItem = makeItem(amount: 1000, period: .monthly, category: childCat, book: book)

        makeTx(amount: -500, date: date(2026, 7, 5), category: parentCat, account: account, ledger: ledger)
        makeTx(amount: -300, date: date(2026, 7, 6), category: childCat, account: account, ledger: ledger)

        // 父项应包含所有后代分类交易
        XCTAssertEqual(service.cumulativeSpending(for: parentItem, context: context), 800)
        // 子项仅含自身分类交易
        XCTAssertEqual(service.cumulativeSpending(for: childItem, context: context), 300)
    }

    // MARK: - 3. 预算执行准确性（一级包含二级）

    /// categorySpending 将子分类金额向上展开到所有祖先
    func testCategorySpending_ancestorExpansion() {
        let ledger = makeLedger()
        let account = makeAccount("现金", ledger)
        let grandparent = makeCategory("生活", ledger)
        let parent = makeCategory("餐饮", ledger, parent: grandparent)
        let child = makeCategory("午餐", ledger, parent: parent)
        let book = makeBook("生活预算", start: date(2026, 1, 1), end: date(2026, 12, 31), ledger)

        // 只在最底层分类有一笔交易
        makeTx(amount: -100, date: date(2026, 7, 5), category: child, account: account, ledger: ledger)

        let spending = service.categorySpending(in: date(2026, 1, 1)...date(2026, 12, 31), for: book, context: context)

        // 三个层级都应包含这 100
        XCTAssertEqual(spending[child.id], 100)
        XCTAssertEqual(spending[parent.id], 100)
        XCTAssertEqual(spending[grandparent.id], 100)
    }

    /// 一级预算通过 cumulativeSpending 正确汇总所有子分类
    func testBudgetExecution_parentCumulativeSpending_matchesActualTransactions() {
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
        XCTAssertEqual(spending, 5000)  // 800 + 1200 + 3000
    }

    // MARK: - 4. 拆分交易

    /// 拆分父交易被排除，拆分子交易按各自分类参与统计
    func testSplit_parentExcluded_childrenIncluded() {
        let ledger = makeLedger()
        let account = makeAccount("现金", ledger)
        let catA = makeCategory("餐饮", ledger)
        let catB = makeCategory("交通", ledger)
        let book = makeBook("总预算", start: date(2026, 1, 1), end: date(2026, 12, 31), ledger)
        let item = makeItem(amount: 10000, period: .monthly, category: catA, book: book)

        // 拆分父交易（isSplitParent = true）
        let splitParent = makeTx(amount: -500, date: date(2026, 7, 5), category: catA, account: account, ledger: ledger, isSplitParent: true)

        // 拆分子交易 1：归入 catA
        makeTx(amount: -300, date: date(2026, 7, 5), category: catA, account: account, ledger: ledger, parent: splitParent)

        // 拆分子交易 2：归入 catB
        makeTx(amount: -200, date: date(2026, 7, 5), category: catB, account: account, ledger: ledger, parent: splitParent)

        // catA 的预算只计入子交易1（300），不计入父交易（500）也不计入 catB 的子交易（200）
        let spending = service.cumulativeSpending(for: item, context: context)
        XCTAssertEqual(spending, 300)
    }

    /// 拆分子交易按各自分类正确归入不同预算项
    func testSplit_childrenDifferentCategories_countedCorrectly() {
        let ledger = makeLedger()
        let account = makeAccount("现金", ledger)
        let catFood = makeCategory("餐饮", ledger)
        let catTransport = makeCategory("交通", ledger)
        let book = makeBook("总预算", start: date(2026, 1, 1), end: date(2026, 12, 31), ledger)

        let foodItem = makeItem(amount: 3000, period: .monthly, category: catFood, book: book)
        let transportItem = makeItem(amount: 1000, period: .monthly, category: catTransport, book: book)

        let splitParent = makeTx(amount: -800, date: date(2026, 7, 5), category: catFood, account: account, ledger: ledger, isSplitParent: true)

        // 子交易1 → 餐饮
        makeTx(amount: -500, date: date(2026, 7, 5), category: catFood, account: account, ledger: ledger, parent: splitParent)
        // 子交易2 → 交通
        makeTx(amount: -300, date: date(2026, 7, 5), category: catTransport, account: account, ledger: ledger, parent: splitParent)

        XCTAssertEqual(service.cumulativeSpending(for: foodItem, context: context), 500)
        XCTAssertEqual(service.cumulativeSpending(for: transportItem, context: context), 300)
    }

    // MARK: - 5. 退款

    /// 全额退款：支出 100 后退款 100，净支出为 0
    func testRefund_fullRefund_netSpendingZero() {
        let ledger = makeLedger()
        let account = makeAccount("现金", ledger)
        let cat = makeCategory("购物", ledger)
        let book = makeBook("购物预算", start: date(2026, 1, 1), end: date(2026, 12, 31), ledger)
        let item = makeItem(amount: 3000, period: .monthly, category: cat, book: book)

        let original = makeTx(amount: -100, date: date(2026, 7, 5), category: cat, account: account, ledger: ledger)
        makeTx(amount: 100, date: date(2026, 7, 6), category: cat, account: account, ledger: ledger, refundGroupId: original.id)

        let spending = service.cumulativeSpending(for: item, context: context)
        XCTAssertEqual(spending, 0)
    }

    /// 部分退款：支出 100 后退款 40，净支出为 60
    func testRefund_partialRefund_correctNetSpending() {
        let ledger = makeLedger()
        let account = makeAccount("现金", ledger)
        let cat = makeCategory("购物", ledger)
        let book = makeBook("购物预算", start: date(2026, 1, 1), end: date(2026, 12, 31), ledger)
        let item = makeItem(amount: 3000, period: .monthly, category: cat, book: book)

        let original = makeTx(amount: -100, date: date(2026, 7, 5), category: cat, account: account, ledger: ledger)
        makeTx(amount: 40, date: date(2026, 7, 7), category: cat, account: account, ledger: ledger, refundGroupId: original.id)

        let spending = service.cumulativeSpending(for: item, context: context)
        XCTAssertEqual(spending, 60)
    }

    /// 退款金额超过原支出：净支出 capped 为 0，不出现负数
    func testRefund_exceedsOriginal_doesNotGoNegative() {
        let ledger = makeLedger()
        let account = makeAccount("现金", ledger)
        let cat = makeCategory("购物", ledger)
        let book = makeBook("购物预算", start: date(2026, 1, 1), end: date(2026, 12, 31), ledger)
        let item = makeItem(amount: 3000, period: .monthly, category: cat, book: book)

        let original = makeTx(amount: -100, date: date(2026, 7, 5), category: cat, account: account, ledger: ledger)
        makeTx(amount: 150, date: date(2026, 7, 6), category: cat, account: account, ledger: ledger, refundGroupId: original.id)

        let spending = service.cumulativeSpending(for: item, context: context)
        // max(0, abs(-100) + (-abs(150))) = max(0, 100 - 150) = 0
        XCTAssertEqual(spending, 0)
    }

    // MARK: - 6. 报销排除

    /// 待报销支出被排除
    func testReimbursable_pending_excluded() {
        let ledger = makeLedger()
        let account = makeAccount("现金", ledger)
        let cat = makeCategory("差旅", ledger)
        let book = makeBook("差旅预算", start: date(2026, 1, 1), end: date(2026, 12, 31), ledger)
        let item = makeItem(amount: 5000, period: .monthly, category: cat, book: book)

        // 普通支出
        makeTx(amount: -300, date: date(2026, 7, 5), category: cat, account: account, ledger: ledger)
        // 待报销支出
        makeTx(amount: -1000, date: date(2026, 7, 6), category: cat, account: account, ledger: ledger, reimbursement: .pending)

        let spending = service.cumulativeSpending(for: item, context: context)
        // 仅计入普通支出，报销支出被排除
        XCTAssertEqual(spending, 300)
    }

    /// 已批准待报销支出被排除
    func testReimbursable_approved_excluded() {
        let ledger = makeLedger()
        let account = makeAccount("现金", ledger)
        let cat = makeCategory("差旅", ledger)
        let book = makeBook("差旅预算", start: date(2026, 1, 1), end: date(2026, 12, 31), ledger)
        let item = makeItem(amount: 5000, period: .monthly, category: cat, book: book)

        makeTx(amount: -500, date: date(2026, 7, 5), category: cat, account: account, ledger: ledger)
        makeTx(amount: -2000, date: date(2026, 7, 6), category: cat, account: account, ledger: ledger, reimbursement: .approved)

        XCTAssertEqual(service.cumulativeSpending(for: item, context: context), 500)
    }

    /// 已报销支出被排除
    func testReimbursable_reimbursed_excluded() {
        let ledger = makeLedger()
        let account = makeAccount("现金", ledger)
        let cat = makeCategory("差旅", ledger)
        let book = makeBook("差旅预算", start: date(2026, 1, 1), end: date(2026, 12, 31), ledger)
        let item = makeItem(amount: 5000, period: .monthly, category: cat, book: book)

        makeTx(amount: -400, date: date(2026, 7, 5), category: cat, account: account, ledger: ledger)
        makeTx(amount: -1500, date: date(2026, 7, 6), category: cat, account: account, ledger: ledger, reimbursement: .reimbursed)

        XCTAssertEqual(service.cumulativeSpending(for: item, context: context), 400)
    }

    // MARK: - 7. 日期范围排除

    /// 预算书开始日期之前的交易不被计入
    func testDateRange_beforeBookStart_excluded() {
        let ledger = makeLedger()
        let account = makeAccount("现金", ledger)
        let cat = makeCategory("餐饮", ledger)
        let book = makeBook("2026预算", start: date(2026, 3, 1), end: date(2026, 12, 31), ledger)
        let item = makeItem(amount: 3000, period: .monthly, category: cat, book: book)

        // 预算开始前的交易
        makeTx(amount: -500, date: date(2026, 1, 15), category: cat, account: account, ledger: ledger)
        // 预算期内的交易
        makeTx(amount: -800, date: date(2026, 7, 5), category: cat, account: account, ledger: ledger)

        let spending = service.cumulativeSpending(for: item, context: context)
        // 仅计入预算期内的交易
        XCTAssertEqual(spending, 800)
    }

    /// 不在当前周期内的交易不被 currentPeriodSpending 计入
    func testDateRange_outsideCurrentPeriod_excluded() {
        let ledger = makeLedger()
        let account = makeAccount("现金", ledger)
        let cat = makeCategory("餐饮", ledger)
        // 预算书覆盖全年，current period 由当前日期决定
        let book = makeBook("2026预算", start: date(2026, 1, 1), end: date(2026, 12, 31), ledger)
        let item = makeItem(amount: 3000, period: .monthly, category: cat, book: book)

        // 上个月的交易
        let lastMonth = Calendar.current.date(byAdding: .month, value: -1, to: Date())!
        makeTx(amount: -900, date: lastMonth, category: cat, account: account, ledger: ledger)
        // 本月的交易
        makeTx(amount: -400, date: Date(), category: cat, account: account, ledger: ledger)

        let thisMonthSpending = service.currentPeriodSpending(for: item, context: context)
        // currentPeriodSpending 只含本月
        XCTAssertEqual(thisMonthSpending, 400)

        // 但 cumulativeSpending 仍包含全部
        let cumulative = service.cumulativeSpending(for: item, context: context)
        XCTAssertEqual(cumulative, 1300)
    }

    // MARK: - 8. 多币种

    /// 外币交易有 convertedAmount → 预算使用换算后的 CNY 金额
    func testMultiCurrency_withConversion_usesConvertedAmount() {
        let ledger = makeLedger()
        let account = makeAccount("双币卡", ledger)
        let cat = makeCategory("购物", ledger)
        let book = makeBook("购物预算", start: date(2026, 1, 1), end: date(2026, 12, 31), ledger)
        let item = makeItem(amount: 5000, period: .monthly, category: cat, book: book)

        // CNY 交易
        makeTx(amount: -500, date: date(2026, 7, 5), category: cat, account: account, ledger: ledger)
        // USD 交易，已换算为 CNY
        makeTx(amount: -10, date: date(2026, 7, 8), category: cat, account: account, ledger: ledger, currency: "USD", converted: -72)

        let spending = service.cumulativeSpending(for: item, context: context)
        // 500 + 72 = 572
        XCTAssertEqual(spending, 572)
    }

    /// 外币交易无 convertedAmount → 回退使用原始 amount（当作 CNY 处理）
    func testMultiCurrency_withoutConversion_fallsBackToRawAmount() {
        let ledger = makeLedger()
        let account = makeAccount("双币卡", ledger)
        let cat = makeCategory("购物", ledger)
        let book = makeBook("购物预算", start: date(2026, 1, 1), end: date(2026, 12, 31), ledger)
        let item = makeItem(amount: 5000, period: .monthly, category: cat, book: book)

        // USD 交易，无换算
        makeTx(amount: -10, date: date(2026, 7, 5), category: cat, account: account, ledger: ledger, currency: "USD")

        let spending = service.cumulativeSpending(for: item, context: context)
        // 回退使用原始金额 10（当作 CNY）
        XCTAssertEqual(spending, 10)
    }

    /// 同币种交易 → 直接使用 amount（未设 convertedAmount）
    func testMultiCurrency_sameCurrency_usesRawAmount() {
        let ledger = makeLedger()
        let account = makeAccount("人民币卡", ledger)
        let cat = makeCategory("餐饮", ledger)
        let book = makeBook("餐饮预算", start: date(2026, 1, 1), end: date(2026, 12, 31), ledger)
        let item = makeItem(amount: 3000, period: .monthly, category: cat, book: book)

        // 所有交易均为 CNY，未设 convertedAmount
        makeTx(amount: -200, date: date(2026, 7, 5), category: cat, account: account, ledger: ledger)
        makeTx(amount: -350, date: date(2026, 7, 8), category: cat, account: account, ledger: ledger)

        let spending = service.cumulativeSpending(for: item, context: context)
        XCTAssertEqual(spending, 550)
    }

    /// 混合币种：CNY + USD + JPY 同时存在，各按 ledgerAmount 参与汇总
    func testMultiCurrency_mixedCurrencies_correctTotal() {
        let ledger = makeLedger()
        let account = makeAccount("多币卡", ledger)
        let cat = makeCategory("购物", ledger)
        let book = makeBook("购物预算", start: date(2026, 1, 1), end: date(2026, 12, 31), ledger)
        let item = makeItem(amount: 10000, period: .monthly, category: cat, book: book)

        // CNY
        makeTx(amount: -500, date: date(2026, 7, 5), category: cat, account: account, ledger: ledger)
        // USD (rate ~7.2)
        makeTx(amount: -10, date: date(2026, 7, 6), category: cat, account: account, ledger: ledger, currency: "USD", converted: -72)
        // JPY (rate ~0.05)
        makeTx(amount: -1000, date: date(2026, 7, 7), category: cat, account: account, ledger: ledger, currency: "JPY", converted: -50)

        let spending = service.cumulativeSpending(for: item, context: context)
        // 500 + 72 + 50 = 622
        XCTAssertEqual(spending, 622)
    }

    /// 多币种退款：汇率波动导致净支出非零
    func testMultiCurrency_refundWithExchangeRateChange() {
        let ledger = makeLedger()
        let account = makeAccount("双币卡", ledger)
        let cat = makeCategory("购物", ledger)
        let book = makeBook("购物预算", start: date(2026, 1, 1), end: date(2026, 12, 31), ledger)
        let item = makeItem(amount: 5000, period: .monthly, category: cat, book: book)

        // USD 支出 (rate 7.2)
        let original = makeTx(amount: -100, date: date(2026, 7, 5), category: cat, account: account, ledger: ledger, currency: "USD", converted: -720)
        // USD 退款 (rate 变为 7.1)
        makeTx(amount: 100, date: date(2026, 7, 8), category: cat, account: account, ledger: ledger, currency: "USD", converted: 710, refundGroupId: original.id)

        let spending = service.cumulativeSpending(for: item, context: context)
        // 净损失 10 CNY（汇率差）
        XCTAssertEqual(spending, 10)
    }
}
