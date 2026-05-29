# SwiftData → Core Data 迁移：研究汇总与更新规划

> 生成日期：2026-05-24
> 背景：项目目前 16 个 @Model 类，~60 个视图用 @Query，CloudKit 共享已通过 SharedPersistenceController 跑通（Core Data 双 Store 架构）。目标是把主体从 SwiftData 迁移到 Core Data，统一技术栈。

---

## 一、清单总览

| # | 问题 | 风险等级 | 状态 |
|---|---|---|---|
| 1 | Transformable `[String]` 在 CloudKit 中的兼容性 | 🔴 高 | 已查明，有方案 |
| 2 | Decimal 类型在 CloudKit 中的精度损失 & iOS 18 Bug | 🔴 高 | 已查明，需规避 |
| 3 | 双 Store（Private + Shared）配置最佳实践 | 🟡 中 | 已查明，与现有代码一致 |
| 4 | @FetchRequest 替代 @Query 的可行性与限制 | 🟢 低 | 已验证可行 |
| 5 | NSManagedObject 子类代码生成策略 | 🟢 低 | 已确定 Manual/None |
| 6 | Core Data + CloudKit 完整上线要求清单 | 🟡 中 | 已整理 |
| 7 | 关系逆向（inverse）要求 | 🔴 高 | 必须逐条检查 |
| 8 | iOS 18 特定 Bug（同步延迟、登出丢数据） | 🔴 高 | 非代码问题，需告知用户 |
| 9 | 跨配置关系限制 | 🟡 中 | 架构约束 |
| 10 | 迁移期间双轨运行（SwiftData + Core Data 共存） | 🟡 中 | 需规划 |
| 11 | NSManagedObject 的 Swift 6 Sendable 限制 | 🟡 中 | 需调整数据传递模式 |
| 12 | UUID 默认值在 xcdatamodeld 中的已知 Bug | 🟡 中 | 需 awakeFromInsert 兜底 |
| 13 | Deny 删除规则在 CloudKit 中禁止 | 🟡 中 | 需检查现有关系 |

---

## 二、逐项详细分析

### 1. Transformable `[String]` 数组 — CloudKit 兼容性

**风险：** 项目中 `Transaction.tags: [String]` 和 `Transaction.photoURLs: [String]?` 使用了 SwiftData 的 `[String]` 类型（内部通过 Transformable 实现）。迁移到 Core Data 后必须显式处理 Transformable，否则 CloudKit 会崩溃。

**研究结果（来源：Apple Developer Forums thread 123266、799236）：**

- `NSPersistentCloudKitContainer` 支持 Transformable，但序列化为 CloudKit 的 **Bytes** 类型（不是原生数组）。
- **已知 Bug：** 如果用 `NSSecureUnarchiveFromDataTransformer`（系统默认），CloudKit 启动时崩溃，错误码 134060。原因是该 Transformer 未注册到 `+[NSValueTransformer valueTransformerForName:]`。
- **解决方案（Apple DTS 工程师确认）：** 创建自定义 `NSSecureUnarchiveFromDataTransformer` 子类并显式注册。

**推荐方案（三个选项）：**

| 方案 | 适用场景 | CloudKit 兼容性 | 复杂度 |
|---|---|---|---|
| A. 自定义 Transformer 子类 + 显式注册 | tags（<20个，不查询单个值） | ✅ Bytes | 低 |
| B. JSON String 存储（encode/decode） | photoURLs（整体消费） | ✅ 原生 String | 低 |
| C. 独立 Tag 实体 + to-many 关系 | 需要查询/搜索标签 | ✅ 原生 CKRecord | 高 |

**本项目决策（2026-05-24）：** 两处都用 **方案 B（JSON String）**，风险最小，代码和性能损失可接受。

**代码示例（方案 A）：**
```swift
@objc(StringArrayTransformer)
final class StringArrayTransformer: NSSecureUnarchiveFromDataTransformer {
    static let name = NSValueTransformerName("StringArrayTransformer")
    override static var allowedTopLevelClasses: [AnyClass] {
        [NSArray.self, NSString.self]
    }
    static func register() {
        ValueTransformer.setValueTransformer(
            StringArrayTransformer(), forName: name
        )
    }
}
// 在 loadPersistentStores 之前调用：
// StringArrayTransformer.register()
```

**⚠️ Xcode 16+ 特别注意（来源：Apple Developer Forums thread 760985）：**
在 `.xcdatamodeld` 编辑器中，Transformable 属性的 **Custom Class** 字段必须填 `NSArray`（不能填 `[String]`），否则 Xcode 报错 "Declared Objective-C type '[String]' is not valid"。Swift 代码中 `@NSManaged var` 仍可声明为 `[String]?`，运行时正确转换。

**冲突解决粒度：** Transformable 在 CloudKit 中作为整体 blob 同步，冲突时整数组替换（非元素级合并）。对 tags 场景影响不大。

---

### 2. Decimal 类型 — CloudKit 精度损失 & iOS 18 Bug

**风险：** 项目中所有金额（Transaction.amount、Account.initialBalance、Budget.amount、SplitEntry.amount 等）都用 `Decimal`。这是记账 App 的核心数据类型。

**研究结果（来源：Apple 文档、Developer Forums thread 775907、767395、766564、803764）：**

**类型映射链路：** `SwiftData Decimal` → Core Data `NSDecimalAttributeType` → 代码层 `NSDecimalNumber` → SQLite 存储为 `REAL`（64 位 IEEE 754 double，~15 位有效数字）→ CloudKit 映射为 `NSNumber`。两层损失：SQLite 层和 CloudKit 层都存为 double。

**精度损失不可避免** — `0.6789` 可能取回 `0.6788999999999999`。但 15 位有效数字对家庭记账足够：9 位整数 + 2 位小数 = 11 位，在安全范围内。

**iOS 18 已确认 Bug：**

| Bug | 触发条件 | 严重程度 |
|---|---|---|
| 正分数 Decimal + 派生属性崩溃 | `@sum` 聚合 + 正分数 Decimal（如 1000.01）| 🔴 崩溃 |
| 同步完全失败 | iOS 18 设备，之前 iOS 17.5 正常工作 | 🔴 数据不同步 |
| 导出崩溃（code 134421） | `NSEntityDescription.objectID` unrecognized selector | 🔴 崩溃 |
| 模拟器同步失败 | iOS 18 模拟器特有问题 | 🟡 仅模拟器 |

**规避策略：**

1. **不用派生属性**（`@sum`、`@avg` 等）— 所有聚合计算手动在代码中完成（本项目本来就手动计算 currentBalance，不受影响）。
2. **不用 NSBatchDeleteRequest** 在含 Decimal 的实体上 — 使用逐条删除。
3. **Decimal 精度损失** — 对于家庭记账，金额通常 ≤ 8 位数 + 2 位小数，Double 的 15-17 位有效数字**足够**。但如果有超大金额（>10^13 分），需考虑存为 String 手动编解码。
4. **仅在真机测试** — iOS 18 模拟器有已知同步 Bug，不反映真实行为。

**规避方案对比：**

| 方案 | 精度 | 复杂度 | 说明 |
|------|------|--------|------|
| 保持 Decimal/double | ~15 位有效数字 | 零 | 默认行为，家庭记账足够 |
| 存为 Int64（分值） | 完全精确，支持 9e16 分 | 中 | UI 层需格式化，查询/排序原生支持 |
| 存为 String | 38 位完整精度 | 高 | 查询/排序需自定义，不推荐 |

**零值比较注意事项：** 因精度误差，`amount == 0` 可能失败，应使用 `abs(amount) < 1e-10` 或 `NSDecimalNumber.compare(NSDecimalNumber.zero)`。

**最终决策（2026-05-24）：全项目金额统一用 Int64 分值存储**。

```swift
// Core Data: Integer 64 属性
@NSManaged var amountInFen: Int64  // 123456 代表 ¥1234.56

// computed property 桥接
var amount: Decimal {
    get { Decimal(amountInFen) / 100 }
    set { amountInFen = (newValue * 100 as NSDecimalNumber).int64Value }
}
```

- 完全精确，无浮点误差
- 排序、比较、聚合全部准确
- 支持最大金额 ~9e16 分（90 万亿），家庭记账用不完
- 局限：固定两位小数（分），对于日元（无小数）、多币种不同小数位的场景，加 `currencyDecimals` 字段动态调整除数即可

---

### 3. 双 Store（Private + Shared）配置

**风险：** 涉及 CloudKit 共享的核心架构决策。配错会导致数据存错位置或无法共享。

**研究结果（来源：Apple 官方文档 "Sharing Core Data objects between iCloud users"、WWDC 2021 Session 10015）：**

**Apple 官方推荐模式：**
- 一个 `NSPersistentCloudKitContainer`，两个 `NSPersistentStoreDescription`
- 一个 `.private` 数据库范围（自己数据），一个 `.shared` 数据库范围（共享数据）
- `.xcdatamodeld` 中两个命名配置："Private" 和 "Shared"

**关键约束（与现有 SharedPersistenceController 一致）：**

| 约束 | 说明 |
|---|---|
| 两个 Store 都需要 `NSPersistentHistoryTrackingKey` | ✅ 已在用 |
| 两个 Store 都需要 `NSPersistentStoreRemoteChangeNotificationPostOptionKey` | ✅ 已在用 |
| 不允许跨配置关系 | 必须用 UUID 外键 + 运行时查找 |
| `affectedStores` 过滤 fetch | ✅ 已在 SharedLedgerImportService 中用 |
| `assign(object, to: store)` 路由写入 | 新对象需显式分配 |
| 实体在两种配置中最好「不相交」 | 简化路由逻辑 |

**与现有代码对比：** SharedPersistenceController 已经正确实现了双 Store 架构。迁移到 Core Data 主体后，这个控制器可以复用。

**版本要求：** `.shared` database scope 最低要求 iOS 16.4（之前直接抛异常）。本项目设置 iOS 18 部署目标，不受影响。

**Info.plist 必需：** `CKSharingSupported = YES`（布尔值），否则共享功能不生效。

**Apple 官方示例的两种模式：**

| 模式 | 做法 | 适用场景 |
|------|------|---------|
| 分离 Configuration | xcdatamodeld 中 "Private"/"Shared" 配置，实体互斥归属 | 实体职责清晰，无需跨配置关系 |
| 同一模型（Apple 示例采用） | 所有实体在默认配置，`assign(_:to:)` + `affectedStores` 控制路由 | 实体需同时存在于两个 Store |

**iOS 18 特别警告：**
- **App Group 容器同步回归**（FB 反馈，thread 767395）：使用 App Group 路径的 store 在 iOS 18 上同步延迟/卡死。建议用默认路径。
- **container.share() 死锁**（已在本项目中验证并修复——使用 callback-based API）。

**本项目决策：** 采用「同一模型」模式（与 Apple 官方示例一致）。所有实体同时存在于两种配置，用 `affectedStores` + `assign(object, to:)` 显式路由。SharedPersistenceController 已按此模式实现。

---

### 4. @FetchRequest 替代 @Query

**风险：** 需要改写 ~60 个视图的 fetch 逻辑。

**研究结果（来源：代码库分析 + Apple 文档）：**

- `@FetchRequest` 与 `NSPersistentCloudKitContainer` 完全兼容。
- `@FetchRequest` 通过 `NSManagedObjectContextDidSave` 通知自动感知 CloudKit push，不需要额外处理。
- 性能：< 500 对象时与 @Query 无差异（本 App 使用场景在此范围内）。
- 动态 predicate 需要视图重建（通过 `id(_:)` 或 `@State` 驱动 init）。

**迁移模式对比：**

```swift
// 旧：SwiftData @Query
@Query(sort: \Transaction.date, order: .reverse)
private var transactions: [Transaction]

// 新：Core Data @FetchRequest
@FetchRequest(
    sortDescriptors: [NSSortDescriptor(keyPath: \Transaction.date, ascending: false)],
    animation: .default
)
private var transactions: FetchedResults<Transaction>
```

**限制：**
- `@FetchRequest` 的 predicate 不可动态修改（需重建视图）
- 复杂过滤场景用 `NSFetchRequest` 手动 fetch（部分视图已经在用这种模式）

**Swift 6 并发注意事项（重要）：**
- `NSManagedObject` 标记为 `NS_SWIFT_NONSENDABLE`，**不能跨 actor 传递**。
- 解决方案：传递 `NSManagedObjectID`（Sendable），在目标 context 中通过 `context.object(with: id)` 重新获取。
- `NSManagedObjectContext` 自身是 Sendable 的，但访问必须通过 `perform()` / `performAndWait()`。
- 不要用 `@unchecked Sendable` 绕过——编译通过但隐藏数据竞争。

**社区共识（来源：HackingWithSwift、Michael Tsai、Andrew Haglund）：**
对于需要 CloudKit 共享的 non-trivial App，社区一致推荐 Core Data + `NSPersistentCloudKitContainer` 而非 SwiftData。原因：SwiftData 截至 iOS 18 仍不支持 `.shared` 数据库范围、迁移困难、稳定性问题。

---

### 5. NSManagedObject 子类代码生成策略

**决策：Manual/None** — 完全手写子类，Xcode 不自动生成。

**理由：**
- 本项目大量使用 `typeRaw: String` + `computed var type: Enum` 桥接模式
- Xcode 自动生成的类文件会覆盖自定义计算属性
- CloudKit 需要 `@objc` 类名精确匹配 `managedObjectClassName`

**代码模式：**
```swift
@objc(Transaction)
final class Transaction: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var typeRaw: String
    @NSManaged var amount: NSDecimalNumber  // 注意：不是 Decimal
    @NSManaged var tags: Data?              // Transformable → Data
    // ... 所有 Core Data 属性

    var type: TransactionType {
        get { TransactionType(rawValue: typeRaw) ?? .expense }
        set { typeRaw = newValue.rawValue }
    }

    var amountDecimal: Decimal {
        get { amount as Decimal }
        set { amount = newValue as NSDecimalNumber }
    }
}
```

---

### 6. Core Data + CloudKit 完整上线要求

**必需 Entitlements：**
- `com.apple.developer.icloud-container-identifiers`
- `com.apple.developer.icloud-services` (CloudKit)
- Push Notifications（远程通知后台模式）

**必需 Info.plist：**
- `NSUbiquitousContainerIdentifier`（可选，但推荐）
- 后台模式：`remote-notification`

**模型要求（硬性）：**

| 要求 | 当前状态 | 说明 |
|------|---------|------|
| 所有非可选属性有默认值 | ✅ SwiftData 已有 | CloudKit 硬性要求 |
| 所有关系可选（nullable） | ✅ 已有 | 相关对象可能不同时到达 |
| 所有关系有逆向（inverse） | ⚠️ 需逐条检查 | 缺失则 CloudKit 报错 |
| 无有序关系（ordered to-many） | ✅ 用的无序 [Model] | CloudKit 不支持 |
| UUID 主键 | ✅ 已有 | 但 UUID 默认值在 xcdatamodeld 中有已知 Bug（FB10592334），需在 awakeFromInsert 中设置 |
| `Deny` 删除规则禁止 | ⚠️ 需检查 | CloudKit 不支持 Deny |
| `initializeCloudKitSchema` 仅调试用 | ⚠️ 需确保 Release 不调用 | 生产环境在 CloudKit Dashboard 部署 Schema |

**CloudKit Dashboard 索引要求：**
- 部署到生产前，需在 Dashboard 中为 `recordName`、`modifiedTimestamp`、`createdTimestamp` 添加 `QUERYABLE` + `SORTABLE` 索引。
- 可用 `initializeCloudKitSchema(options: .dryRun)` 做 Schema 检查（不上传数据）。

**iOS 18 关键警告（来源：Apple Developer Forums）：**
- **iCloud 登出自动删本地数据** — 这是 iOS 18 的 "by design" 行为。未同步的本地修改永久丢失，无法恢复。（Apple DTS 确认）
- **同步延迟回归** — 社区报告 iOS 18 同步速度比 iOS 17 慢。

---

### 7. 关系逆向（Inverse）检查

**所有 @Relationship 必须双向都有 inverse。** 这是 CloudKit 的硬性要求。

需要逐条检查的关系（16 个模型，约 30+ 条关系）。常见的单向关系（如 `Transaction.category`）必须在 `Category` 侧有 `transactions: [Transaction]` 逆向。

---

### 8. 架构约束：跨配置关系

**不允许**在 Private 配置的实体和 Shared 配置的实体之间建 Core Data 关系。

**影响：** 如果 Ledger 在 Shared 配置中，User 在 Private 配置中，则不能有 `Ledger.users` → `User` 的 Core Data 关系。

**解决方案：** 所有共享账本相关的实体（Ledger、Transaction、Account、Category 等）都放在 Shared 配置中。User 用 `cloudKitUserRecordID: String` + 运行时查找关联。

---

### 10. NSManagedObject 的 Swift 6 Sendable 限制

**风险：** 项目大量使用 `@Model` 类在 View/ViewModel/Service 之间传递。Core Data 的 `NSManagedObject` 标记为 `NS_SWIFT_NONSENDABLE`，不能跨 actor 传递。

**研究结果（来源：Apple Developer Forums thread 782289、756807、797809）：**
- `NSManagedObject` 严格 non-Sendable。
- 正确做法：传递 `NSManagedObjectID`（Sendable），在目标 context 中 `context.object(with: id)` 重新获取。
- `NSManagedObjectContext` 自身是 Sendable，但所有访问必须通过 `perform()` / `performAndWait()`。
- Swift 6 语言模式下编译会报错，Swift 5 模式仅警告。

**影响范围：** Service 层返回的实体对象需要改为返回 Sendable DTO 或 `NSManagedObjectID`。View 层直接使用 `@FetchRequest` 的 `FetchedResults` 不受影响（都在主 actor 上）。

**缓解：** 项目当前所有 Service 都在 `@MainActor` 上运行，View 也在主线程，短期内不会触发 actor 隔离问题。但需要建立规范：跨层级传 `NSManagedObjectID`，避免直接传 `NSManagedObject`。

---

### 11. UUID 默认值在 xcdatamodeld 中的已知 Bug

**风险：** Apple 已知 Bug（FB10592334）— 在 Core Data 模型编辑器中为 UUID 属性设置的默认值在运行时被忽略，导致插入时 UUID 为 nil。

**解决方案：** 在 `NSManagedObject` 子类的 `awakeFromInsert()` 中手动设置 UUID：
```swift
override func awakeFromInsert() {
    super.awakeFromInsert()
    id = UUID()
}
```
或者在插入对象时显式设置 `object.setValue(UUID(), forKey: "id")`。

---

### 12. Deny 删除规则在 CloudKit 中禁止

**风险：** `NSPersistentCloudKitContainer` 不支持 `Deny` 删除规则。如果任何关系用了 `.deny`，CloudKit 同步会报错。

**需要检查：** 所有 16 个模型的 `@Relationship(deleteRule: ...)` 中是否有 `.deny`。现有模型主要用 `.cascade` 和 `.nullify`，大概率不受影响，但需要逐一确认。

---

### 13. 迁移策略

**决策：一次性全切**（2026-05-24）。无生产用户，无需双轨过渡。

执行顺序：
1. 新建 `.xcdatamodeld` + 16 个 NSManagedObject 子类
2. 创建 `CoreDataStack` 替代 `ModelContainer`
3. 改 `AppContainer` 用 NSPersistentCloudKitContainer
4. 批量改写 Service 层（ModelContext → NSManagedObjectContext）
5. 批量改写 View 层（@Query → @FetchRequest）
6. 全部通过编译后，删除所有 SwiftData `@Model` 文件

---

## 三、更新后的迁移计划

### Phase 0：基础设施（预计 2-3 天）

**0.1 创建 .xcdatamodeld**
- 使用 "Private" 和 "Shared" 两个 Configuration
- 所有实体同时配置到两个 Configuration
- 每个属性正确设置：类型、可选性、默认值
- 所有关系双向 inverse

**0.2 创建 NSManagedObject 子类**（16 个文件，Manual/None codegen）
- 每个子类：`@NSManaged` 原始属性 + 计算属性桥接（enum、Decimal）
- 保持与现有 SwiftData Model 相同的 public API
- 放到 `Models/CoreData/` 目录

**0.3 创建 CoreDataStack**
- 替代 `AppContainer` 中的 `ModelContainer`
- 整合现有 SharedPersistenceController 逻辑
- 双 Store（Private + Shared）描述

**0.4 数组属性 JSON String 编码**
- `tags: [String]` → 存为 `String`，computed property 做 JSON encode/decode
- `photoURLs: [String]?` → 同上

**0.5 验证基础架构**
- Build 通过
- 本地 CRUD 操作正常
- CloudKit 私有同步正常

### Phase 1：Service 层迁移（预计 2-3 天）

逐服务迁移（独立可测）：
- LedgerServiceImpl
- AccountServiceImpl
- TransactionServiceImpl
- CategoryServiceImpl
- TemplateServiceImpl
- 其余服务

每个 Service 的改动：
- `ModelContext` → `NSManagedObjectContext`
- `FetchDescriptor` → `NSFetchRequest`
- `context.insert(obj)` → 手动创建 NSManagedObject + 插入 context
- `context.save()` → `try context.save()`

### Phase 2：View 层迁移（预计 3-5 天）

逐模块迁移：
- `@Query` → `@FetchRequest`
- `@Environment(\.modelContext)` → `@Environment(\.managedObjectContext)`
- `#Predicate` → `NSPredicate`
- `SortDescriptor` → `NSSortDescriptor`

### Phase 3：共享功能对齐（预计 1-2 天）

- 确保 SharedPersistenceController 与新的 CoreDataStack 统一
- CKShare 创建/接受流程不变
- syncParticipants 功能对齐

### Phase 4：清理（预计 1 天）

- 删除所有 SwiftData `@Model` 文件
- 删除 `AppContainer` 中的 `ModelContainer` 代码
- 删除 SwiftData import

---

## 四、待确认事项（需用户决策）

1. **tags 存储方案：** ✅ 已决策 — JSON String。
2. **photoURLs 存储方案：** ✅ 已决策 — JSON String。
3. **迁移节奏：** ✅ 已决策 — 一次性全切（无生产用户，无需双轨过渡）。
4. **iOS 18 iCloud 登出丢数据：** ✅ 已决策 — UI 层面加提示，提醒用户登出 iCloud 前确保数据已同步。
5. **Decimal 精度：** ✅ 已决策 — 全项目金额统一用 Int64 分值存储，避免浮点精度问题。

---

## 五、来源汇总

| 来源 | 链接/标识 |
|---|---|
| Apple 官方文档 — Sharing Core Data objects between iCloud users | developer.apple.com/documentation/coredata/sharing_core_data_objects_between_icloud_users |
| Apple 官方文档 — Creating a Core Data Model for CloudKit | developer.apple.com/documentation/coredata/creating-a-core-data-model-for-cloudkit |
| WWDC 2021 Session 10015 | "Build apps that share data through CloudKit and Core Data" |
| Apple 示例项目 — cloudkit-coredatasync | github.com/apple/sample-cloudkit-coredatasync |
| Apple Dev Forums — NSSecureUnarchiveFromData + CloudKit crash | thread 123266 |
| Apple Dev Forums — SwiftData CloudKit NSKeyedUnarchiveFromData error | thread 799236 |
| Apple Dev Forums — iOS 18 Core Data CloudKit 同步失败 | thread 767395 |
| Apple Dev Forums — 正分数 Decimal 派生属性崩溃 | thread 775907 |
| Apple Dev Forums — iOS 18 模拟器 CloudKit | thread 766564 |
| Apple Dev Forums — SwiftData 未同步 code 134421 | thread 803764 |
| Apple Dev Forums — Storing Custom Transformable Array | thread 110168 |
| Stack Overflow — How to read arrays with NSPersistentCloudKitContainer | /questions/66090596 |
| Apple DTS 工程师 — Chen Ziqiao 确认自定义 Transformer 方案 | Developer Forums 回复 |
| TN3164 — Debugging NSPersistentCloudKitContainer sync | developer.apple.com/documentation/technotes/tn3164 |
| Apple Dev Forums — Core Data and Swift 6 concurrency | thread 782289 |
| Apple Dev Forums — Using Core Data with Swift 6 language mode | thread 756807 |
| Apple Dev Forums — Xcode 26 Sendable + perform | thread 797809 |
| Apple Dev Forums — Xcode 16 Transformable [String] fix | thread 760985 |
| Apple Dev Forums — iCloud sign-out data wipe (iOS 18) | thread 811294 |
| Apple Dev Forums — CloudKit Core Data sharing participants | thread 659431 |
| Apple Bug — FB10592334 UUID defaults ignored | Feedback Assistant |
| Stack Overflow — Core Data CodeGen differences | /questions/53891194 |
| Stack Overflow — container.share() iOS 18 deadlock | /questions/79912375 |
| Stack Overflow — CoreData and NSDecimalNumber | /questions/30585723 |
| HackingWithSwift — Core Data with SwiftUI | hackingwithswift.com |
| HackingWithSwift — Array of Strings in Core Data | hackingwithswift.com/forums/swiftui/9572 |
| Michael Tsai — Returning to Core Data | mjtsai.com/blog/2024/10/16 |
| Andrew Haglund — Regretting SwiftData | haglund.app/2024/09/02 |
| Fatbobman — CloudKit Sync Rules | fatbobman.com |
| Apple Developer — CKRecord supported types | developer.apple.com/documentation/cloudkit/ckrecord |
| Apple Developer — Linking Data Between Two Core Data Stores | developer.apple.com/documentation/coredata/linking-data-between-two-core-data-stores |
| Apple Developer — NSSecureUnarchiveFromDataTransformer | developer.apple.com/documentation/foundation/nssecureunarchivefromdatatransformer |
