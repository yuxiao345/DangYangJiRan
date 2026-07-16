# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Development Principles

1. **查文档再写代码。** 对实现方法不确定时，先查 Apple 官方文档和开发者论坛，不要自己猜测。
   - **返工两次即查。** 同一问题的修改超过 2 次仍未达到预期，必须停下来查阅 Apple 官方文档，确认标准做法后再继续。不能用熟悉的 API 反复拼凑试错。
   - **不要默认跳过。** "这个应该能拼出来"不等于"不需要查文档"。动手前主动问：Apple 对这个场景有没有专门的 API？如果有，那才是正确答案。如果有，那才是正确答案。
2. **追根因再修。** 标准 API 不达预期时，先去官方文档和论坛查清为什么，不要急于引入 workaround。上次 CKShare 过度工程化就是教训。
3. **动代码前先确认。** 任何代码修改必须先解释方案并等用户明确同意。参见 [[feedback_ask_before_code]]。
4. **iOS 26 优先。** 技术方案使用 Apple 最新推荐 API（iOS 26+），优先兼容 iOS 26.5 正式版。参见 [[feedback_latest_apple_api]]。
5. **不过度工程化。** 标准 API 能用就用最简单的方式。复杂 workaround 只在彻底排除环境问题后才考虑。参见 [[feedback_no_overengineering]]。
6. **UI 控件一致性。** 同一页面、同一功能的控件必须使用相同的 SwiftUI 组件。例如：选择器统一使用 `Picker(.menu)`，不允许混用 `Menu` 实现同功能——不同组件的渲染管线不同（SF Symbol vs 系统矢量），会导致字号、颜色、间距不一致，且无法通过调参对齐。

## 构建与测试策略

- 任何代码修改后，必须对 iOS 和 macOS 两个目标都进行构建，然后才能声明工作完成。绝不要假设一个平台构建成功就意味着另一个也没问题。
- 修改共享的 service/model/budget 逻辑后，在 iOS 上运行单元测试（XCTest）。注意 macOS 上 Swift Testing 并行执行不稳定的问题——建议 macOS 测试顺序运行。

## Build & Run

```bash
# Simulator build (use -jobs 4 + wholemodule for build stability)
# String Catalog (.xcstrings) compiled automatically by Xcode's xcstringstool
xcodebuild -project FirstCC.xcodeproj -scheme 钱伲 -destination "platform=iOS Simulator,name=iPhone 17" -derivedDataPath /tmp/firstcc-build -jobs 4 SWIFT_COMPILATION_MODE=wholemodule

# Device build (replace DEVICE_ID)
xcodebuild -project FirstCC.xcodeproj -scheme 钱伲 -destination "id=<DEVICE_ID>" -derivedDataPath /tmp/firstcc-build-device -jobs 4 SWIFT_COMPILATION_MODE=wholemodule

# Install to booted simulator
xcrun simctl install booted /tmp/firstcc-build/Build/Products/Debug-iphonesimulator/钱伲.app

# Launch simulator
xcrun simctl launch booted com.qianey.app

# Install to real device
xcrun devicectl device install app /tmp/firstcc-build-device/Build/Products/Debug-iphoneos/钱伲.app --device <DEVICE_ID>

# Launch real device
xcrun devicectl device process launch --device <DEVICE_ID> com.qianey.app

# List connected devices
xcrun devicectl list devices
```

## Test

| 平台 | 框架 | Target | Bundle ID |
|------|------|--------|-----------|
| Mac | Swift Testing | `QianeymacTests` (unit) + `QianeymacUITests` (UI) | `com.qianey.app.mac.QianeymacTests` |
| iOS | XCTest | `钱伲Tests` (unit) | `com.qianey.app.Tests` |

### Mac

```bash
# Run all tests (unit + UI)
xcodebuild test -project FirstCC.xcodeproj -scheme Qianeymac -destination "platform=macOS" -derivedDataPath /tmp/firstcc-test-build -jobs 4

# Run unit tests only
xcodebuild test -project FirstCC.xcodeproj -scheme Qianeymac -destination "platform=macOS" -only-testing:QianeymacTests -derivedDataPath /tmp/firstcc-test-build -jobs 4

# Run a single test (Swift Testing)
xcodebuild test -project FirstCC.xcodeproj -scheme Qianeymac -destination "platform=macOS" -only-testing:QianeymacTests/CurrencyFormatterTests/currencySymbol_CNY_returnsYenSign -derivedDataPath /tmp/firstcc-test-build -jobs 4
```

### iOS

```bash
# Run unit tests
xcodebuild test -project FirstCC.xcodeproj -scheme 钱伲 -destination "platform=iOS Simulator,name=iPhone 17" -only-testing:钱伲Tests -derivedDataPath /tmp/firstcc-ios-test -jobs 4

# Run a single test (XCTest)
xcodebuild test -project FirstCC.xcodeproj -scheme 钱伲 -destination "platform=iOS Simulator,name=iPhone 17" -only-testing:钱伲Tests/CurrencyFormatterTests/testCurrencySymbol_CNY_returnsYenSign -derivedDataPath /tmp/firstcc-ios-test -jobs 4
```

Target: `钱伲`, scheme: `钱伲`, bundle ID: `com.qianey.app`, container: `iCloud.com.qianey.v2`.

## Architecture

**Stack:** SwiftUI (iOS 26+) + CoreData (`NSPersistentCloudKitContainer`) + CloudKit. No third-party dependencies.

**DI pattern:** `AppContainer` is an `ObservableObject` injected as `@EnvironmentObject` at the app root. It holds `CoreDataStack` (which owns `NSPersistentCloudKitContainer`), all service instances, and `@Published var currentLedger: Ledger?`. Views read `appContainer.currentLedger` to determine the active ledger.

**Service layer:** Protocol-based. Every domain has `XxxServiceProtocol` + `XxxServiceImpl`. Services are instantiated in `AppContainer.init()`. They operate on `NSManagedObjectContext` (passed as parameter, never stored). All services are implemented: Ledger, Account, Transaction, Category, Template, Recurring, Member, Merchant, Project, Split, Budget, BankOCR, CreditCardStatement, Reconciliation, Currency, ExchangeRate, Export, Sync.

**Models:** `NSManagedObject` subclasses in `Models/CoreData/`. CoreData schema in `FirstCC.xcdatamodeld`. To add a new entity: create the `NSManagedObject` subclass, add the entity to `xcdatamodeld` in Xcode, and update `project.pbxproj`.

**Data flow:**
- `AppContainer.currentLedger` is the single source of truth for "which ledger is active"
- Dashboard refreshes on `Notification.Name.transactionDidChange` and `onChange(of: currentLedger?.id)`
- `UserDefaults.string(forKey: "currentLedgerID")` persists last-used ledger across restarts

### 代码架构规则

- 共享逻辑放在 Service 层，而不是 View 层。iOS 和 macOS 必须使用相同的 service 方法。
- 统一平台代码时，消除重复实现——一个共享的单一真相来源。
- 预算计算（总额、已用、剩余）必须使用单一过滤逻辑方法。多条计算路径曾导致支出差异 bug。
- 父子预算关系使用信封/子限额聚合模型。

## Platform Feature Parity

两个 target 共享同一套 Model/Service/Utility 层，但 View 层大多独立实现。修改任一平台功能时，**必须检查本表**确认另一个平台是否需要同步修改。

### 修改检查清单

改 iOS 功能 → 查 Mac 列是否独立实现 → 如是，检查 Mac 实现是否需要同步
改 Mac 功能 → 查 iOS 列是否独立实现 → 如是，检查 iOS 实现是否需要同步
改共享代码 → 两个平台同时受影响，两边都要测

| 功能模块 | iOS (钱伲) | Mac (Qianeymac) | 共享代码 |
|---------|-----------|----------------|---------|
| **总览/仪表盘** | `DashboardView` | `DashboardContentColumn` | `DashboardViewModel`, services |
| **账户列表** | `AccountListView` | `AccountListContent` | services |
| **账户详情** | `AccountDetailView` | `AccountDetailContent` | services |
| **新增/编辑账户** | `AddEditAccountView` | 复用 iOS（共享） | `AddEditAccountView` |
| **流水列表** | `TransactionListView` | `TransactionListContent` | `TransactionListOptions`, services |
| **流水详情** | `TransactionDetailView`→`AddEditTransactionView(displayMode:)` | `TransactionDetailContent`→`MacAddTransactionSheet(displayMode:)` | - |
| **记一笔** | `AddEditTransactionView` | `MacAddTransactionSheet` | services |
| **收支日历** | `CalendarStripView`+`CalendarDayCell` | 内置在 `TransactionListContent` | - |
| **报表** | `ReportsView`（3种：分类占比+成员维度、收支趋势、多维分析） | `ReportDetailContent`（6种：分类占比+成员维度、收支趋势、资产变化、预算执行、资产配置、多维分析） | `ReportViewModel` |
| **搜索** | `SearchView` | `MacSearchView`（toolbar 弹出） | `SearchViewModel`, `ChineseExpressionParser` |
| **高级搜索** | `AdvancedFilterPanel`（SearchView 内） | `MacAdvancedFilterView`（popover picker） | - |
| **设置主页** | `SettingsView` | `SettingsContent`+`SettingsWindow` | - |
| **账本列表** | `LedgerListSettingsView`（Settings 内） | `SettingsContent` 内 | services |
| **分类管理** | `CategoryListView`+`AddEditCategoryView` | `MacCategoryListView`+`MacCategoryEditSheet` | services |
| **成员管理** | `MemberListView` | `MacMemberListView`+`MacMemberEditSheet` | services |
| **商户管理** | `MerchantListView`（Settings 内） | `MacMerchantListView`+`MacMerchantEditSheet` ⚠️ 导航未挂载 | services |
| **项目管理** | `ProjectListView`（Settings 内） | `MacProjectListView`+`MacProjectEditSheet` ⚠️ 导航未挂载 | services |
| **周期账管理** | RecurringListView（Settings 内） | `MacRecurringListView`+`MacAddEditRecurringView` ⚠️ 导航未挂载 | services |
| **模板管理** | TemplateListView（Settings 内） | `MacTemplateListView`+`MacAddEditTemplateView` ⚠️ 导航未挂载 | services |
| **预算详情** | `BudgetBookDetailView` | `BudgetBookDetailMacView` | `AddEditBudgetItemView`, services |
| **预算列表** | `BudgetBookListView` | 复用（`#if os(macOS)` 条件编译） | `BudgetBookListView` |
| **新增/编辑预算** | `AddEditBudgetBookView` | 复用 iOS（共享） | `AddEditBudgetBookView` |
| **数据导出** | `ExportView` | `MacExportView` ⚠️ 导航未挂载 | `ExportServiceProtocol` |
| **共享管理** | `CloudSharingView`+`LedgerSettingsView` | `CloudSharingDelegate`+`ShareBadgeView`（toolbar） | `SyncServiceImpl`, `CloudKitShareCoordinator` |
| **信用卡对账** | `CreditCardReconciliationView` | 暂缓 | services |
| **分期管理** | `Installments/` 目录 | 不做 | - |
| **拆分交易管理** | `SplitDetailView`+`SplitEntryRowView`+`SplitFormView` | 内置在 `MacAddTransactionSheet` | - |
| **App 锁** | `AppLockView` | 不做（macOS 安全模型不同） | `BiometricAuth` |
| **Onboarding** | 已替换为仪表盘引导 | 已替换为仪表盘引导 | - |

> ⚠️ 标记的文件已实现但未挂载到 `MacLedgerDetailView` 导航中（仅链接了分类和成员管理），需要补充导航入口。

### 共享层（两个 target 都编译）

- **Models:** 所有 `Models/CoreData/*Entity.swift`、`Models/Enums/*.swift`
- **Services:** 所有 `Services/Protocols/`、`Services/Implementations/`
- **Design System:** `Font+Design.swift`、`Color+Design.swift`、`GlassModifiers.swift`
- **ViewModels:** `DashboardViewModel`、`SearchViewModel`、`ReportViewModel`、`AccountListViewModel`
- **Extensions:** `Date+Display`、`Color+Hex`、`Color+Expense`、`Transaction+Grouping` 等
- **Utilities:** `CurrencyFormatter`、`DateFormatters`、`ChineseExpressionParser`、`DiagnosticLog` 等
- **Components:** `CurrencyText`、`TransactionRowView`、`PixelProgressBar`、`NumpadAmountField`、`SearchablePickerView`、`DatePickerButton`

### 跨平台条件编译

共享文件中使用 `#if os(macOS)` / `#if os(iOS)` 处理平台差异：
- `BudgetBookListView.swift` — `EditButton`（iOS only）、`NavigationLink` 目标
- `Color+Design.swift` — 部分颜色微调
- `TransactionRowView.swift` — 部分渲染差异

### 添加新文件到 Mac target

Mac target 使用显式 Sources 列表（非自动同步）。新增共享文件时，需要同时加到 `project.pbxproj` 中 Mac target（`9AB5F8AC2FCD51C400F5044E`）的 Sources phase。

## Sharing (CKShare)

Sharing flow: owner taps Button → `createShareAndShow()` → `CoreDataStack.createShareForLedger()` → `CloudSharingView` (wraps `UICloudSharingController`).

`createShareForLedger` uses the standard approach:
```swift
container.share([ledger], to: nil)  // only pass root object, CoreData cascades to children
```
Do NOT use `CKShareTransferRepresentation` / `ShareLink` — that approach ties async share creation to the system share sheet lifecycle and is unreliable. Do NOT pre-create CKShare via raw CloudKit API — the two-step workaround was an over-engineering dead end.

30-second timeout via `withThrowingTaskGroup` protects against `container.share()` hangs (FB16908476).

`initializeCloudKitSchema()` is commented out in `loadStores()` — it caused iOS watchdog kills on DEV device builds. Only re-enable if schema changes in development and you need to push to CloudKit Development environment.

## Key Design Decisions

**Signed amounts:** `Transaction.amount` is `Decimal`, positive for income, negative for expense. UI uses `abs(amount)` with color (green/red) to distinguish direction.

**Transfer model:** Two linked `Transaction` records with opposite signs, linked by `transferGroupId`.

**Refund model:** A new Transaction with `refundGroupId` pointing to original, optionally `refundAmount` for partial refunds.

**Reimbursement:** `Transaction.reimbursementStatusRaw` (none/pending/approved/reimbursed) + `reimbursedById` linking settlement income back to expenses. Reports filter out both reimbursable expenses and linked settlement income.

**Member vs User:** "联系人" (model `Member`) are tags for splitting/lending — they don't have accounts. Shared users (CKShare participants) are a separate concept tracked via `User` entity.

**Settings structure:** Two-tier. SettingsView = app-level (ledger list, security, appearance). LedgerSettingsView = per-ledger config (accounts, categories, contacts, merchants, projects, templates, budgets, export).

## Patterns When Adding Features

**New management list view:** Follow the pattern in `AccountsManagementView` / `CategoryListView` — accept optional `ledger: Ledger?` with `effectiveLedger` computed property, use `onDismiss` on sheets to refresh, use `.task` for initial load.

**Sheet within a sheet:** Use `.task` not `.onAppear` for data loading — environment objects may not be ready in `.onAppear` for nested sheets. Call `loadData()` explicitly before setting picker sheet state.

**New service:** Add protocol in `Services/Protocols/`, implementation in `Services/Implementations/`, instantiate in `AppContainer.init()`.

**New model entity:** Add `NSManagedObject` subclass in `Models/CoreData/`, add entity to `FirstCC.xcdatamodeld` in Xcode, add files to `project.pbxproj`.

**Sharing changes:** Keep it simple. Use `container.share([rootObject], to: nil)`. Do not introduce raw CKShare APIs, `CKShareTransferRepresentation`, or multi-step workarounds unless proven necessary after exhausting all standard-API debugging (schema deployment, store state, actor isolation).

**New UI component:** Every distinct UI component gets its own file. Do not accumulate multiple independent views/subviews in a single file. If a view grows beyond ~150 lines or hosts multiple logical sub-components (ring-chart, bar-list, detail-list), split each sub-component into its own file in the same directory. The orchestrator view should be thin — compose components, manage state/animations, pass callbacks. Example: `MacCategoryChartView.swift` orchestrates `DonutChart.swift` + `CategoryBarList.swift` + `TransactionDetailList.swift`.

**Mac ScrollView + glassCard 布局规范（强制）：** 玻璃卡片在 ScrollView 内时，**水平 padding 必须放在 ScrollView 内部内容上，不能放在 ScrollView 本身**。ScrollView 默认裁剪内容，阴影需要 24px 呼吸空间。同时必须加 `.scrollClipDisabled()` 防止 SwiftUI 裁剪阴影。标准模板：

```swift
ScrollView {
    VStack(spacing: 8) {
        ForEach(items) { item in
            rowContent(item)
                .padding(.horizontal, 12)   // 内部间距先加
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)  // 约束宽度，防止 GeometryReader 撑开
                .glassCard(cornerRadius: 10)
        }
    }
    .padding(.horizontal, 24)  // ← 水平 padding 在内部内容上，不在 ScrollView 上
}
.scrollClipDisabled()  // ← 必须，防止 ScrollView 裁剪卡片阴影
.padding(.vertical, 12)
```

**错误示范（禁止使用）：**
```swift
// ❌ padding 在 ScrollView 上 → 内部无间距，阴影被裁剪
ScrollView { content }
    .padding(.horizontal, 24)
```

参考正确实现：`CategoryBarList.swift` → `MacCategoryChartView.swift`。

## 完成工作流

### 实现后检查清单

1. iOS 构建 ✅
2. macOS 构建 ✅
3. 运行单元测试 ✅
4. 通过并行 Agent 运行 `/simplify` 和代码审查 ✅
5. Git 提交 + 推送 ✅

不要跳过任何步骤——这是标准的完成工作流。

## Mac 报表架构

Mac 报表位于 `Qianeymac/Views/Reports/`，使用独立组件拼装（非复用 iOS 的 CategoryPieChartView）：

| 文件 | 职责 |
|------|------|
| `ReportContent.swift` | `ReportType` 枚举（6种）+ `ReportDetailContent` 容器，含 `reportPickerBar` 通用选择器 |
| `DonutChart.swift` | 饼图组件（`DonutChart`）+ 通用胶囊切换器（`GlassPillToggle`） |
| `CategoryBarList.swift` | 分类柱状列表（`CategoryBarList` + `CategoryBarRow`），支持成员子行 |
| `TransactionDetailList.swift` | 可复用交易明细列表（从 MacCategoryChartView 提取） |
| `MacCategoryChartView.swift` | 分类占比编排器：饼图+列表+成员维度切换（L1成员占比/L2成员拆分） |
| `MacTrendChartView.swift` | 收支趋势图 |
| `MacAssetChartView.swift` | 资产变化图 |
| `MacBudgetChartView.swift` | 预算执行图 |
| `MacAssetAllocationView.swift` | 资产配置图 |
| `MacDimensionChartView.swift` | 多维分析（商家/项目双维度），饼图+列表+下钻 |

**关键设计模式：**
- 饼图 + 列表的通用布局已提取为 `MacDimensionChartView.chartSection()` 私有方法
- 成员模式（`isMemberSplitOn`）在 `ReportContent` 生命周期钩子中统一重置（切换周期/报表/账本/交易时）
- 维度选择器使用 `GlassPillToggle` 同款胶囊玻璃风格，置于饼图卡片内左上角

## macOS/iOS 踩坑记录

### UI 血泪教训

- **macOS Swift Charts 崩溃**: macOS 上的 Swift Charts 在 `drawingGroup()`、`chartOverlay` 和 `SectorMark.cornerRadius` 上存在已知的 SIGTRAP/EXC_BREAKPOINT 崩溃。Mac 端图表优先使用原生 SwiftUI 渲染（`RoundedRectangle` 柱状图）。
- **分类缩进**: 层次化分类菜单使用 `NSMenuItem.indentationLevel`。禁止使用 padding/Spacer/attributedTitle——这些全都会失败。
- **CalendarDay ID**: 绝不要对日历日期标识符使用 `UUID()`——配合 `.onHover` 会导致无限重渲染循环。使用稳定的基于日期的 ID。
- **@State 字典变更**: 不要直接变更 `@State` 字典下标。SwiftUI 不会检测到变更。应创建新的字典副本。

## i18n / 多语言规范

**这是强制性规范。所有新增/修改代码必须遵循，不允许硬编码中文。**

### 基础

- 源语言：zh-Hans，翻译目标：en
- 文件：`FirstCC/Resources/Localizable.xcstrings`（String Catalog，编译时由 xcstringstool 自动处理）
- 不要手动创建 `.lproj` / `.strings` 文件 — xcstringstool 编译时自动生成

### 五种场景及处理方式

| 类型 | 场景 | 解决方案 |
|------|------|---------|
| **A** | `Text("中文")`、`Label("中文")`、`Button("中文")` 等 SwiftUI 字符串字面量 | SwiftUI 自动视作 `LocalizedStringKey`，只需在 Catalog 加条目 |
| **B** | `String` 变量/参数：`errorMessage = "中文"`、`return "中文"`、函数参数 `title: "中文"` | 用 `String(localized: "中文")` |
| **C** | 函数内 `Text(label)` 拿 `String` 变量显示 | `Text(LocalizedStringKey(label))` |
| **D** | 日期格式硬编码 | 用 `Date.FormatStyle` 自适应系统 locale |
| **E** | `enum` 的 `displayName` | `NSLocalizedString(rawValue, comment: "")` |

### Catalog 条目新增流程

1. 写完代码后，把新增的中文字符串加进 `Localizable.xcstrings`
2. 每个条目必须有 `zh-Hans`（源值）和 `en`（翻译值）
3. JSON 格式：
```json
"中文字符串": {
  "extractionState": "manual",
  "localizations": {
    "zh-Hans": {"stringUnit": {"state": "translated", "value": "中文字符串"}},
    "en": {"stringUnit": {"state": "translated", "value": "English Translation"}}
  }
}
```
4. 带插值的字符串：`String(localized: "每\(n)")` → Catalog key 为 `"每%lld"`（Int→%lld, String→%@）
5. 添加后验证：`python3 -c "import json; json.load(open('FirstCC/Resources/Localizable.xcstrings'))"`

### 噪音短语顺序（仅规则引擎相关）

`ChineseExpressionParser` 的 `noisePhrases` 数组中，**长短语必须排在短短语前面**（如 "多少钱" 在 "多少" 前面），否则长短语会被短匹配截断。

### 现有条目数

719 条目（zh-Hans + en 全覆盖）。
