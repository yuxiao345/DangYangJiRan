import XCTest
@preconcurrency import CoreData
@testable import 钱伲

/// 共享内存 CoreData 栈，用于单元测试。
/// 每次创建都是独立的内存 store，互不干扰。
///
/// 注意：NSManagedObjectModel 必须单例化，否则多次 `NSManagedObjectModel(contentsOf:)`
/// 会创建多个 model 实例，触发 'Multiple NSEntityDescriptions claim' 警告，
/// 在 fault 访问时偶发 crash（SplitServiceTests/LedgerServiceTests 已知受此影响）。
///
/// 不要改用 NSPersistentContainer —— 它会默认添加磁盘 SQLite store，导致测试间数据泄漏。
enum InMemoryCoreDataStack {

    /// 单例 model，所有测试 context 共享同一个 NSManagedObjectModel 实例
    private static let sharedModel: NSManagedObjectModel = {
        guard let modelURL = Bundle(for: Account.self).url(forResource: "FirstCC", withExtension: "momd"),
              let model = NSManagedObjectModel(contentsOf: modelURL) else {
            fatalError("Failed to load CoreData model from bundle")
        }
        return model
    }()

    /// 创建一个 in-memory NSManagedObjectContext。
    /// 数据隔离：每次新建独立 coordinator + 独立 in-memory store。
    static func makeContext() -> NSManagedObjectContext {
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: sharedModel)
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