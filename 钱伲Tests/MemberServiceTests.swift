import XCTest
@preconcurrency import CoreData
@testable import 钱伲

/// MemberService 单元测试
/// 覆盖：createMember / fetchMembers / updateMember / deleteMember
final class MemberServiceTests: CoreDataTestCase {

    var service: MemberServiceImpl!

    override func setUp() {
        super.setUp()
        service = MemberServiceImpl()
    }

    override func tearDown() {
        service = nil
        super.tearDown()
    }

    // MARK: - createMember

    /// createMember 关联到 ledger 并持久化
    func test_createMember_linksToLedger_andPersists() throws {
        let ledger = context.makeLedger()
        let member = Member(name: "张三", context: context)
        member.sortOrder = 5

        try service.createMember(member, ledger: ledger, context: context)

        XCTAssertEqual(member.ledger, ledger)
        XCTAssertEqual(member.name, "张三")
        XCTAssertEqual(member.sortOrder, 5)
        // save 之后应能从 context 重新 fetch
        let request = NSFetchRequest<Member>(entityName: "Member")
        request.predicate = NSPredicate(format: "name == %@", "张三")
        let fetched = try context.fetch(request)
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.ledger, ledger)
    }

    // MARK: - fetchMembers

    /// fetchMembers 按 sortOrder 升序，再按 name 升序
    func test_fetchMembers_sortsBySortOrderThenName() throws {
        let ledger = context.makeLedger()
        let a = context.makeMember("阿尔法", ledger: ledger)
        a.sortOrder = 0
        let b = context.makeMember("贝塔", ledger: ledger)
        b.sortOrder = 1
        let c = context.makeMember("伽马", ledger: ledger)
        c.sortOrder = 2
        try context.save()

        let fetched = try service.fetchMembers(for: ledger, context: context)

        XCTAssertEqual(fetched.map(\.name), ["阿尔法", "贝塔", "伽马"])
    }

    /// fetchMembers 同 sortOrder 时按 name 升序
    func test_fetchMembers_sameSortOrder_sortsByName() throws {
        let ledger = context.makeLedger()
        let c = context.makeMember("Charlie", ledger: ledger)
        c.sortOrder = 0
        let a = context.makeMember("Alpha", ledger: ledger)
        a.sortOrder = 0
        let b = context.makeMember("Bravo", ledger: ledger)
        b.sortOrder = 0
        try context.save()

        let fetched = try service.fetchMembers(for: ledger, context: context)

        XCTAssertEqual(fetched.map(\.name), ["Alpha", "Bravo", "Charlie"])
    }

    /// fetchMembers 跨 ledger 隔离
    func test_fetchMembers_isolatesByLedger() throws {
        let ledgerA = context.makeLedger("账本A")
        let ledgerB = context.makeLedger("账本B")
        context.makeMember("成员A1", ledger: ledgerA)
        context.makeMember("成员A2", ledger: ledgerA)
        context.makeMember("成员B1", ledger: ledgerB)

        let fetchedA = try service.fetchMembers(for: ledgerA, context: context)
        let fetchedB = try service.fetchMembers(for: ledgerB, context: context)

        XCTAssertEqual(fetchedA.count, 2)
        XCTAssertEqual(fetchedA.map(\.name).sorted(), ["成员A1", "成员A2"])
        XCTAssertEqual(fetchedB.count, 1)
        XCTAssertEqual(fetchedB.first?.name, "成员B1")
    }

    /// fetchMembers 空 ledger 返回空数组
    func test_fetchMembers_emptyLedger_returnsEmpty() throws {
        let ledger = context.makeLedger()

        let fetched = try service.fetchMembers(for: ledger, context: context)

        XCTAssertTrue(fetched.isEmpty)
    }

    // MARK: - updateMember

    /// updateMember 持久化属性变更
    func test_updateMember_persistsChanges() throws {
        let ledger = context.makeLedger()
        let member = context.makeMember("原名", ledger: ledger)

        member.name = "新名"
        member.sortOrder = 10
        try service.updateMember(member, context: context)

        // 用新 context 验证持久化效果（重 fetch）
        let request = NSFetchRequest<Member>(entityName: "Member")
        request.predicate = NSPredicate(format: "id == %@", member.id as CVarArg)
        let fetched = try context.fetch(request).first
        XCTAssertEqual(fetched?.name, "新名")
        XCTAssertEqual(fetched?.sortOrder, 10)
    }

    // MARK: - deleteMember

    /// deleteMember 真正从 context 移除
    func test_deleteMember_removesFromContext() throws {
        let ledger = context.makeLedger()
        let member = context.makeMember("待删", ledger: ledger)
        let memberID = member.id  // 提取到本地，避免删除后访问已删除对象的 fault

        try service.deleteMember(member, context: context)

        let request = NSFetchRequest<Member>(entityName: "Member")
        request.predicate = NSPredicate(format: "id == %@", memberID as CVarArg)
        let fetched = try context.fetch(request)
        XCTAssertTrue(fetched.isEmpty)
    }
}