import XCTest
@preconcurrency import CoreData
@testable import 钱伲

/// TemplateService 单元测试
/// 覆盖：createTemplate / findByName / fetchTemplates / updateTemplate /
///       deleteTemplate / createTransaction(from:)
/// 重点：createTransaction 字段映射
final class TemplateServiceTests: CoreDataTestCase {

    var service: TemplateServiceImpl!

    override func setUp() {
        super.setUp()
        service = TemplateServiceImpl()
    }

    override func tearDown() {
        service = nil
        super.tearDown()
    }

    // MARK: - createTemplate

    /// createTemplate 关联到 ledger 并持久化
    func test_createTemplate_linksToLedger_andPersists() throws {
        let ledger = context.makeLedger()
        let template = TransactionTemplate(
            name: "早班通勤",
            context: context
        )
        template.amount = 25
        template.sortOrder = 3

        try service.createTemplate(template, ledger: ledger, context: context)

        XCTAssertEqual(template.ledger, ledger)
        XCTAssertEqual(template.name, "早班通勤")
        XCTAssertEqual(template.amount, 25)
        XCTAssertEqual(template.sortOrder, 3)
        let request = NSFetchRequest<TransactionTemplate>(entityName: "TransactionTemplate")
        request.predicate = NSPredicate(format: "name == %@", "早班通勤")
        let fetched = try context.fetch(request)
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.ledger, ledger)
    }

    // MARK: - findByName

    /// findByName 存在时返回匹配项
    func test_findByName_existing_returnsMatch() throws {
        let ledger = context.makeLedger()
        let template = makeTransactionTemplate("午餐模板", ledger: ledger)

        let found = try service.findByName("午餐模板", ledger: ledger, context: context)

        XCTAssertNotNil(found)
        XCTAssertEqual(found?.id, template.id)
    }

    /// findByName 不存在时返回 nil
    func test_findByName_missing_returnsNil() throws {
        let ledger = context.makeLedger()
        _ = makeTransactionTemplate("已存在", ledger: ledger)

        let found = try service.findByName("不存在", ledger: ledger, context: context)

        XCTAssertNil(found)
    }

    /// findByName 跨 ledger 隔离
    func test_findByName_isolatesByLedger() throws {
        let ledgerA = context.makeLedger("账本A")
        let ledgerB = context.makeLedger("账本B")
        _ = makeTransactionTemplate("模板A", ledger: ledgerA)

        let foundInB = try service.findByName("模板A", ledger: ledgerB, context: context)

        XCTAssertNil(foundInB, "ledgerB 不应找到 ledgerA 的模板")
    }

    // MARK: - fetchTemplates

    /// fetchTemplates 按 sortOrder 升序，再按 createdAt 升序
    func test_fetchTemplates_sortsBySortOrderThenCreatedAt() throws {
        let ledger = context.makeLedger()
        let t1 = makeTransactionTemplate("T1", ledger: ledger, sortOrder: 0)
        let t2 = makeTransactionTemplate("T2", ledger: ledger, sortOrder: 1)
        let t3 = makeTransactionTemplate("T3", ledger: ledger, sortOrder: 2)
        try context.save()

        let fetched = try service.fetchTemplates(for: ledger, context: context)

        XCTAssertEqual(fetched.map(\.name), ["T1", "T2", "T3"])
    }

    /// fetchTemplates 跨 ledger 隔离
    func test_fetchTemplates_isolatesByLedger() throws {
        let ledgerA = context.makeLedger("账本A")
        let ledgerB = context.makeLedger("账本B")
        makeTransactionTemplate("模板A1", ledger: ledgerA)
        makeTransactionTemplate("模板A2", ledger: ledgerA)
        makeTransactionTemplate("模板B1", ledger: ledgerB)

        let fetchedA = try service.fetchTemplates(for: ledgerA, context: context)
        let fetchedB = try service.fetchTemplates(for: ledgerB, context: context)

        XCTAssertEqual(fetchedA.count, 2)
        XCTAssertEqual(fetchedB.count, 1)
        XCTAssertEqual(fetchedB.first?.name, "模板B1")
    }

    /// fetchTemplates 空 ledger 返回空数组
    func test_fetchTemplates_emptyLedger_returnsEmpty() throws {
        let ledger = context.makeLedger()

        let fetched = try service.fetchTemplates(for: ledger, context: context)

        XCTAssertTrue(fetched.isEmpty)
    }

    // MARK: - updateTemplate

    /// updateTemplate 持久化属性变更
    func test_updateTemplate_persistsChanges() throws {
        let ledger = context.makeLedger()
        let template = makeTransactionTemplate("原名", ledger: ledger)

        template.name = "新名"
        template.amount = 99
        try service.updateTemplate(template, context: context)

        let request = NSFetchRequest<TransactionTemplate>(entityName: "TransactionTemplate")
        request.predicate = NSPredicate(format: "id == %@", template.id as CVarArg)
        let fetched = try context.fetch(request).first
        XCTAssertEqual(fetched?.name, "新名")
        XCTAssertEqual(fetched?.amount, 99)
    }

    // MARK: - deleteTemplate

    /// deleteTemplate 真正从 context 移除
    func test_deleteTemplate_removesFromContext() throws {
        let ledger = context.makeLedger()
        let template = makeTransactionTemplate("待删", ledger: ledger)
        let templateID = template.id  // 提取到本地，避免删除后访问已删除对象的 fault

        try service.deleteTemplate(template, context: context)

        let request = NSFetchRequest<TransactionTemplate>(entityName: "TransactionTemplate")
        request.predicate = NSPredicate(format: "id == %@", templateID as CVarArg)
        let fetched = try context.fetch(request)
        XCTAssertTrue(fetched.isEmpty)
    }

    // MARK: - createTransaction(from:date:)

    /// createTransaction 从模板创建交易：字段全映射 + template 反向关联 + ledger 关联
    func test_createTransactionFromTemplate_mapsAllFields() throws {
        let ledger = context.makeLedger()
        let account = context.makeAccount("工资卡", ledger: ledger)
        let category = context.makeCategory("餐饮", ledger: ledger, type: .expense)
        let member = context.makeMember("张三", ledger: ledger)
        let merchant = context.makeMerchant("麦当劳", ledger: ledger)
        let project = context.makeProject("午餐项目", ledger: ledger)

        let template = TransactionTemplate(
            name: "午餐模板",
            type: .expense,
            amount: 35,
            currencyCode: "CNY",
            note: "工作日午餐",
            tags: ["日常", "工作日"],
            sortOrder: 5,
            account: account,
            category: category,
            member: member,
            merchant: merchant,
            project: project,
            context: context
        )
        try service.createTemplate(template, ledger: ledger, context: context)

        let customDate = Date(timeIntervalSince1970: 1700000000)
        let transaction = try service.createTransaction(from: template, date: customDate, context: context)

        // 字段映射
        XCTAssertEqual(transaction.type, .expense)
        XCTAssertEqual(transaction.amount, 35)
        XCTAssertEqual(transaction.currencyCode, "CNY")
        XCTAssertEqual(transaction.note, "工作日午餐")
        XCTAssertEqual(transaction.tags, ["日常", "工作日"])
        XCTAssertEqual(transaction.account, account)
        XCTAssertEqual(transaction.category, category)
        XCTAssertEqual(transaction.member, member)
        XCTAssertEqual(transaction.merchant, merchant)
        XCTAssertEqual(transaction.project, project)
        XCTAssertEqual(transaction.date, customDate)

        // 模板反向关联
        XCTAssertEqual(transaction.template, template)

        // ledger 关联
        XCTAssertEqual(transaction.ledger, ledger)
    }

    /// createTransaction 转账模板：toAccount 也被映射
    func test_createTransactionFromTemplate_mapsToAccount() throws {
        let ledger = context.makeLedger()
        let fromAccount = context.makeAccount("现金", ledger: ledger)
        let toAccount = context.makeAccount("银行卡", ledger: ledger)

        let template = TransactionTemplate(
            name: "现金→银行卡",
            type: .transfer,
            amount: 1000,
            account: fromAccount,
            toAccount: toAccount,
            context: context
        )
        try service.createTemplate(template, ledger: ledger, context: context)

        let transaction = try service.createTransaction(from: template, date: Date(), context: context)

        XCTAssertEqual(transaction.type, .transfer)
        XCTAssertEqual(transaction.account, fromAccount)
        XCTAssertEqual(transaction.toAccount, toAccount)
    }

    // MARK: - Helpers

    /// TestFixtures 没有 makeTransactionTemplate，用这个内联 helper
    @discardableResult
    private func makeTransactionTemplate(
        _ name: String,
        ledger: Ledger,
        sortOrder: Int = 0
    ) -> TransactionTemplate {
        let t = TransactionTemplate(
            name: name,
            sortOrder: sortOrder,
            context: context
        )
        t.ledger = ledger
        try? context.save()
        return t
    }
}