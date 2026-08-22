import XCTest
@preconcurrency import CoreData
@testable import 钱伲

/// SharedLedgerImportService 单元测试
///
/// Known issue: SharedLedgerImportService 依赖 NSPersistentCloudKitContainer + sharedStore + viewContext，
/// 需要真实 CloudKit 容器才能测试。In-memory CoreData 测试环境无法提供。
/// 按约束不修 service 代码，整体测试加 disabled_ 前缀跳过。
///
/// 保留为 known issue 文档，等待后续 CloudKit mock 基础设施就绪后再启用。
final class SharedLedgerImportServiceTests: CoreDataTestCase {

    func disabled_test_importSharedLedgers_requiresCloudKitContainer() throws {
        throw XCTSkip("Known issue: SharedLedgerImportService 需要 NSPersistentCloudKitContainer，in-memory CoreData 测试环境无法提供")
        // 任何实际测试都需要 mock CloudKit 容器，超出当前测试基础设施范围
        let _ = SharedLedgerImportService.shared
    }

    func disabled_test_importSharedLedgers_marksLedgersAsShared() throws {
        throw XCTSkip("Known issue: 需要 CloudKit mock 容器才能验证共享标记行为")
    }

    func disabled_test_dumpSharedStoreInventory_countsEntities() throws {
        throw XCTSkip("Known issue: 需要 CloudKit mock 容器才能验证 COUNT 查询")
    }
}