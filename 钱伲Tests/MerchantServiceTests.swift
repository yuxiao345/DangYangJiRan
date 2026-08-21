import XCTest
@preconcurrency import CoreData
@testable import 钱伲

/// MerchantService 单元测试
/// 覆盖：createMerchant / findByName / fetchMerchants / updateMerchant / deleteMerchant
final class MerchantServiceTests: CoreDataTestCase {

    var service: MerchantServiceImpl!

    override func setUp() {
        super.setUp()
        service = MerchantServiceImpl()
    }

    override func tearDown() {
        service = nil
        super.tearDown()
    }

    // MARK: - createMerchant

    /// createMerchant 关联到 ledger 并持久化
    func test_createMerchant_linksToLedger_andPersists() throws {
        let ledger = context.makeLedger()
        let merchant = Merchant(name: "星巴克", context: context)
        merchant.sortOrder = 7

        try service.createMerchant(merchant, ledger: ledger, context: context)

        XCTAssertEqual(merchant.ledger, ledger)
        XCTAssertEqual(merchant.name, "星巴克")
        XCTAssertEqual(merchant.sortOrder, 7)
        let request = NSFetchRequest<Merchant>(entityName: "Merchant")
        request.predicate = NSPredicate(format: "name == %@", "星巴克")
        let fetched = try context.fetch(request)
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.ledger, ledger)
    }

    // MARK: - findByName

    /// findByName 存在时返回匹配项
    func test_findByName_existing_returnsMatch() throws {
        let ledger = context.makeLedger()
        let m = context.makeMerchant("麦当劳", ledger: ledger)

        let found = try service.findByName("麦当劳", ledger: ledger, context: context)

        XCTAssertNotNil(found)
        XCTAssertEqual(found?.id, m.id)
    }

    /// findByName 不存在时返回 nil
    func test_findByName_missing_returnsNil() throws {
        let ledger = context.makeLedger()
        _ = context.makeMerchant("肯德基", ledger: ledger)

        let found = try service.findByName("必胜客", ledger: ledger, context: context)

        XCTAssertNil(found)
    }

    /// findByName 大小写严格匹配（== 不区分大小写）
    func test_findByName_caseInsensitiveStrictMatch() throws {
        let ledger = context.makeLedger()
        _ = context.makeMerchant("Starbucks", ledger: ledger)

        // NSPredicate == 默认不区分大小写
        let found = try service.findByName("starbucks", ledger: ledger, context: context)

        // 当前实现用 == 严格匹配，大写版本找不到
        XCTAssertNil(found)
    }

    /// findByName 跨 ledger 隔离
    func test_findByName_isolatesByLedger() throws {
        let ledgerA = context.makeLedger("账本A")
        let ledgerB = context.makeLedger("账本B")
        _ = context.makeMerchant("沃尔玛", ledger: ledgerA)

        let foundInB = try service.findByName("沃尔玛", ledger: ledgerB, context: context)

        XCTAssertNil(foundInB, "ledgerB 不应找到 ledgerA 的商户")
    }

    // MARK: - fetchMerchants

    /// fetchMerchants 按 sortOrder 升序，再按 name 升序
    func test_fetchMerchants_sortsBySortOrderThenName() throws {
        let ledger = context.makeLedger()
        let a = context.makeMerchant("A商户", ledger: ledger)
        a.sortOrder = 0
        let b = context.makeMerchant("B商户", ledger: ledger)
        b.sortOrder = 1
        let c = context.makeMerchant("C商户", ledger: ledger)
        c.sortOrder = 2
        try context.save()

        let fetched = try service.fetchMerchants(for: ledger, context: context)

        XCTAssertEqual(fetched.map(\.name), ["A商户", "B商户", "C商户"])
    }

    /// fetchMerchants 同 sortOrder 时按 name 升序
    func test_fetchMerchants_sameSortOrder_sortsByName() throws {
        let ledger = context.makeLedger()
        let c = context.makeMerchant("Charlie", ledger: ledger)
        c.sortOrder = 0
        let a = context.makeMerchant("Alpha", ledger: ledger)
        a.sortOrder = 0
        let b = context.makeMerchant("Bravo", ledger: ledger)
        b.sortOrder = 0
        try context.save()

        let fetched = try service.fetchMerchants(for: ledger, context: context)

        XCTAssertEqual(fetched.map(\.name), ["Alpha", "Bravo", "Charlie"])
    }

    /// fetchMerchants 跨 ledger 隔离
    func test_fetchMerchants_isolatesByLedger() throws {
        let ledgerA = context.makeLedger("账本A")
        let ledgerB = context.makeLedger("账本B")
        context.makeMerchant("商户A1", ledger: ledgerA)
        context.makeMerchant("商户A2", ledger: ledgerA)
        context.makeMerchant("商户B1", ledger: ledgerB)

        let fetchedA = try service.fetchMerchants(for: ledgerA, context: context)
        let fetchedB = try service.fetchMerchants(for: ledgerB, context: context)

        XCTAssertEqual(fetchedA.count, 2)
        XCTAssertEqual(fetchedA.map(\.name).sorted(), ["商户A1", "商户A2"])
        XCTAssertEqual(fetchedB.count, 1)
        XCTAssertEqual(fetchedB.first?.name, "商户B1")
    }

    /// fetchMerchants 空 ledger 返回空数组
    func test_fetchMerchants_emptyLedger_returnsEmpty() throws {
        let ledger = context.makeLedger()

        let fetched = try service.fetchMerchants(for: ledger, context: context)

        XCTAssertTrue(fetched.isEmpty)
    }

    // MARK: - updateMerchant

    /// updateMerchant 持久化属性变更
    func test_updateMerchant_persistsChanges() throws {
        let ledger = context.makeLedger()
        let merchant = context.makeMerchant("原名", ledger: ledger)

        merchant.name = "新名"
        merchant.sortOrder = 10
        try service.updateMerchant(merchant, context: context)

        let request = NSFetchRequest<Merchant>(entityName: "Merchant")
        request.predicate = NSPredicate(format: "id == %@", merchant.id as CVarArg)
        let fetched = try context.fetch(request).first
        XCTAssertEqual(fetched?.name, "新名")
        XCTAssertEqual(fetched?.sortOrder, 10)
    }

    // MARK: - deleteMerchant

    /// deleteMerchant 真正从 context 移除
    func test_deleteMerchant_removesFromContext() throws {
        let ledger = context.makeLedger()
        let merchant = context.makeMerchant("待删", ledger: ledger)
        let merchantID = merchant.id  // 提取到本地，避免删除后访问已删除对象的 fault

        try service.deleteMerchant(merchant, context: context)

        let request = NSFetchRequest<Merchant>(entityName: "Merchant")
        request.predicate = NSPredicate(format: "id == %@", merchantID as CVarArg)
        let fetched = try context.fetch(request)
        XCTAssertTrue(fetched.isEmpty)
    }
}