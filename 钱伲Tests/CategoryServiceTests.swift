import XCTest
@preconcurrency import CoreData
@testable import 钱伲

/// CategoryService 单元测试
/// 覆盖：createCategory / findByName / fetchCategories / fetchAllCategories /
///       updateCategory / deleteCategory / seedDefaults
/// 重点：层级排序（parent → children）和 orphan 处理
final class CategoryServiceTests: CoreDataTestCase {

    var service: CategoryServiceImpl!

    override func setUp() {
        super.setUp()
        service = CategoryServiceImpl()
    }

    override func tearDown() {
        service = nil
        super.tearDown()
    }

    // MARK: - createCategory

    /// createCategory 关联到 ledger 并持久化
    func test_createCategory_linksToLedger_andPersists() throws {
        let ledger = context.makeLedger()
        let category = 钱伲.Category(name: "餐饮", context: context)
        category.typeRaw = TransactionType.expense.rawValue

        try service.createCategory(category, ledger: ledger, context: context)

        XCTAssertEqual(category.ledger, ledger)
        XCTAssertEqual(category.name, "餐饮")
        let request = NSFetchRequest<钱伲.Category>(entityName: "Category")
        request.predicate = NSPredicate(format: "name == %@", "餐饮")
        let fetched = try context.fetch(request)
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.ledger, ledger)
    }

    // MARK: - findByName

    /// findByName 存在时返回匹配项
    func test_findByName_existing_returnsMatch() throws {
        let ledger = context.makeLedger()
        let c = context.makeCategory("餐饮", ledger: ledger)

        let found = try service.findByName("餐饮", ledger: ledger, context: context)

        XCTAssertNotNil(found)
        XCTAssertEqual(found?.id, c.id)
    }

    /// findByName 不存在时返回 nil
    func test_findByName_missing_returnsNil() throws {
        let ledger = context.makeLedger()
        _ = context.makeCategory("餐饮", ledger: ledger)

        let found = try service.findByName("不存在", ledger: ledger, context: context)

        XCTAssertNil(found)
    }

    /// findByName 跨 ledger 隔离
    func test_findByName_isolatesByLedger() throws {
        let ledgerA = context.makeLedger("账本A")
        let ledgerB = context.makeLedger("账本B")
        _ = context.makeCategory("餐饮", ledger: ledgerA)

        let found = try service.findByName("餐饮", ledger: ledgerB, context: context)

        XCTAssertNil(found, "ledgerB 不应找到 ledgerA 的分类")
    }

    // MARK: - fetchCategories / fetchAllCategories (过滤)

    /// fetchCategories 过滤掉 isHidden=true 的分类
    func test_fetchCategories_filtersHidden() throws {
        let ledger = context.makeLedger()
        let visible = context.makeCategory("餐饮", ledger: ledger)
        visible.isHidden = false
        let hidden = context.makeCategory("隐藏分类", ledger: ledger)
        hidden.isHidden = true
        try context.save()

        let visible_ = try service.fetchCategories(for: ledger, context: context)

        XCTAssertEqual(visible_.map(\.name), ["餐饮"])
    }

    /// fetchAllCategories 包含 isHidden=true 的分类
    func test_fetchAllCategories_includesHidden() throws {
        let ledger = context.makeLedger()
        let visible = context.makeCategory("餐饮", ledger: ledger)
        visible.isHidden = false
        let hidden = context.makeCategory("隐藏分类", ledger: ledger)
        hidden.isHidden = true
        try context.save()

        let all = try service.fetchAllCategories(for: ledger, context: context)

        XCTAssertEqual(all.count, 2)
        XCTAssertTrue(all.contains(where: { $0.name == "餐饮" }))
        XCTAssertTrue(all.contains(where: { $0.name == "隐藏分类" }))
    }

    /// fetchCategories 按 type=expense 过滤
    func test_fetchCategories_filtersByType() throws {
        let ledger = context.makeLedger()
        let expense = context.makeCategory("餐饮", ledger: ledger, type: .expense)
        let income = context.makeCategory("工资", ledger: ledger, type: .income)
        try context.save()

        let expenses = try service.fetchCategories(for: ledger, type: .expense, context: context)
        let incomes = try service.fetchCategories(for: ledger, type: .income, context: context)

        XCTAssertEqual(expenses.map(\.name), ["餐饮"])
        XCTAssertEqual(incomes.map(\.name), ["工资"])
    }

    /// fetchAllCategories type=nil 返回全部类型
    func test_fetchAllCategories_typeNil_returnsAll() throws {
        let ledger = context.makeLedger()
        context.makeCategory("餐饮", ledger: ledger, type: .expense)
        context.makeCategory("工资", ledger: ledger, type: .income)
        try context.save()

        let all = try service.fetchAllCategories(for: ledger, type: nil, context: context)

        XCTAssertEqual(all.count, 2)
    }

    // MARK: - 层级排序

    /// 层级排序：parent 在前、children 按 sortOrder 接在 parent 后
    func test_fetchAllCategories_hierarchicalOrder_parentBeforeChildren() throws {
        let ledger = context.makeLedger()
        let root1 = context.makeCategory("根1", ledger: ledger)
        root1.sortOrder = 0
        let root2 = context.makeCategory("根2", ledger: ledger)
        root2.sortOrder = 1
        let child1a = context.makeCategory("子1A", ledger: ledger, parent: root1)
        child1a.sortOrder = 0
        let child1b = context.makeCategory("子1B", ledger: ledger, parent: root1)
        child1b.sortOrder = 1
        let child2a = context.makeCategory("子2A", ledger: ledger, parent: root2)
        child2a.sortOrder = 0
        try context.save()

        let result = try service.fetchAllCategories(for: ledger, context: context)

        // 期望：根1, 子1A, 子1B, 根2, 子2A
        XCTAssertEqual(result.map(\.name), ["根1", "子1A", "子1B", "根2", "子2A"])
    }

    /// 同 sortOrder 的根分类：先按 sortOrder，再按插入顺序（实际实现是稳定排序）
    func test_fetchAllCategories_sameRootSortOrder() throws {
        let ledger = context.makeLedger()
        let a = context.makeCategory("A", ledger: ledger)
        a.sortOrder = 0
        let b = context.makeCategory("B", ledger: ledger)
        b.sortOrder = 0
        let c = context.makeCategory("C", ledger: ledger)
        c.sortOrder = 0
        try context.save()

        let result = try service.fetchAllCategories(for: ledger, context: context)

        // 同 sortOrder 时依赖 sort descriptor（自身 sortOrder 相同时顺序不保证稳定），
        // 但至少应包含全部 3 个
        XCTAssertEqual(result.count, 3)
        XCTAssertTrue(result.map(\.name).contains("A"))
        XCTAssertTrue(result.map(\.name).contains("B"))
        XCTAssertTrue(result.map(\.name).contains("C"))
    }

    /// Orphan 处理：parent 被 type 过滤后，子被追加到末尾
    func test_fetchAllCategories_orphansAppendedAtEnd() throws {
        let ledger = context.makeLedger()
        // 父分类是 income，但请求 type=expense 时父被过滤
        let parent = context.makeCategory("父类", ledger: ledger, type: .income)
        parent.sortOrder = 0
        let child = context.makeCategory("子类", ledger: ledger, type: .expense, parent: parent)
        child.sortOrder = 0
        // 另一个 expense 父类（保留）
        let visibleRoot = context.makeCategory("可见根", ledger: ledger, type: .expense)
        visibleRoot.sortOrder = 0
        try context.save()

        let result = try service.fetchAllCategories(for: ledger, type: .expense, context: context)

        // 期望：可见根, 子类（orphan 在末尾）
        XCTAssertEqual(result.map(\.name), ["可见根", "子类"])
    }

    /// fetchCategories 也处理 orphan（隐藏 parent 时子被 orphan）
    func test_fetchCategories_hiddenParentOrphans() throws {
        let ledger = context.makeLedger()
        let parent = context.makeCategory("父类", ledger: ledger)
        parent.isHidden = true
        parent.sortOrder = 0
        let child = context.makeCategory("子类", ledger: ledger, parent: parent)
        child.isHidden = false
        child.sortOrder = 0
        try context.save()

        // fetchCategories 过滤 hidden，但内部走的是 fetchAllCategories 然后过滤
        // orphan 的子分类本身不是 hidden，应保留
        let visible = try service.fetchCategories(for: ledger, context: context)

        XCTAssertEqual(visible.map(\.name), ["子类"])
    }

    // MARK: - updateCategory

    /// updateCategory 持久化属性变更
    func test_updateCategory_persistsChanges() throws {
        let ledger = context.makeLedger()
        let category = context.makeCategory("原名", ledger: ledger)

        category.name = "新名"
        category.isHidden = true
        try service.updateCategory(category, context: context)

        let request = NSFetchRequest<钱伲.Category>(entityName: "Category")
        request.predicate = NSPredicate(format: "id == %@", category.id as CVarArg)
        let fetched = try context.fetch(request).first
        XCTAssertEqual(fetched?.name, "新名")
        XCTAssertEqual(fetched?.isHidden, true)
    }

    // MARK: - deleteCategory

    /// deleteCategory 真正从 context 移除
    func test_deleteCategory_removesFromContext() throws {
        let ledger = context.makeLedger()
        let category = context.makeCategory("待删", ledger: ledger)
        let categoryID = category.id  // 提取到本地，避免删除后访问已删除对象的 fault

        try service.deleteCategory(category, context: context)

        let request = NSFetchRequest<钱伲.Category>(entityName: "Category")
        request.predicate = NSPredicate(format: "id == %@", categoryID as CVarArg)
        let fetched = try context.fetch(request)
        XCTAssertTrue(fetched.isEmpty)
    }

    // MARK: - seedDefaults

    /// seedDefaults 创建所有默认分类（expense + income）
    func test_seedDefaults_createsAllDefaultCategories() {
        let ledger = context.makeLedger()

        service.seedDefaults(ledger: ledger, context: context)

        let all = try? service.fetchAllCategories(for: ledger, context: context)
        // 当前 CategorySeeder 共 20 个根分类（13 expense + 7 income）
        XCTAssertNotNil(all)
        let rootCount = all?.filter { $0.parent == nil }.count
        XCTAssertEqual(rootCount, 20, "应有 20 个根分类（13 expense + 7 income）")

        // 验证至少有一个 expense 和一个 income
        let hasExpense = all?.contains(where: { $0.type == .expense })
        let hasIncome = all?.contains(where: { $0.type == .income })
        XCTAssertTrue(hasExpense == true)
        XCTAssertTrue(hasIncome == true)
    }

    /// seedDefaults 创建的分类有子分类
    func test_seedDefaults_createsSubcategories() {
        let ledger = context.makeLedger()

        service.seedDefaults(ledger: ledger, context: context)

        let all = try? service.fetchAllCategories(for: ledger, context: context)
        let children = all?.filter { $0.parent != nil }
        XCTAssertGreaterThan(children?.count ?? 0, 0, "应至少有一个子分类")
    }
}