import XCTest
@preconcurrency import CoreData
@testable import 钱伲

/// 共享内存 CoreData 栈，用于单元测试。
/// 每次创建都是独立的内存 store，互不干扰。
enum InMemoryCoreDataStack {

    /// 创建一个加载了 FirstCC 数据模型的 in-memory NSManagedObjectContext。
    /// 注意：必须使用 `Bundle(for: SomeEntity.self)` 找到 .momd 资源。
    static func makeContext() -> NSManagedObjectContext {
        guard let modelURL = Bundle(for: Account.self).url(forResource: "FirstCC", withExtension: "momd"),
              let model = NSManagedObjectModel(contentsOf: modelURL) else {
            fatalError("Failed to load CoreData model from bundle")
        }
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
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