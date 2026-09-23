# Swift 6 迁移：Core Data model 共享与全局状态

> 生成日期：2026-09-23
> 起因：审查 `FirstCC/Services/CoreDataStack.swift:17` 的 `CoreDataModel.shared` 在 Swift 6 下的合规性。
> 结论已超出「一行代码」的范围 —— 它牵出的是「进程内只允许一份 `NSManagedObjectModel`」这条约束的出处，
> 以及 Apple 对这个场景到底说了什么。

---

## 〇、结论卡片（将来 Apple 强推 Swift 6 时先读这 5 行）

| 问题 | 结论 |
|---|---|
| 现在要改吗？ | **不用。** 当前 Swift 5 下两平台构建全绿、0 警告，改了拿不到可见收益 |
| 将来 Swift 6 会怎么报？ | iOS 模块在**声明侧**报 `#MutableGlobalVariable`（error）；Mac 因 `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` 改为**消费侧**报 actor 隔离警告 |
| 正解是什么？ | `nonisolated(unsafe) static let shared: NSManagedObjectModel` —— 实测 5 种配置下唯一全清的写法 |
| 最大的风险？ | **不是这一行**，是它与 Mac 测试 Suite 上 `@MainActor` 的纠缠（见「五、风险登记」） |
| 这一行能代表 Swift 6 迁移吗？ | **不能。** Mac app target 全量构建有 **12 个** `#NonSendableInAsyncConformanceOrOverride`，那些在 Swift 6 下也是 error |

**一句话总纲**：现在这份 `CoreDataModel.shared` 是 **Apple-conformant（符合 Apple 写明的约束），
但不是 Apple-documented recipe（Apple 从没为「app 与测试共处一进程」提供过配方）。**

---

## 一、这个全局状态为什么存在

### 1.1 `+entity` 的机制

`Entity(context:)` / `NSManagedObject.init(context:)` 内部调用类方法 `+[NSManagedObject entity]`，
它**按类名在整个进程注册过的模型里**查实体描述。

只要进程里存在**第二份** `NSManagedObjectModel`（`model.copy()` 也算 —— `copy()` 会产生**新的实体描述**），
同一个子类被两个模型声称，`+entity` 就返回**空的** `NSEntityDescription` 并打日志：

```
Multiple NSEntityDescriptions claim the NSManagedObject subclass 'X' so +entity is unable to disambiguate
+[X entity] Failed to find a unique match for an NSEntityDescription to a managed object subclass
```

随后 `Entity(context:)` 的兜底行为不稳定：有时回落到 context 所属模型，有时给对象绑上另一份模型的实体。

### 1.2 后果

`save()` 报 `NSPersistentStoreIncompatibleSchemaError`（错误码 134020，
"用来打开储存的型号配置与用来创建该储存的型号配置不兼容"）。

> ⚠️ **出处界定**：**134020 与「重复 model」的因果关联不是 Apple 说法。** SDK 头
> `CoreDataErrors.h:60` 里 134020 的注释是
> `// store returned an error for save operation (database level errors ie missing table, no permissions)`。
> 没有任何 Apple 文档或工程师回复把两者关联起来。上面这条链是**本项目实测观察到的现象**。

**实测判据**（不是「崩不崩」—— 同一份代码下崩溃是非确定性的）：

| 指标 | 修复前 | 修复后 |
|---|---|---|
| `Failed to find a unique match` | 554 次 | **0** |
| `Multiple NSEntityDescriptions` | 42 条（跨 21 个类） | **0** |

### 1.3 已落地的修复

- `1be4ba4` —— app 与 iOS 测试共用同一份 `NSManagedObjectModel`（`enum CoreDataModel`）
- `5c7e08c` —— Mac 测试侧删掉 `loadModel()` + `model.copy()`，改复用 `CoreDataModel.shared`

**隔离靠 store，不靠 model**：每个测试新建 coordinator + 新建 in-memory store（`at: nil`），
model 共用不影响数据隔离。

---

## 二、Apple 官方立场查证结果（2026-09-23）

### 2.1 文档化的事实（逐字引用）

| 出处 | 原话 | 对我们的意义 |
|---|---|---|
| `+[NSManagedObject entity]` | *"This method is only legal to call on subclasses of `NSManagedObject` that represent a single entity in the model."* | **「一个子类一个 model」的唯一文档依据**，是本次修复的锚点 |
| `NSManagedObject.init(context:)` | 同上，一字不差 | 我们全项目用 `Entity(context:)` |
| `NSManagedObject.fetchRequest()` | 同上，一字不差 | — |
| `NSPersistentContainer.init(name:managedObjectModel:)` | *"Passing in the `NSManagedObjectModel` object overrides the lookup of the model by the provided name value."* | Apple **文档化的唯一**共享 model 手段，我们用的就是它 |
| `NSPersistentContainer.init(name:)` | name *"is used to **look up** the name of the `NSManagedObjectModel` object"* | Apple **只说 "look up"，从未说「每次构造新建一份」**，也没文档化任何缓存 |
| `NSPersistentContainer.name` | *"This name is used to locate the`NSManagedObjectModel` (if the `NSManagedObjectModel` object is not passed in as part of the initialization)"* | — |
| `NSManagedObjectModel` — "Editing models at runtime" | *"once a model is being used, it **must not** be changed… If you need to **modify** a model that's in use, create a copy, modify the copy…"* | **`model.copy()` 误解的来源。** 前提是「**要改**这个 model」，讲的是用 copy 来改，**不是用 copy 来隔离** |
| `NSPersistentStoreCoordinator` Overview | *"A coordinator performs its work on a private queue and executes that work serially. You can use multiple coordinators if the work requires separate queues."* | 讲 coordinator，**没讲 model** |

**关于 `Sendable`（这是一个很干净的证据）：**

| 类型 | Conforms To 里有 `Sendable` 吗 |
|---|---|
| `NSPersistentContainer` | ✅ 有 |
| `NSPersistentStoreCoordinator` | ✅ 有 |
| `NSManagedObjectContext` | ✅ 有 |
| `NSManagedObjectID` | ✅ 有 |
| **`NSManagedObjectModel`** | ❌ **没有** |

Apple 认为 model 就是那个**不该跨并发域共享**的类型。这正是下面第三章「Swift 6 迁移项」的由来。

**Apple 文档对 `NSManagedObjectModel` 的线程安全没有任何表述**；已归档的
*Core Data Programming Guide: Concurrency* 也只讲 `NSManagedObjectContext` 与 `NSManagedObject`，
**压根没提 model**。

### 2.2 Apple 自己的模板长什么样

`/Applications/Xcode.app/Contents/Developer/Library/Xcode/Templates/Project Templates/Base/SwiftUI App Base.xctemplate/Persistence-CoreData.swift`：

```swift
struct PersistenceController {
    static let shared = PersistenceController()          // ← 单例的是「栈」，不是 model
    @MainActor
    static let preview: PersistenceController = {
        let result = PersistenceController(inMemory: true) // ← in-memory 用 /dev/null 实现
        …
    }()
    init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "___PACKAGENAME:identifier___")  // ← 不传 model
        if inMemory {
            container.persistentStoreDescriptions.first!.url = URL(fileURLWithPath: "/dev/null")
        }
        container.loadPersistentStores(completionHandler: { … })
    }
}
```

**模板里没有任何 model 单例。** 唯一性来自「栈是单例 → `init(name:)` 只被调用一次」这个**副作用**。

Apple 文档 *Setting up a Core Data stack* 也是同一形状：*"Typically, you initialize a Core Data
stack as a singleton:"* + `static let shared = CoreDataStack()` + `NSPersistentContainer(name: "DataModel")`。

### 2.3 Apple 开发者论坛（developer.apple.com/forums）

**⭐ thread 682136 —— 场景与本项目完全一致（app 与单测共处一个进程）**

提问者的测试基类持有 `static var model: NSManagedObjectModel?`，用它建
`NSPersistentContainer(name:managedObjectModel:)`，崩在
`+[MySchema.MyEntity entity] Failed to find a unique match…`。

Apple **Frameworks Engineer** 回复：

> "You have loaded multiple instances of your managed object model. What does
> `CoreDataTestCase.model` look like? If it's returning a new instance each time that's the
> source of your issue."

同一帖他还有一句有区分度的话 —— 对 `static var` + lazy init：

> "I don't believe there are any implicit concurrency guarantees there, and you don't have any
> locks or semaphores to prevent setUp from being called concurrently."

→ **这是全库唯一一条 Apple 工程师对「重复 model → `+entity` 歧义」的确认。**
注意它**没有**推荐 model 单例；也注意 `static var` 与 `static let` 在此点上不同（见第三章）。

**thread 779255 —— DTS Engineer Ziqiao Chen（2025-04）**

> "It seems to me that the issue is triggered because `NSStagedMigrationManager` and
> `NSPersistentContainer` load the same models into separate Core Data stacks, which leads to a
> conflict."

他给的 workaround 是改用 `insertNewObject(forEntityName:into:)` 绕开 `+entity`，但自己承认
*"this doesn't reflect the best practices of using strong types, nor is it practical for a
real-world project"*，最后建议 **提 feedback 报 bug**（FB18334791，2026-05 仍可复现）。

→ **Apple 的定性是「这是个 bug」，不是「你这样拼不对，你该改成单例」。**

**⚠️ thread 695840 —— 一条被广泛误引的帖子**

网上常把这段引作「Apple 建议把 model 做成 static / singleton」：

> "Don't load your model in PersistentController initializer as this is what loads the model
> multiple times. Just make it static (either a let constant or a singleton)…"

**该帖没有任何 Apple 工程师回复** —— 参与者只有提问者与另一位社区成员，
这段是**提问者自己的 self-accepted answer**。**不要当官方依据引用。**

### 2.4 测试侧：Apple 没有给指引

| 查证对象 | 结果 |
|---|---|
| `developer.apple.com/documentation/coredata/testing-core-data` | **HTTP 404，不存在这一页** |
| WWDC 专场 | 无 |
| `NSInMemoryStoreType` 页面 | 全页只有一句 *"The in-memory store type."*，无 testing 指引 |
| `/dev/null` in-memory 写法 | **只出现在 Xcode 模板里**，且只服务于 `#Preview` |
| 解释该模板的论坛帖 659777 | **无 Apple 工程师回复** |
| `NSPersistentContainer.persistentStoreDescriptions` | 这是唯一真实可用的钩子：*"If you will be configuring custom persistent store descriptions, you must set this property **before** calling `loadPersistentStores(completionHandler:)`."* |

### 2.5 官方立场小结

**Apple 从未文档化、也从未推荐 `static let shared: NSManagedObjectModel` 单例。**

Apple 文档化的做法是把**栈**做成单例，于是 model 顺带唯一。
Apple 文档化的**共享**手段是 `init(name:managedObjectModel:)` 注入 —— 我们用了它，
但注入的那个实例来自一个 Apple 没有文档化的全局。

**零件全是官方的，拼法不是。**

---

## 三、Swift 6 到底会怎么报（编译实测，非推测）

### 3.1 声明侧

| 模块形态 | Swift 5 | Swift 6 |
|---|---|---|
| iOS 模块（**无** `-default-isolation`） | ✅ | ❌ **error** `static property 'shared' is not concurrency-safe because non-'Sendable' type 'NSManagedObjectModel' may have shared mutable state [#MutableGlobalVariable]` |
| Mac app 模块（`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`） | ✅ | ✅ 声明侧不报（被推断为 `@MainActor @preconcurrency`），问题推给消费侧 |

`M2.swiftinterface` 实测导出签名：

```
@_Concurrency::MainActor @preconcurrency @_hasInitialValue public static let shared: CoreData::NSManagedObjectModel
```

### 3.2 消费侧：`@testable import` 在 Swift 5 下**不做这项检查**

这是「为什么现在 0 警告」的答案。对照实验（模块声明为 `@MainActor` 隔离，消费侧从 nonisolated 上下文访问）：

| 消费侧写法 | Swift 5 | Swift 6 |
|---|---|---|
| 普通 `import` | ⚠️ 报 `main actor-isolated static property 'shared' can not be referenced from a nonisolated context` | ⚠️ 报 |
| **`@testable import`** | ✅ **不报** | ⚠️ 报 |

本项目 `QianeymacTests/*` 与 `钱伲Tests/*` **清一色用 `@testable import`**。
所以现在的「全绿」是**编译器没查，不是写法合法**。

### 3.3 三种写法的诊断矩阵

| 声明写法 | Swift 5 | Swift 5 + MainActor | Swift 5 + strict=complete | Swift 6 + MainActor | Swift 6 默认 |
|---|---|---|---|---|---|
| `static let shared` | ✅ | ✅ | ✅ | ✅ | ❌ `#MutableGlobalVariable` |
| `nonisolated static let shared` | ⚠️ | ⚠️ | ⚠️ | ⚠️ | ❌ `#MutableGlobalVariable` |
| **`nonisolated(unsafe) static let shared`** | ✅ | ✅ | ✅ | ✅ | ✅ |

**`nonisolated(unsafe)` 是唯一在全部配置下 0 诊断的写法。**
（不带 `unsafe` 的 `nonisolated` 仍报 `#MutableGlobalVariable`。）

消费侧验证：`nonisolated(unsafe)` 在**两种模块形态**（含/不含 `-default-isolation MainActor`）
× **Swift 5 / Swift 6** 下，`@testable import` 消费均 0 诊断。

### 3.4 全部引用点清单（迁移时逐一确认）

| 位置 | 访问方式 | Swift 6 命运 |
|---|---|---|
| `FirstCC/Services/CoreDataStack.swift:17` | 声明处 | **iOS：声明侧 error**；Mac：`CoreDataStack` 本身是 `@MainActor`，OK |
| `FirstCC/Services/CoreDataStack.swift:73` | 同模块 | 同上 |
| `钱伲Tests/TestSupport/InMemoryCoreDataStack.swift:19` | `@testable import 钱伲` | 被声明侧 error 先挡住 |
| `QianeymacTests/BudgetServiceTests.swift:48` | `@testable import Qianeymac`，Suite 标了 `@MainActor` | ✅ 合法 |

**注意最后一行**：Mac 测试现在恰好合法，**只是因为 Suite 上标了 `@MainActor`**。

### 3.5 Swift 语言层依据（SE-0412）

> "Under strict concurrency checking, require every global variable to either be isolated to a
> global actor or be both: 1. immutable 2. of `Sendable` type"

我们的 `static let` 满足 1，**不满足 2**。

> "Although global variables are lazily initialized, the initialization is **already guaranteed
> to be thread-safe** and therefore requires no further specification under strict concurrency
> checking."

→ **初始化本身**由语言保证线程安全，这不是问题所在。（本项目实测：200 并发线程读同一个
`nonisolated(unsafe) static let`，带副作用的初始化器只跑了 **1 次**。与这段原文一致。）

> "The attribute `nonisolated(unsafe)` can be used to annotate the global variable (or any form of
> storage). Though this will disable static checking of data isolation for the global variable,
> note that without correct implementation of a synchronization mechanism to achieve data
> isolation, dynamic run-time analysis from exclusivity enforcement or tools such as Thread
> Sanitizer could still identify failures."

---

## 四、将来做 Swift 6 迁移时的清单

**不要单独改这一行。** 它拿不到任何可见收益（Swift 5 下前后都是 0 警告），而且会削弱
「这里在 Swift 6 下会报」这个可见的提醒。按顺序一次做完：

1. **先解决规模更大的阻塞项。** Mac app target 全量构建实测有 **12 个**
   `[#NonSendableInAsyncConformanceOrOverride]` 警告 —— 那在 Swift 6 下是 error。
   这一行只是路上的一个小坑。
2. **改声明**：`FirstCC/Services/CoreDataStack.swift:17`
   ```swift
   nonisolated(unsafe) static let shared: NSManagedObjectModel = { … }()
   ```
3. **在同一 commit 里给 Mac Suite 的 `@MainActor` 加锚定注释**，说明它为什么不能删（见「五」）。
4. **在声明旁边补一句「为什么可以 unsafe」**：
   model 加载完成后不再变更（Apple：*"once a model is being used, it must not be changed"*）+
   `static let` 惰性初始化由语言保证线程安全。
5. **两个消费点复核**：`钱伲Tests/…/InMemoryCoreDataStack.swift:19`、
   `QianeymacTests/BudgetServiceTests.swift:48`。
6. **验证方式**：不要 grep SDK 接口文件（会假阴性），用下面的复现脚本**编译实测**。

---

## 五、风险登记

### 🔴 R1 —— 最大的风险不是这一行，是它与 `@MainActor` 的纠缠

Mac 测试 Suite 上的 `@MainActor` 现在**同时干两件事**：

1. 修 Core Data 线程违规 —— Swift Testing 把测试跑在协作线程池上，而 fixture 用的是
   `.mainQueueConcurrencyType` context。Apple DTS 的定性是 *"Violating the programming pattern
   can trigger random crashes in Core Data"*。**这才是真正会崩的那个。**
2. 顺带让 `CoreDataModel.shared` 的访问在类型检查上合法。

改成 `nonisolated(unsafe)` 后，**② 不再需要**。将来有人清理「看起来多余的 `@MainActor`」，
就会把 ① 放回来 —— Mac 套件重新开始随机崩，而且**失败集合每轮不同**，极难定位。

→ **必须同一 commit 在 Suite 上留锚定注释。** 现状：`QianeymacTests/BudgetServiceTests.swift:23`。

### 🟡 R2 —— `unsafe` 是承诺，不是保证

`nonisolated(unsafe)` 是在向编译器承诺「这些访问由我自己保证安全」。本项目成立的前提：

- `NSManagedObjectModel` 加载完成后不再变更（Apple 文档原文支持）
- `static let` 惰性初始化由语言保证线程安全（SE-0412 原文支持）

**但这个承诺会被后续改动悄悄推翻**：只要有人在这里改成 `var`、加重新赋值、
或再引入 `copy()`，编译器就不再拦，`unsafe` 变成假话。

### 🟡 R3 —— 单独改它治不了 Swift 6 迁移

见「四、1」。12 个 `#NonSendableInAsyncConformanceOrOverride` 是更硬的阻塞项。

### 🟢 R4 —— 不改的风险是零

当前两平台构建全绿。它是「还没被编译器检查」的点，不是「已知会出问题」的点。

### 已评估但**不推荐**的替代方案

**让测试别自建栈，转而注入 app 栈的 context，或用 `persistentStoreDescriptions` 把 app 容器改成
in-memory。** 这样连 model 单例都不需要，形式上更贴 Apple 文档。但：

- `persistentStoreDescriptions` 必须在 `loadPersistentStores` **之前**设置，
  而宿主测试里 `CoreDataStack.shared` 可能在测试开始前就已 load 过 store
- 会把测试与 app 的生命周期绑死

→ **比现在这版更脆，不采用。**

---

## 六、复现脚本（不依赖 `/tmp` 残留）

```bash
SDK=$(xcrun --show-sdk-path --sdk macosx)
UP=(-enable-upcoming-feature DisableOutwardActorInference \
    -enable-upcoming-feature InferSendableFromCaptures \
    -enable-upcoming-feature GlobalActorIsolatedTypesUsability \
    -enable-upcoming-feature MemberImportVisibility \
    -enable-upcoming-feature InferIsolatedConformances \
    -enable-upcoming-feature NonisolatedNonsendingByDefault)

# ① 声明侧：iOS 模块形态（无 -default-isolation）在 Swift 6 下报 #MutableGlobalVariable
cat > decl.swift <<'EOF'
import CoreData
enum CoreDataModel {
    static let shared: NSManagedObjectModel = NSManagedObjectModel()   // ← 换成 nonisolated(unsafe) 即通过
    static func keepAlive() { _ = shared }
}
EOF
xcrun swiftc -typecheck -sdk "$SDK" -swift-version 6 decl.swift

# ② 消费侧：@testable import 在 Swift 5 下不检查、Swift 6 下才报
xcrun swiftc -emit-module -emit-library -module-name M -swift-version 5 -enable-testing \
  -default-isolation MainActor -sdk "$SDK" decl.swift -o libM.dylib
cat > consumer.swift <<'EOF'
import CoreData
@testable import M
struct T { static func make() -> NSManagedObjectModel { CoreDataModel.shared } }
EOF
for v in 5 6; do
  echo "--- Swift $v ---"
  xcrun swiftc -typecheck -sdk "$SDK" -swift-version $v $UP -I . consumer.swift
done
```

> 注：zsh **不会**对未加引号的 `$var` 做词分割。要展开数组用 `${=UP}`，否则
> `-swift-version 5` 会被当成一个参数传进去 → `unknown argument`。

---

## 七、参考链接

**Apple 文档**
- [NSManagedObjectModel](https://developer.apple.com/documentation/coredata/nsmanagedobjectmodel) —— 尤其 "Editing models at runtime"
- [NSManagedObject.entity()](https://developer.apple.com/documentation/coredata/nsmanagedobject/entity())
- [NSManagedObject.init(context:)](https://developer.apple.com/documentation/coredata/nsmanagedobject/init(context:))
- [NSPersistentContainer.init(name:)](https://developer.apple.com/documentation/coredata/nspersistentcontainer/init(name:)) / [init(name:managedObjectModel:)](https://developer.apple.com/documentation/coredata/nspersistentcontainer/init(name:managedobjectmodel:))
- [Setting up a Core Data stack](https://developer.apple.com/documentation/coredata/setting-up-a-core-data-stack) / […manually](https://developer.apple.com/documentation/coredata/setting-up-a-core-data-stack-manually)
- [NSPersistentContainer.persistentStoreDescriptions](https://developer.apple.com/documentation/coredata/nspersistentcontainer/persistentstoredescriptions)

**Apple 开发者论坛**
- ⭐ [thread 682136](https://developer.apple.com/forums/thread/682136) —— app+单测共处一进程，**唯一一条工程师确认**
- [thread 779255](https://developer.apple.com/forums/thread/779255) —— DTS Engineer Ziqiao Chen，定性为 conflict，建议提 feedback（FB18334791）
- ⚠️ [thread 695840](https://developer.apple.com/forums/thread/695840) —— **无 Apple 工程师回复**，勿引用为官方建议

**Swift Evolution**
- [SE-0412: Strict concurrency for global variables](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0412-strict-concurrency-for-global-variables.md)

**本项目相关代码与提交**
- 修复：`1be4ba4`（共享 model）、`5c7e08c`（Mac 测试复用共享 model + `@MainActor`）、`1ea1660`（CLAUDE.md 更正）
- 声明：`FirstCC/Services/CoreDataStack.swift:17`
- 测试栈：`钱伲Tests/TestSupport/InMemoryCoreDataStack.swift`、`QianeymacTests/BudgetServiceTests.swift`
