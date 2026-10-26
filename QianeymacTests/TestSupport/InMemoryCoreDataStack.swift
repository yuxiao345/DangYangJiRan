import Foundation
@preconcurrency import CoreData
@testable import Qianeymac

/// 共享内存 CoreData 栈，用于 Mac 单元测试。
///
/// 每次调用创建独立的 in-memory store，互不干扰。
///
/// model 复用进程内唯一的那份 `CoreDataModel.shared`，**数据隔离靠 store、不靠 model**：
/// 每次新建 coordinator + 新建 in-memory store。绝不能在这里自建 model 或 `model.copy()`
/// ——宿主 `Qianey.app` 启动时（`QianeymacApp.swift` 的 `AppContainer()`）已经建了一份，
/// 进程里出现第二份会让 `+[NSManagedObject entity]` 因同一子类被两个模型声称而解析失败，
/// `Entity(context:)` 的兜底不稳定，`save()` 报 NSPersistentStoreIncompatibleSchemaError
/// (134020) 而崩。完整机制见 `CoreDataModel` 的文档注释。
enum InMemoryCoreDataStack {

    static func makeContext() -> NSManagedObjectContext {
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: CoreDataModel.shared)
        do {
            try coordinator.addPersistentStore(ofType: NSInMemoryStoreType, configurationName: nil, at: nil)
        } catch {
            fatalError("Failed to add in-memory store: \(error)")
        }
        let ctx = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        ctx.persistentStoreCoordinator = coordinator
        return ctx
    }
}

// MARK: - 共用夹具

/// 这些 fixture 方法访问 `.mainQueueConcurrencyType` context，所以整体钉在 MainActor 上。
/// Swift Testing 的 Suite 也必须标 `@MainActor`（理由见 `BudgetServiceTests` 顶部注释）。
@MainActor
extension NSManagedObjectContext {

    /// 尝试 save，失败返回 Error，成功返回 nil（代替 try!）
    func saveAsError() -> Error? {
        guard hasChanges else { return nil }
        do { try save(); return nil }
        catch { return error }
    }

    @discardableResult
    func makeLedger(_ name: String = "测试账本") -> Ledger {
        let l = Ledger(name: name, context: self)
        l.defaultCurrencyCode = "CNY"
        if let err = saveAsError() { fatalError("makeLedger save failed: \(err)") }
        return l
    }

    @discardableResult
    func makeAccount(_ name: String = "测试账户", _ ledger: Ledger) -> Account {
        let a = Account(name: name, context: self)
        a.ledger = ledger
        if let err = saveAsError() { fatalError("makeAccount save failed: \(err)") }
        return a
    }
}
