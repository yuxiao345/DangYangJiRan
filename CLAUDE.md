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

Target: `钱伲`, scheme: `钱伲`, bundle ID: `com.qianey.app`, container: `iCloud.com.qianey.v2`. No tests or linting configured yet.

## Architecture

**Stack:** SwiftUI (iOS 26+) + CoreData (`NSPersistentCloudKitContainer`) + CloudKit. No third-party dependencies.

**DI pattern:** `AppContainer` is an `ObservableObject` injected as `@EnvironmentObject` at the app root. It holds `CoreDataStack` (which owns `NSPersistentCloudKitContainer`), all service instances, and `@Published var currentLedger: Ledger?`. Views read `appContainer.currentLedger` to determine the active ledger.

**Service layer:** Protocol-based. Every domain has `XxxServiceProtocol` + `XxxServiceImpl`. Services are instantiated in `AppContainer.init()`. They operate on `NSManagedObjectContext` (passed as parameter, never stored). All services are implemented: Ledger, Account, Transaction, Category, Template, Recurring, Member, Merchant, Project, Split, Budget, BankOCR, CreditCardStatement, Reconciliation, Currency, ExchangeRate, Export, Sync.

**Models:** `NSManagedObject` subclasses in `Models/CoreData/`. CoreData schema in `FirstCC.xcdatamodeld`. To add a new entity: create the `NSManagedObject` subclass, add the entity to `xcdatamodeld` in Xcode, and update `project.pbxproj`.

**Data flow:**
- `AppContainer.currentLedger` is the single source of truth for "which ledger is active"
- Dashboard refreshes on `Notification.Name.transactionDidChange` and `onChange(of: currentLedger?.id)`
- `UserDefaults.string(forKey: "currentLedgerID")` persists last-used ledger across restarts

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
| **报表** | `ReportsView` | `ReportTypeContent`+`ReportDetailContent` | `ReportViewModel` |
| **设置主页** | `SettingsView` | `MacSettingsView` | - |
| **账本列表** | `LedgerListSettingsView` (in SettingsContent) | `MacLedgerSettingsView` | services |
| **分类管理** | `CategoryListView`+`AddEditCategoryView` | `MacCategoryListView`+`MacCategoryEditSheet` | services |
| **成员管理** | `MemberListView` | `MacMemberListView`+`MacMemberEditSheet` | services |
| **预算详情** | `BudgetBookDetailView` | `BudgetBookDetailMacView` | `AddEditBudgetItemView`, services |
| **预算列表** | `BudgetBookListView` | 复用（`#if os(macOS)` 条件编译） | `BudgetBookListView` |
| **新增/编辑预算** | `AddEditBudgetBookView` | 复用 iOS（共享） | `AddEditBudgetBookView` |
| **搜索** | `SearchView` | 未实现 | `SearchViewModel`, `ChineseExpressionParser` |
| **高级搜索** | `SearchView` (多条件) | 未实现 | - |
| **数据导出** | `ExportView` | 未实现 | `ExportServiceProtocol` |
| **App 锁** | `AppLockView` | 未实现 | `BiometricAuth` |
| **共享管理** | `CloudSharingView`+`LedgerSettingsView` | 未实现 | `SyncServiceImpl`, `CloudKitShareCoordinator` |
| **信用卡对账** | `CreditCardReconciliationView` | 未实现 | services |
| **商户/项目管理** | iOS Settings 内 | Mac 未实现 | services |

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

**New UI component:** Every distinct UI component gets its own file. Do not accumulate multiple independent views/subviews in a single file. If a view grows beyond ~150 lines or hosts multiple logical sub-components (ring-chart, bar-list, detail-list), split each sub-component into its own file in the same directory. The orchestrator view should be thin — compose components, manage state/animations, pass callbacks. Example: `MacCategoryChartView.swift` (85 lines) orchestrates `DonutChart.swift` + `CategoryBarList.swift` + `TransactionDetailList`.

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
