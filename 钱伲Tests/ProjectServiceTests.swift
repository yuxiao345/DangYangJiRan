import XCTest
@preconcurrency import CoreData
@testable import 钱伲

/// ProjectService 单元测试
/// 覆盖：createProject / fetchProjects / updateProject / deleteProject
final class ProjectServiceTests: CoreDataTestCase {

    var service: ProjectServiceImpl!

    override func setUp() {
        super.setUp()
        service = ProjectServiceImpl()
    }

    override func tearDown() {
        service = nil
        super.tearDown()
    }

    // MARK: - createProject

    /// createProject 关联到 ledger 并持久化
    func test_createProject_linksToLedger_andPersists() throws {
        let ledger = context.makeLedger()
        let project = Project(name: "装修", context: context)
        project.sortOrder = 3

        try service.createProject(project, ledger: ledger, context: context)

        XCTAssertEqual(project.ledger, ledger)
        XCTAssertEqual(project.name, "装修")
        XCTAssertEqual(project.sortOrder, 3)
        let request = NSFetchRequest<Project>(entityName: "Project")
        request.predicate = NSPredicate(format: "name == %@", "装修")
        let fetched = try context.fetch(request)
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.ledger, ledger)
    }

    // MARK: - fetchProjects

    /// fetchProjects 按 sortOrder 升序，再按 name 升序
    func test_fetchProjects_sortsBySortOrderThenName() throws {
        let ledger = context.makeLedger()
        let a = context.makeProject("A项目", ledger: ledger)
        a.sortOrder = 0
        let b = context.makeProject("B项目", ledger: ledger)
        b.sortOrder = 1
        let c = context.makeProject("C项目", ledger: ledger)
        c.sortOrder = 2
        try context.save()

        let fetched = try service.fetchProjects(for: ledger, context: context)

        XCTAssertEqual(fetched.map(\.name), ["A项目", "B项目", "C项目"])
    }

    /// fetchProjects 同 sortOrder 时按 name 升序
    func test_fetchProjects_sameSortOrder_sortsByName() throws {
        let ledger = context.makeLedger()
        let c = context.makeProject("Charlie", ledger: ledger)
        c.sortOrder = 0
        let a = context.makeProject("Alpha", ledger: ledger)
        a.sortOrder = 0
        let b = context.makeProject("Bravo", ledger: ledger)
        b.sortOrder = 0
        try context.save()

        let fetched = try service.fetchProjects(for: ledger, context: context)

        XCTAssertEqual(fetched.map(\.name), ["Alpha", "Bravo", "Charlie"])
    }

    /// fetchProjects 跨 ledger 隔离
    func test_fetchProjects_isolatesByLedger() throws {
        let ledgerA = context.makeLedger("账本A")
        let ledgerB = context.makeLedger("账本B")
        context.makeProject("项目A1", ledger: ledgerA)
        context.makeProject("项目A2", ledger: ledgerA)
        context.makeProject("项目B1", ledger: ledgerB)

        let fetchedA = try service.fetchProjects(for: ledgerA, context: context)
        let fetchedB = try service.fetchProjects(for: ledgerB, context: context)

        XCTAssertEqual(fetchedA.count, 2)
        XCTAssertEqual(fetchedA.map(\.name).sorted(), ["项目A1", "项目A2"])
        XCTAssertEqual(fetchedB.count, 1)
        XCTAssertEqual(fetchedB.first?.name, "项目B1")
    }

    /// fetchProjects 空 ledger 返回空数组
    func test_fetchProjects_emptyLedger_returnsEmpty() throws {
        let ledger = context.makeLedger()

        let fetched = try service.fetchProjects(for: ledger, context: context)

        XCTAssertTrue(fetched.isEmpty)
    }

    // MARK: - updateProject

    /// updateProject 持久化属性变更
    func test_updateProject_persistsChanges() throws {
        let ledger = context.makeLedger()
        let project = context.makeProject("原名", ledger: ledger)

        project.name = "新名"
        project.sortOrder = 10
        try service.updateProject(project, context: context)

        let request = NSFetchRequest<Project>(entityName: "Project")
        request.predicate = NSPredicate(format: "id == %@", project.id as CVarArg)
        let fetched = try context.fetch(request).first
        XCTAssertEqual(fetched?.name, "新名")
        XCTAssertEqual(fetched?.sortOrder, 10)
    }

    // MARK: - deleteProject

    /// deleteProject 真正从 context 移除
    func test_deleteProject_removesFromContext() throws {
        let ledger = context.makeLedger()
        let project = context.makeProject("待删", ledger: ledger)
        let projectID = project.id  // 提取到本地，避免删除后访问已删除对象的 fault

        try service.deleteProject(project, context: context)

        let request = NSFetchRequest<Project>(entityName: "Project")
        request.predicate = NSPredicate(format: "id == %@", projectID as CVarArg)
        let fetched = try context.fetch(request)
        XCTAssertTrue(fetched.isEmpty)
    }
}