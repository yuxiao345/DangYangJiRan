import XCTest
@preconcurrency import CoreData
@testable import 钱伲

/// 共享内存 CoreData 栈，用于单元测试。
/// 每次创建都是独立的内存 store，互不干扰。
///
/// model 复用 `CoreDataModel.shared`（原理见那里）。这里绝不能自建 model 或 `model.copy()`：
/// 测试进程里宿主 app 会真启动并建自己的栈，多出来的那一份会让 `+entity` 解析失败——
/// 实测完整套件跑时 `Failed to find a unique match` 出现 554 次，`CategoryServiceTests`
/// 稳定崩在 `TestFixtures.swift:12`。
///
/// 不要改用 NSPersistentContainer —— 它会默认添加磁盘 SQLite store，导致测试间数据泄漏。
enum InMemoryCoreDataStack {

    /// 创建一个 in-memory NSManagedObjectContext。
    /// 数据隔离：每次新建独立 coordinator + 独立 in-memory store。
    static func makeContext() -> NSManagedObjectContext {
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: CoreDataModel.shared)
        do {
            try coordinator.addPersistentStore(
                ofType: NSInMemoryStoreType,
                configurationName: nil,
                at: nil
            )
        } catch {
            fatalError("Failed to add in-memory store: \(error)")
        }
        let ctx = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        ctx.persistentStoreCoordinator = coordinator
        return ctx
    }
}

/// 共享测试基类。setUp/tearDown 自动创建和清理 in-memory context。
/// 子类可在 setUp() 里 override 创建 service，或在实例属性里直接 init。
class CoreDataTestCase: XCTestCase {
    var context: NSManagedObjectContext!

    override func setUp() {
        super.setUp()
        context = InMemoryCoreDataStack.makeContext()
    }

    override func tearDown() {
        context = nil
        super.tearDown()
    }
}