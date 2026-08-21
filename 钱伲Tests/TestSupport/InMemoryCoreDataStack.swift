import XCTest
@preconcurrency import CoreData
@testable import 钱伲

/// 共享内存 CoreData 栈，用于单元测试。
/// 每次创建都是独立的内存 store，互不干扰。
///
/// 使用 NSPersistentContainer（Apple 推荐）替代手动 coordinator 装配，
/// 内部统一管理 NSManagedObjectModel，避免 NSEntityDescription 重影警告。
enum InMemoryCoreDataStack {

    /// 单例 NSPersistentContainer，所有测试复用同一 model 避免重影
    private static let sharedContainer: NSPersistentContainer = {
        let container = NSPersistentContainer(name: "FirstCC")
        container.loadPersistentStores { _, error in
            if let error = error {
                fatalError("Failed to load in-memory store: \(error)")
            }
        }
        return container
    }()

    /// 创建一个 in-memory NSManagedObjectContext。
    /// 数据隔离：每次测试创建独立的 in-memory store，sharedContainer 仅复用 model。
    static func makeContext() -> NSManagedObjectContext {
        let ctx = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        ctx.persistentStoreCoordinator = sharedContainer.persistentStoreCoordinator
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