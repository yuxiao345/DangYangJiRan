# 上架（App Store）清单

> **核实日期：2026-09-24。** 方法：三路并行只读盘点（代码层 / 配置与资产层 / 功能与 UI 层），
> 每条结论都附 `file:line` 或可复跑命令。**凡标「未核实」的，是旧记忆的断言，本轮没验。**
>
> **本文取代两份旧 memory**（`project_release_checklist`、`project_prerelease_review`）。
> 那两份是 2026-08 的核实，已多处过期，且互相矛盾 —— 例如一份说隐私清单「文件不存在」，
> 另一份说「已完成」。
>
> 相关：`.claude/research/swift6-migration-coredata-model.md`（Swift 6 迁移）、
> `.claude/research/mac-reporting-plan.md`（Mac 报表）、`CLAUDE.md`。

---

## 〇、结论卡片（先读这 6 行）

| 问题 | 结论 |
|---|---|
| 上架**真正**卡在哪？ | **不是代码，是素材。** 截图 / 描述 / 关键词 / 隐私政策 URL **一个都没有**，无 fastlane |
| 代码层最大的真缺口？ | **报销不支持部分冲销**（`Transaction` 无 `reimbursedAmount`，两平台都是全额标记） |
| 旧清单里哪些是假警报？ | **账期 Picker 18/20/25 已不存在**（早已改成完整的 1…28 / 1…31）；隐私清单已完成且合法 |
| 分发渠道定了吗？ | Mac 走 **App Store / TestFlight**（已被拒过一次，罪名是名称含 "Mac" 商标，`5f74a0f` 已修）→ **不需要公证** |
| 名称会不会影响上架？ | **不会。** `荡漾计然` 只写在 Debug 配置里，Release 产物无该键 → 设备显示名 = `钱伲`（Mac `Qianey`），与商店名一致（Debug/Release 各实测一次，见 §二-5） |
| 测试规模？ | **343** 个用例（288 iOS XCTest + 42 Mac Swift Testing + 5 iOS UI + 8 Mac UI） |

---

## 一、完成度快照（2026-09-24 实测）

| 层 | 状态 | 依据 |
|---|---|---|
| 功能层 | **完整** | 18 个 `Services/Protocols/*.swift` + 22 个 `Implementations/*.swift`；Mac 6 大报表 12 个文件齐全（`Qianeymac/Views/Reports/`） |
| 测试层 | **360 用例 = 347 单测 + 13 UI** | 单测 **2026-09-24 实测全绿**：iOS `钱伲Tests` **305 执行（303 通过 + 2 跳过）/ 0 失败**，Mac `QianeymacTests` **42 通过 / 0 失败**。UI 13 个（`钱伲UITests` 5 + `QianeymacUITests` 8）**本次未跑**。剩余 2 个跳过项与已修项见 §六-6 |
| 本地化 | **1024 条，332 条缺 `en`** | `FirstCC/Resources/Localizable.xcstrings`（12932 行）—— 注意该文件是 **12932 行 / 1024 条**，CLAUDE.md 里「约 11750 行」已过期 |
| CI | **有，但只测不发布** | `.github/workflows/test.yml` 只跑 `xcodebuild test`，无 archive/export/release job。另有 **Xcode Cloud 已配置但未纳入 git**（`FirstCC.xcodeproj/xcshareddata/xcodecloud/manifest.json`，未跟踪） |
| 发布层 | **素材 0%、签名待调** | 见 §二 |

---

## 二、P0 —— 上架阻断项

### 1. App Store 素材（**全缺**）

| 项 | 实测状态 |
|---|---|
| 截图 | **无。** 仓库里的 PNG 全是设计稿（约 500–780 × 1600）或 1024 图标，**没有一个商店规格** |
| description / keywords / what's new | **无任何文件**（无 `Description.txt`、无 `metadata/`） |
| 隐私政策 URL | **无。** 全仓库搜 `privacy` / `隐私政策` 只命中 `// MARK: - Privacy Placeholder Dot` 注释，App 内没有任何政策链接 |
| fastlane | **无**（无 `Fastfile`/`Deliverfile`/`Appfile`，无 `fastlane/` 目录，无任何 fastlane 工具引用） |

> 注：截图规格按 2026 的 App Store Connect 要求给（iPhone 6.9"，Mac 用 `macOS` 规格）；
> **不要**照抄旧清单里的「6.5"/6.7"」。

### 2. Mac 分发签名与推送环境

| 项 | 实测值 | 问题 |
|---|---|---|
| `CODE_SIGN_IDENTITY`（Qianeymac） | `"Apple Development"` | 应为 `Apple Distribution` 才能出正式包 |
| `PROVISIONING_PROFILE_SPECIFIER`（Qianeymac） | `""`（空串） | 空值 + Automatic 签名，正式归档前须确认 |
| `aps-environment`（Qianeymac.entitlements） | **硬编码 `development`** | iOS 走 `$(APS_ENVIRONMENT)` 会切 production，**Mac 不会** —— 生产包会带着开发推送环境 |
| `ENABLE_HARDENED_RUNTIME` | `YES` ✅ | 已开，无需动 |
| iOS `aps-environment` | `$(APS_ENVIRONMENT)`（Debug=development / Release=production）✅ | 正常 |

### 3. 报销不支持部分冲销（**核心业务 bug，真缺口**）

- `Transaction` **没有** `reimbursedAmount` 字段（全仓库 grep 无命中）。现有字段只有
  `reimbursementStatusRaw`（`TransactionEntity.swift:21`）与 `reimbursedById`（`:22`）。
- 关联函数是**全额标记**，且**不在 Service 层**，而在两个 View 里：
  - iOS `AddEditTransactionView.swift:2586` `linkReimbursedExpenses(to:)`
  - Mac `MacAddTransactionSheet.swift:1504` `linkReimbursed(txID:)`
  - 两者都只做 `exp.reimbursementStatus = .reimbursed; exp.reimbursedById = ...`，**不记金额**。
- 收入金额是自动取所选待报销支出的**全额之和**（iOS `:2571`、Mac `:970`/`:1323`）。
- **三个坏场景**：① 一笔大额支出分次报销 → 第一笔收入就把整笔标成已报销；② 金额不一致
  （记 900 只报 890）→ 差额永久挂在 pending，没有「差额弃权」出口；③ 多笔支出合一张报销单 → 当前 OK。
- 改造方向：加 `reimbursedAmount`（参考借贷的 `settledAmountInFen` 分次冲销模型）+「差额弃权」终态。
- 📌 **同一片区的另一个线索**：删除「已报销支出」时的级联删除断言曾被 `XCTSkipIf(true)` 关掉，
  2026-09-24 复核确认**级联本身是好的**（是测试断言写错，见 §六-6）——**本项（部分冲销）仍是真的缺口**，
  两者不是一回事。

### 4. i18n：332 条缺 `en`

- 1024 条中 **332 条没有 `en`**，其中 **313 条 `localizations` 完全为空**（既无 zh-Hans 也无 en）。
- 空条目的 key 多为符号/格式串（`''`、`' '`、`'–'`、`'%@年'`、`'%lld笔'`、`'↔'` …），
  但仍有 `'%@ 锁'`、`'%@:'` 这类**会显示给人看**的。
- ⚠️ **工作区正在继续增加空条目**：未提交的 `Localizable.xcstrings` 改动新增了
  `"你正在参与此共享账本，仅拥有者可管理成员"` 与 `"此账本已开启共享，其他用户可加入协作记账"`，
  两条的 `localizations` 都是**空的**。

### 5. 名称一致性 —— ✅ **上架包没问题**（Debug 的 `荡漾计然` 是**有意保留的开发版标识**）

**构建产物实测（Debug 与 Release 各打了一次，实测不是推断）：**

| 配置 | 产物 | `CFBundleDisplayName` | `CFBundleName`（系统回落） |
|---|---|---|---|
| **Release**（= TestFlight / 归档 / 上架） | `钱伲.app` | **（无该键）** | **钱伲** ✅ |
| Debug（= 本机开发装机） | `钱伲.app` | `荡漾计然` | 钱伲 |

**根因**：`INFOPLIST_KEY_CFBundleDisplayName = "荡漾计然"` 在 `project.pbxproj` 里**只有一处**
（`:2075`），且落在**项目级 Debug** 配置里；**项目级 Release 没有这个 key**。
`GENERATE_INFOPLIST_FILE = YES` 且 `INFOPLIST_FILE = FirstCC/Resources/Info.plist`（签入的那份
**也没有**任何 `CFBundleDisplayName`/`CFBundleName` 键），所以 Release 产物就是没有这个键 →
系统回落到 `CFBundleName` = `钱伲`。

**结论：不改它，对上架零影响。** 设备显示名（Release）就是 `钱伲`，与应用内 UI 一致
（`AppLockView.swift:23`、`OnboardingView.swift:15`、`SettingsContent.swift:342` 都显示「钱伲」），
也符合 Guideline 2.3.8（商店名须与设备显示名相似）。两个平台各自的显示名不同名
（iOS `钱伲` / Mac `Qianey`），所以「同账户 iOS/macOS 不能同名」也不触发。

**Debug 与 Release 故意不同名（2026-09-24 用户确认）**：在本机**同一台设备**上同时装开发版和
上架版做对照测试，靠桌面图标名一眼区分——**这是有意设计，不是残留**。所以
`project.pbxproj:2075` 那条 Debug 的 `CFBundleDisplayName = "荡漾计然"` **保持不动**。

**副作用（已知并接受）**：人工核对时若只看 Debug 包，会误以为上架版也叫这个名字
（**我自己就踩了这个坑**，见 §八）。判断上架行为必须打 Release 包。

**仓库卫生残留 —— 处置结果（2026-09-24）：**

| 位置 | 内容 | 处置 |
|---|---|---|
| `generate_xcodeproj.py` | 一次性工程生成器（target 名 `荡漾计然`，`PRODUCT_NAME = $(TARGET_NAME)`，全篇 0 处提到 `钱伲`；最后改动 2026-05-06） | ✅ **已删**（本 commit）。它已比真工程落后 4 个月，且跑一次会**覆盖 `project.pbxproj`、造出没有「钱伲」target 的工程** —— 留着纯是陷阱 |
| `project.pbxproj.backup.20260524_115209`<br>`project.pbxproj.backup.phase3` | 两份 2026-05 的 pbxproj 快照 | ✅ **已删**（本 commit）。实测 `project.pbxproj` 里 **0 处引用**，Xcode 不读、构建不碰 |
| `project.pbxproj:2075` | Debug 的 `CFBundleDisplayName = "荡漾计然"` | ⛔ **保留**（见上文，用户有意设计） |
| `project.pbxproj:1110` | `productName = "荡漾计然"` | ⛔ **保留**。惰性字段：实际产物名由 `PRODUCT_NAME` 决定（Debug/Release 实测产物均为 `钱伲.app`），`productReference` 也是 `钱伲.app`。动它要改真工程文件，零收益 |
| `Localizable.xcstrings` 条目 `荡漾计然`（en=`FirstCC`） | Swift 代码 0 处引用的孤儿条目 | ⛔ **保留**。证实它**不产生任何效果**（仓库里没有 `InfoPlist.xcstrings`，Debug 显示荡漾计然是 pbxproj 字面写死的，与 Catalog 无关）；而 `Localizable.xcstrings` 当时正带着无关的未提交改动，不该混改 |
| `.claude/settings.local 2.json:10` | 权限条目 `Bash(python3 …/generate_xcodeproj.py)` | ⚠️ **未动**（权限文件，等用户指示）。脚本已删，该条目现在指向不存在的文件、成为死条目。**另注**：这个带空格的 `settings.local 2.json` **被 git 跟踪了**，通常 `settings.local` 属本地文件，是另一处卫生问题 |

→ **这一项不需要为「上架」做任何事。** 上表纯属仓库卫生，已按用户指示清理完毕。

### 6. Mac HIG 审查（**未核实**）

- 旧记忆（2026-08）断言「7 个界面 0% 审查，属上架前必修」。**本轮没有验证完成度**，
  证据也不足以从代码判定。
- 已确知相关的**局部**工作曾发生：`4233a44`（补 macOS GUI 必需 Info.plist 字段）、
  `d366a32`（Mac 报表硬编码字号收敛到设计系统）、`8a6a7a5`/`4772038`（Apple Design + Reduced Motion）、
  `eeb3a96`（`dashboard_higCompliance` 测试「改为轻量级验证」）。
- → **待确认**：这个「P0」是仍旧成立，还是已被上述工作消化。建议先跑一遍人工 HIG 走查再定。

---

## 三、P1 —— 重要但不阻断上架

| # | 项 | 实测状态 |
|---|---|---|
| 7 | **UX 调整：Dashboard「最近交易」→「预算计划概览」** | **预算概览部分 ✅ 已完成**（用户 2026-09-24 确认，本轮复核一致）：iOS `Views/Main/DashboardView.swift:43` 的 `budgetCard`（identifier `dashboard-budget-card`）；Mac `DashboardContentColumn.swift:248-285` 的 `budgetSummaryCard` + `burnRateCard`（消耗速率）+ `categoryOverviewCard`（支出分类）。**只剩「是否移除最近交易段」这一步没做** —— 两平台仍并存「最近交易」（iOS `:49`、Mac `:570`）→ **降级为可选项**，因为预算概览已到位，原来「信息重叠」的动机已不成立 |
| 8 | **崩溃监控** | **完全没有**（`MetricKit`/`MXMetricManager`/`Crashlytics`/`Sentry`/`Firebase`/`Bugsnag` 全仓库 0 命中） |
| 9 | TestFlight 内部测试 | **进行中**：Mac 版曾被 App Review 拒（Guideline 5.2.5，名称含 Apple 商标 "Mac"），`5f74a0f` 已改为 `Qianey` → **需重新归档上传**，并复核版本元数据里不含 "Mac"、含 `Qianeymac` 的旧截图重拍 |
| 10 | Mac 公证 | **不需要**——Mac 走 App Store 分发，不是 Developer ID 直发。旧清单把它列成 P1 是渠道判断错误。（若将来改为独立分发，再补 notarytool + stapler） |

---

## 四、P2 —— 上线后

| # | 项 | 实测状态 |
|---|---|---|
| 11 | **Widget / Live Activity / Apple Watch** | **完全没有。** 全仓库 0 命中；工程共 6 个 target（2 app + 4 测试），**无任何 extension target**。（注：`FirstCC/AppIntents/` 是进程内 App Intents，不是 widget） |
| 12 | **可访问性审计** | **部分做了。** 见下方细分 |
| 13 | iOS HIG 一致性审查 | 未核实（旧清单项，沿用） |

**可访问性实测细分**（113 个视图文件：iOS 66 + Mac 47）：

| 维度 | 状态 |
|---|---|
| VoiceOver 标签 | ✅ 部分：`accessibilityLabel` 74 处 / 36 文件；`accessibilityIdentifier` 57 处 / 21 文件 |
| `accessibilityHint` | ⚠️ 仅 **1 处**（`CalendarDayCell.swift:89`） |
| `accessibilityValue` / `accessibilityHidden` | ❌ **0** |
| **Dynamic Type** | ❌ **基本为零**：`dynamicTypeSize` 0、`UIFontMetrics` 0、`@ScaledMetric` **仅 1 处**（`CurrencyText.swift:16`） |
| Reduce Motion | ✅ 6 个文件（Dashboard + 各图表） |
| Reduce Transparency / Differentiate Without Color | ❌ **0** |

> `MacDashboardUITests.swift:10` 有一句注释「macOS 视图尚未补 accessibilityIdentifier」——**已过期变假**，
> Mac 视图实际已大面积补上（`MainSplitView`、`DashboardContentColumn`、`AccountListContent`、
> `MacSearchView`、`TransactionListContent`、`AccountDetailContent`、`MacAddTransactionSheet` 等）。

---

## 五、✅ 从旧清单销掉（本轮已核实完成 / 是假警报）

- **iOS Privacy Manifest** ✅ 完成。`FirstCC/Resources/PrivacyInfo.xcprivacy` 存在，内容合法
  （只有 `NSPrivacyTracking=false` + `NSPrivacyAccessedAPICategoryUserDefaults`/`CA92.1`），
  且**同时是 iOS 与 Mac 两个 app target 的 Resources 成员**。
  来历：`f37b6e6` 创建 → 首版 key/value 是编造的导致 ITMS-91055/91056 被拒 → `3de9a6c` 修正。
  ⚠️ 遗留：`project.pbxproj` 里有**两份 `PBXFileReference` 指向同一路径**，其中一份是
  「Resources」组下的悬空引用（未被任何 build phase 使用，实际用的是「Recovered References」组那份）—— 建议清理。
- **账期 Picker 18/20/25** ✅ **不存在**。实测已是完整的 `ForEach(1...28)`（账单日）/
  `ForEach(1...31)`（还款日），默认 `billingDay = 1`、`dueDay = 5`
  （`AddEditAccountView.swift:133-142`、`AccountsManagementView.swift:245-254`、`MacAccountEditSheet.swift:36-37`）。
- **拆分交易统计** ✅ 口径正确（详见 §六-2 的谓词说明）。
- **Mac 6 大报表** ✅ 齐全。
- 其余已完成的基建：iCloud/APS/ubiquity entitlements 双平台就位；iOS 18.0+ / macOS 26.5+
  deployment target 就位；无第三方依赖（已核实：无 `Package.swift`/`Podfile`/`Cartfile`，
  pbxproj 里 SPM 依赖块全空）。

---

## 六、独立工程项 / 未决项（**不在上架路径上**，但别忘）

### 1. Swift 6 迁移 —— 6 个阻断项

清单与根因见 `.claude/research/swift6-migration-coredata-model.md` §3.5。
**Mac 5 个** `#NonSendableInAsyncConformanceOrOverride`（全部由 Mac target 独有的
`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` 引起）+ **iOS 1 个**（测试里跨隔离访问
`SharedLedgerImportService.shared`）。**Mac 那 5 个要先决定那个编译开关怎么收场，是设计决策。**
另：`#UnavailableSendableConformance` 计数不可复现（3 vs 5），归入待查。

### 2. 拆分统计的两套谓词（**已核实，不是 bug，但极易误改**）

两者**不等价**，各有各的用途，**不要互相替换**：

| 谓词 | 用在哪 | 语义 |
|---|---|---|
| `parentTransaction == nil` | **列表类**：`TransactionServiceImpl.fetchTransactions:120`、`AccountServiceImpl:49,71`、`ReconciliationServiceImpl:18`、`CreditCardStatementServiceImpl:54`、`AccountDetailView:214`、`AccountDetailContent:149`、`CreditCardReconciliationView:218,639` | 列表只显示父交易、**排除全部子项** |
| `isSplitParent == false` / `!isSplitParent` | **统计类**：`BudgetServiceImpl.fetchExpenseTransactions:233-239`（预算统计的唯一查询引擎）、`ReportViewModel:590,639,763,1331,1493,1669`、`DashboardViewModel:231-236` | 排除父交易、**计入子项**（父金额 = 子项之和，双计就翻倍） |

### 3. 🔴 成员分摊交易从预算/报表整体消失（用户 2026-09-15 决定暂缓，**仍存在**）

- `SplitServiceImpl.swift:28` 把原交易标成 `isSplitParent = true` 并创建 `SplitGroup` + `SplitEntry`，
  **但不创建任何子交易** → 统计用的 `isSplitParent == false` 把它整个排除，且没有子项顶替 → **整笔消失**。
- 根因：**两套「拆分」共用一个 `isSplitParent` 标记但语义不同**（一个靠子项代表金额，一个没有）。
- 修法二选一：给成员分摊用独立标记，或把统计判断从 `isSplitParent` 改成 `hasSplitChildren`。
- **同一决定还挂着一个产品问题**：该功能可发现性极低 —— 创建入口全 App **只有 1 处**
  （`AddEditTransactionView.swift:604`，四层深），**没有任何分摊列表**，且**Mac 端 0 处引用**。
  用户原话「你不说，我都忘记还有成员分摊这个功能了」。方向：搁置 / 提升可发现性 / 下线。

### 4. CoreData 行不重绘（iOS 已修，**Mac 4 处未修**）

- 根因：`ForEach` 遍历 `[Transaction]`、keyed by 稳定 identity，而 `TransactionRowView`
  故意不是 `@ObservedObject` → 原地编辑同一实例后 identity 不变，SwiftUI 跳过重算。
- ✅ iOS 已修：`Views/Main/DashboardView.swift:26`（`@State recentRefreshVersion`）+ `:80`（`.id()`）+ `:497`（`&+= 1`）。
- ❌ Mac 未修：`DashboardContentColumn.swift:588`、`AccountDetailContent.swift:129`（连 `.transactionDidChange` 都没订阅，数据也 stale）、`MacSearchView.swift:270,277`、`TransactionListContent.swift:118`。
- 待决策：(a) `.id(version)` 样板逐个镜像；(b) 在共享的 `TransactionRowView` 里做一次自失效，一处修全部。

### 5. 其他暂缓项

- **iOS 选中态样式未统一**：实测仍有 **12 种**选中底色写法，跨 0.08/0.12/0.15/0.2 四档透明度，
  且 **两个绿色家族并存**：亮绿 `designPrimaryContainer`（#00d16b/#00ff7f）vs 深绿
  `designPrimary`/`designAccentGreen`/`designPrimaryFixedDim`（#006d35）。用户 2026-09-12 决定暂不动。
- **FAB 在 iOS 18–25 横向偏右 5pt**（实测），用户 2026-09-14 决定暂不修。
  看到 `padding(.trailing, 15)` 别当魔法数字改 20。
- **期间对比（本月 vs 上月/去年同期）** 暂缓（数据不足两年）。
- **拆分交易金额维度搜索** 明确不做（用户决定）。
- **货币代码列表三套并存**（本轮新发现，非旧清单项）：16 码表出现在 7 处
  （`AddEditAccountView:21`、`AccountsManagementView:5`、`AddEditTransactionView:116`、
  `CreateLedgerView:16`、`SettingsWindow:84`、`MacAccountEditSheet:35`、`MacAddTransactionSheet:451`），
  另有 8 码表（`LedgerSettingsView:37`）与 6 码表（`CreateLedgerMacSheet:14`、`CreateLedgerSheet`）。
  **同一个「选择货币」在不同页面给不同选项** —— 建议收敛到一处常量。
- **`钱伲UITests` 的 Release 配置 bundle id 是 `com.qianey.app.--UITests`**（`project.pbxproj:1713`），
  看着像模板残留拼坏（不随包分发，优先级低）。
- **`.claude/agents/` 下的 `pbxproj-checker`** 的去留从未定论。（原先并列的 `generate_xcodeproj.py`
  已于 2026-09-24 删除，见 §二-5。）

### 6. 两个被 `XCTSkipIf(true)` 挡住的断言 + 同类 `Decimal → Int64` 转换 —— ✅ **已全部修复（2026-09-24）**

2026-09-24 跑 iOS 单测实测：`288` 执行 / `284` 通过 / **4 跳过** / 0 失败。4 个跳过全是
**无条件** `XCTSkipIf(true, …)`。用户批准后把下面两处暂时去掉跑了一次（**跑完已完全还原，
两个测试文件与 HEAD 字节一致**），结论如下：

| 断言 | 位置 | 裁定 | 状态 |
|---|---|---|---|
| ① `SplitEntry.amountInFen` 应为 `3333`（100÷3） | `钱伲Tests/Unit/Services/SplitServiceTests.swift:60` | 🔴 **真 bug，根因已锁定** | ✅ 已修（跳过已删） |
| ② 删除已报销支出后关联收入应被级联删除 | `钱伲Tests/Unit/Services/TransactionServiceTests.swift:618` | ✅ **级联正常，是测试断言写错** | ✅ 已修（断言改写） |
| ③ 其余 12 处同写法的 `Decimal → Int64` setter | 6 个 model 文件 | 🟡 同模式隐患（① 之外的 11 处无覆盖） | ✅ 已修（统一走 helper） |

**修复方案（用户批准）**：新增共享 helper，13 处调用点全部改走它。

```swift
// FirstCC/Extensions/Decimal+Currency.swift（放在已有的 Decimal 扩展里，不新建文件
// —— 新建文件要改 6 处 pbxproj，而该文件当时带着无关的未提交改动，放已有文件里零 pbxproj 改动）
var fenValue: Int64 {
    var scaled = self * 100
    var rounded = Decimal()
    NSDecimalRound(&rounded, &scaled, 0, scaled < 0 ? .up : .down)
    return NSDecimalNumber(decimal: rounded).int64Value
}
```

**取「朝零截断」而非四舍五入**（用户选择「保持现状」）。实测对照，能精确表示的值新旧**逐一相同**，
故对存量数据无行为变更：

| 值 | 旧 `Int64(truncating:)` | 新 `fenValue` |
|---|---|---|
| `100/3` | **`0`** ❌ | `3333` ✅ |
| `-100/3` | **`0`** ❌ | `-3333` ✅ |
| `100/7` / `1000/3` | **`0`** ❌ | `1428` / `33333` ✅ |
| `300/3` | `10000` | `10000`（同） |
| `712.3456789` / `712.34` / `712` | `71234` / `71234` / `71200` | 同 |
| `1.005` / `2.675` / `-1.005` | `100` / `267` / `-100` | 同（**是截断不是四舍五入**：四舍五入会给 `101`/`268`/`-101`） |
| `-0.999` / `-0.001` / `0` | `-99` / `0` / `0` | 同 |

⚠️ **`Decimal.RoundingMode` 没有 `.floor`**（只有 `.plain`/`.down`/`.up`/`.bankers`），
且 `.down` 是**朝 −∞**、`.up` 是**朝 +∞** —— 名字反直觉，朝零截断只能写 `v < 0 ? .up : .down`。

**验证**（**该 commit 当时的数字**；同一分支后续又改了 `.equal` 余数与 `applyCurrency`，
当前数字见 §六-8 末尾）：iOS 单测 `300` 执行 / `298` 通过 / `2` 跳过 / `0` 失败
（284 基线 + 2 条取消跳过转绿 + 12 条新增 `fenValue` 用例）；Mac `42/42`。新增 `钱伲Tests/DecimalCurrencyTests.swift` 专门锁
`fenValue` 的截断语义与「除不尽不再是 0」这两件事（③ 的 11 个无覆盖调用点靠它兜）。

#### ① 真 bug：除不尽的 `Decimal` 会让金额变成 **0** —— ✅ 已修

实测失败：`XCTAssertEqual failed: ("0") is not equal to ("3333")`。
根因**不在 service 逻辑，在 `Decimal → Int64` 的转换**：

```swift
set { amountInFen = Int64(truncating: (newValue * 100) as NSDecimalNumber) }   // ❌ 高精度时返回 0
```

→ **`Int64(truncating: NSDecimalNumber)` 对高精度小数返回 0**；凡是 `Decimal` 除法除不尽
（`Decimal` 最多 38 位、除不尽时填满精度）都会中招。**能整除就正常**，这正是它长期没被发现的
原因 —— 同文件的 `test_createSplit_equal_dividesEvenly`（300÷3）一直是绿的。数值对照表见本节顶部。

- **影响面**：`SplitServiceImpl.createSplit:33` 的 `.equal` 模式（`totalAmount / Decimal(members.count)`）
  → **AA 分账只要除不尽，所有人的分摊金额都是 0**。`.percentage`/`.fixed` 用的是外部传入金额，
  若调用方自己算过除法也会中招。
- **已修**：13 处调用点全部改走 `Decimal.fenValue`（定义见本节顶部）。`SplitServiceTests.swift:60`
  的 `XCTSkipIf` 已删除，该用例现在转绿。
- ~~**有意不改**：AA 分账除不尽时的 `0.01` 余数**不分配**（各 3333 分，合计 9999 分）~~
  → **该遗留同日已修，见 §六-8-2。** 当时判它「是既有行为、项目自己的测试就断言 `3333`」，
  但漏看了 3333×3 = 9999 **补不齐总额**，于是 `settlementStatus` 永远到不了 `.settled`
  —— 那不是「保持现状」，是留了个坏掉的判据。**「测试也这么断言」不等于「这是对的」。**

#### ② 不是 bug：级联删除是好的，`isDeleted` 断言无效 —— ✅ 测试已修

去掉跳过后该断言确实失败（`income.isDeleted == false`），但**深挖发现是实现行为误导了测试**：

```
TEMP_DIAG after-delete incomeRows=0 expenseRows=0 incomeIsDeleted=false hasChanges=false
```

「按照 `id` 重新 fetch，两行都查不到了」+ `hasChanges=false` → **级联删除已经生效并落盘**。
`isDeleted` 之所以是 `false`，是因为 **它只在「删除尚未保存」期间为 `true`**：`deleteTransaction`
结尾执行了 `try context.save()`（`:289`），保存后对象转成 fault，`isDeleted` 便变回 `false`
—— 连它自己删掉的 `expense` 也报 `false`，这就是自相矛盾的信号。

> ⚠️ **本条曾错误归因，已更正**：初稿写的是「post 了 `.transactionDidChange` → context 被 `reset()`」。
> 实际 **全仓 `grep` 不到任何 `.reset()` / `refreshAllObjects()`**，该通知的消费方全是 SwiftUI
> `.onReceive` + 两个只断言「通知发了」的测试 observer。用临时探针实测（iOS 测试栈，全程不 reset）：
> `delete 后/save 前 isDeleted=true, hasChanges=true` → `save 后 isDeleted=false, isFault=true`。
> **真因就是 `save()` 本身。**
> *教训：结论碰巧对（「不能用 `isDeleted`」）不等于因果链对。给机制起名字之前先确认那个名字在代码里真的存在。*

- **已修**：断言改为「按 `id` 重新 fetch 应为 0 行」（新增私有 helper `transactionCount(id:)`），
  **并加了正向对照**（一条不该被删的交易 `count == 1`），避免两条 `== 0` 一起空过。
  删除**之前**先取出 `id` —— save 后对象转 fault，再读属性不安全（本轮诊断时曾因此崩掉 test host）。
  **不要用 `isDeleted`。**
- ⚠️ **原跳过字符串里方法名是错的**：写的是 `TransactionServiceImpl.deleteReimbursableExpense`，
  该符号**全仓库只在测试文件里出现、代码中不存在**（真名 `deleteTransaction`）。该错误字符串已随跳过一并删掉。
- **本轮未动**：另外 2 处同源的跳过（`ExportServiceTests.swift:228`、`:263`）其实不是 `XCTSkipIf`，
  而是把测试**改名成 `disabled_…`** 退出收集，里面的 `throw XCTSkip` 是永不执行的死代码 ——
  这也是「6 处 skip 语句 vs 只报 4 个 skipped」的由来。
  **`disabled_` 前缀等于静默删除测试**，属于另一类卫生问题，未获批准故未处理。

### 7. `ExportServiceTests` 的一对 `disabled_` 测试静默消失（**独立修复项，用户 2026-09-24 指定单独做以留痕**）

| 项 | 内容 |
|---|---|
| 位置 | `钱伲Tests/ExportServiceTests.swift:227`（CSV）、`:262`（JSON） |
| 症状 | 测试名带 `disabled_` 前缀 → **退出 XCTest 收集**，永远不会被跑到；而函数体首行又是 `throw XCTSkip(...)`，**永不执行的死代码**。等于**双重失效**，两个测试静默消失 |
| 跳过理由 | ❌ **误归因**：写的是「`SplitServiceImpl` 创建 entry 后 `amountInFen` 被重置为 0（service bug）」。实际这两个测试用 `SplitEntry(amount: 200)` / `(amount: 100)` **直接构造**，200 和 100 乘 100 都是整数，旧 `Int64(truncating:)` 下本来就正确 —— 那个 bug **根本影响不到它们**。（它们自己的注释还写着「绕过 SplitService 的 entry amount bug」，是在绕一个不适用的 bug。） |
| ⚠️ 解封**预计是红的**，且原因与金额无关 | 该文件里 `SplitGroup(` 构造次数 **0**，而测试写的是 `entry1.splitGroup = tx.splitGroup` —— `tx.splitGroup` 是 nil，equals把 entry 挂在**空**上，导出很可能根本看不到这些 entry。所以这不只是「删掉前缀就行」，**测试本身是坏的**，需要建真的 `SplitGroup` 并正确关联 entry |
| 为什么单独做 | 修它 = 修测试本身，与 §六-6 的金额 bug 是两件事；用户指定单独立项，好在 git 上留痕 |

### 8. 收尾两件 —— ✅ **已修（2026-09-24，用户裁定「1、3 解决；2 放代办独立修」）**

#### 8-1. `applyCurrency` 是全项目最后一处没走 `fenValue` 的元→分换算

| 项 | 内容 |
|---|---|
| 位置 | `TransactionServiceImpl.swift` `applyCurrency`（旧第 370 行） |
| 旧写法 | `t.convertedAmountInFen = Int64((computed * 100 as NSDecimalNumber).doubleValue)` |
| 旧注释 | 「使用 Double 中间值避免 **Swift 6.3 / macOS 26 beta** 中 `NSDecimalNumber → Int64` 的高精度转换 bug」 —— ❌ **根因记错了**，真因是 `Int64(truncating:)` 的语义（§六-6 ①），与 Swift/macOS 版本无关 |
| 裁定 | **不是活跃 bug**（不会给出离谱的值），但**并非与旧写法逐位相同** —— 见下表的实测对照 |
| 它有四个真问题 | ① `Int64(Double)` 遇 `NaN`/`∞`/越界是 **fatal error（进程崩）**；`fenValue` 不崩，但**也别读成「正确」**——`Decimal.nan.fenValue` 返回的是**垃圾值**（实测 `4501261337`）而非 0；② 旧写法有**双重舍入**，实测会偏 1 分（见下表）；③ 上表那条错误注释把根因记成 Swift/macOS 版本 bug，会误导后人；④ 它是全项目唯一没走 `fenValue` 的元→分换算 |
| 已修 | `t.convertedAmount = t.amount * rate` —— 走 setter → `Decimal.fenValue`，注释重写为真因 |

**新旧写法实测对照**（金额 −1000.00…+1000.00 按分步进，共 200001 例 × 各 rate）：

| rate（来源） | 差异例数 | 举例 |
|---|---|---|
| `1.0` / `7.2451`（两位小数，Mac 路径常见） | `0 / 200001` | 完全一致 |
| `9.628999999999998` | `0 / 200001` | 完全一致 |
| `0.3333333333333333`（**iOS 路径**：`AddEditTransactionView` 用 `Decimal(string:)` 存 16 位有效数字的汇率，如 1/3） | **`12598 / 200001`（6.3%）** | amount `-983.04` × `1/3`：旧 **`-32768`** / 新 **`-32767`**；精确值 `-32767.9999999999967232`，截断朝零 = `-32767` → **新值才是对的** |

⚠️ **所以这条不是纯空操作**：对上面那类 16 位有效数字的汇率，旧写法每 16 例就有 1 例偏 1 分，
新写法会**在下次保存时静默把已存的 `convertedAmountInFen` 纠正过来**（幅度 ≤1 分）。
方向是「变正确」，但**是一处会动到存量数据的改动**，别当成纯重构。

- **`.else` 分支的 `t.convertedAmountInFen = 0` 有意保留**：与 setter 写 0 完全等价
  （`Decimal(0).fenValue == 0`），改它只扩大 diff，无行为差异。
- **`t.exchangeRate = Double(truncating: ...)` 有意不动**，且**不要**照着 §六-6 去批量改它。
  实测 `Double(truncating: NSDecimalNumber)` 与 `.doubleValue` 逐位一致，**没有**那个陷阱；
  坑只属于**整数版** `truncating:`（走 `int64Value`）。全仓 50+ 处 `Double(truncating:)`
  基本都是百分比/图表用途，属于另一类。**把 §六-6 的结论机械外推到它们身上会造成大范围无关改动。**

#### 8-2. AA 分账余数不分配 → `settlementStatus` 永远到不了 `.settled`

- **位置**：`SplitServiceImpl.createSplit` 的 `.equal` 分支（旧第 33 行 `totalAmount / Decimal(members.count)`）。
- **症状链**：¥100 分 3 人 → 各存 3333 分，**合计 9999 < 10000**
  → `SplitGroup.settlementStatus`（`totalPaid >= totalAmount`）**永不成立**
  → 全部付清也停在 `.partial`
  → `SplitDetailView:63` 的「一键结算」按钮门控正是 `settlementStatus != .settled`
  → **按钮永不消失**，且一直挂着 `remainingAmount` 算出的「剩余 ¥0.01」。
- **根因**：`totalAmount / Decimal(members.count)` 除不尽时 `Decimal` 会填满 38 位有效数字，
  每份再按分截断 → 每份都往下取 → 合计必然 **≤** 总额。§六-6 只修了「截断成 0」，
  这个「每份少一点点」还在。
- **修法（用户选 (a)：余数补给最后一名成员）**：新增
  `SplitServiceImpl.equalShares(totalAmount:count:)`，**先按分取整再均分**，
  余数（`< 人数` 分）补给最后一份 → `sum(entries.amountInFen) == totalAmountInFen` **恒成立**。
  ¥100 分 3 人 → `3333 / 3333 / 3334`。
- **顺带收掉两处同算法的不一致**（不一起收就是新的不一致）：
  - `SplitFormView` 的 `createSplit()` 曾自己算一份等分金额，而 service 对 `.equal` 根本不用它
    （传了也被丢弃）—— **两份算法并存**。现传 `nil`，算法只留在 service 一份。
  - 同文件的「均分金额」**预览**（旧 `:102`）是**第三份**除法，除不尽时会比实际入库少 1 分
    —— 现改为逐人列出，且直接调同一个 `equalShares`。
- **测试**：① 改 `test_createSplit_equal_unevenDivision_remainderGoesToLastMember`
  （断言 `3333/3333/3334`、按成员反查余数归属、`sum == totalAmountInFen`）；
  ② 新增 `test_settleSplit_unevenEqual_reachesSettled`（**症状回归锁**：`unsettled → partial → settled`）；
  ③ 新增 `test_equalShares_invariants_hold`（6 种人数 × 12 种总额的性质测试，含 0 人 / 0 元 / 负数）。
- ⚠️ **未覆盖 & 已知边界**（本轮有意不改）：
  - ✅ **同一症状在 `.percentage`/`.fixed` 下曾同样存在 → 已统一修掉**（审查发现，用户裁定「一起修」）。
    `equalShares` 只管 `.equal` 的**分配方式**；另外两种模式的金额来自调用方，
    每份各自按分截断后合计仍可能少于总额。实测（精确小数，33%/33%/34% **确实凑满 100%**，
    `isAmountValid` 拦不住）：

    | 总额 | 修前每份（分） | 修前合计 | 差 |
    |---|---|---|---|
    | ¥7.77 | 256 / 256 / 264 | 776 | −1 分 |
    | ¥0.10 | 3 / 3 / 3 | 9 | −1 分 |
    | ¥99.99 | 3299 / 3299 / 3399 | 9997 | **−2 分** |
    | ¥10.00 | 330 / 330 / 340 | 1000 | 0（恰好整除） |

    差额最大可达 **人数−1 分**。`.fixed` 同理：金额框是 `TextField(value:format: .number)`，
    解析出的 `Decimal` 是**精确**的（实测 `33.333` 就是 `33.333`），于是
    `33.333 + 66.667 == 100` 校验通过，按分截断后 3333+6666 = 9999 ≠ 10000。
    （2026-09-24 复核：审查指出该「实测」当时没有依据 —— 现补测，
    `TextField(value:format:)` 走 `Decimal.FormatStyle.number` 的 parseStrategy，
    实测 `Decimal("33.333", format: .number) == Decimal(string:"33.333")` 为真，
    且 `33.333 + 66.667 == 100` 精确成立，故这条成立。）
    **修法（已实施）**：新增 `SplitServiceImpl.balancedToTotal(_:totalAmount:)`，
    在 `createSplit` 的 switch **之后**统一调用一次 —— 把全部金额转成分、差额补到最后一份。
    三种模式**都**满足 `sum(entries) == totalAmount`；对 `.equal` 差值为 0，是空操作。
    代价（已知并接受）：`.fixed` 会**静默吸收**调用方的差额，
    即把「合计必须对」的保证从 UI 收进 service。
    **测试**：`test_percentage_unevenShares_sumEqualsTotal`（256/256/**265** + 付清到 `.settled`）、
    `test_fixed_subFenAmounts_sumEqualsTotal`（3333/**6667**）、
    `test_balancedToTotal_invariants`（5 组含空数组/负数/故意对不上，断言合计恒等于总额）。
    *⚠️ 复现时的坑：**必须用 `Decimal(string: "7.77")`，不能用 `Decimal(7.77)`** ——
    后者是 Double 字面量转换，实际是 `7.769999999999997952`，总额算出来是 776，
    会让探针误报「合计正好相等」。我第一次就踩了这个，差点把真缺口判成假警报。*
    *（这类发现说明「修一个症状」要顺着**同一个不变量**把所有产生它的分支都找一遍——
    只修 `.equal` 就是只修了 1/3。）*
  - 循环里的 `shares[index]` 在 **`amounts.count < members.count` 时会越界崩**；
    当前 View 恒按 `membersList` 生成等长数组，无调用方能触发，故未加防护。
  - **反向错配**（`amounts.count > members.count`）**不会崩，但静默失效**（审查实测）：
    差额补在 `amounts` 的**最后一个元素**上，而循环只写 `members.count` 份 ——
    多出的那份不会入库，差额就落空了，症状（`.settled` 到不了）原样复现。
    实测 `members = [M]`、`amounts = [1,2,3,4,5]`、`total = 100` → 写库 1 份 1.00 元。
    **改前改后暴露度相同**（旧代码同样只索引 `members.count` 次），故不是本次引入的回归。
    一处 `guard amounts.count == members.count else { throw SplitError.invalidAmounts }`
    可同时收掉正反两个方向 —— **未加，属独立决定**（见下条 overflow 同一性质）。
  - **doc 已相应收窄**：原先写「任何调用方（含将来的）都自动满足不变量」是**过度断言**
    （审查据此举出可复现反例），现明确写「仅在 `amounts.count == members.count` 时成立」。
- ⚠️ **新增了一条 Int64 溢出的 crash 路径（已实测复现，但论证为不可达 —— 未修，属独立决定）**：
  `balancedToTotal` 里新加了 `fen.reduce(0, +)` 与 `+=`，都是**检查型** Int64 运算。
  `Decimal.fenValue` 越界时**不回绕报错、也不饱和，而是回绕成垃圾值**（实测
  `Decimal(string:"1e30")!.fenValue == -8814407033341083648`），三个这样的值再相加 →
  `Swift runtime failure: arithmetic overflow`（trap）。改前**不崩**（每份各自换成分就存库，
  只是存了垃圾值）。**可达性论证（审查给出，我认同）**：`totalAmount` 来自
  `Transaction.amount`，其底层是 `amountInFen: Int64`，故
  `|总额| ≤ ¥92,233,720,368,547,758.07`；加上 View 的 `sum(amounts) == amount` 门控，
  `sum(fen) ≤ totalFen` 恒成立，部分和不会越界。**故应用内触发不到** ——
  但该函数是 `static` 且被文档当作通用不变量守卫，将来若有别的调用方就会踩到。
  可选处理：把 `+` / `-` 改成 `&+` / `&-`（与 `fenValue` 本身「回绕不报错」的语义一致，
  垃圾进垃圾出、不崩），或加金额上限校验。**均未实施。**
- ⚠️ **存量数据不回溯**：本次只影响**新建/重新保存**的分账。已经存在的除不尽分账仍是 9999/10000，
  仍卡在 `.partial`（点「一键结算」能标记全部已付，但状态显示不会变）。
  要不要照 `repairInvalidTypeFields` 的样子加一次回填修复（差值补给最后一名 entry），
  **未定，待用户裁定**。

**实测**：iOS `305` 执行 / `303` 通过 / `2` 跳过 / `0` 失败（本轮共 +5 条新用例）；Mac `42/42`；
双端构建 `BUILD SUCCEEDED`、0 error、0 条新警告。

---

## 七、核实方法与复跑命令

```bash
# 测试规模
grep -rnE --include="*.swift" "func test[A-Za-z0-9_]*\(" 钱伲Tests | wc -l      # 288
grep -rn  --include="*.swift" "@Test"                    QianeymacTests | wc -l # 42
grep -rnE --include="*.swift" "func test[A-Za-z0-9_]*\(" 钱伲UITests | wc -l    # 5
grep -rnE --include="*.swift" "func test[A-Za-z0-9_]*\(" QianeymacUITests | wc -l # 8

# 本地化
python3 - <<'PY'
import json; s=json.load(open("FirstCC/Resources/Localizable.xcstrings"))["strings"]
print("条目", len(s), "缺 en", sum(1 for v in s.values() if "en" not in v.get("localizations",{})))
PY

# 素材与配套
find . -name "*.xcprivacy" ; find . -type d -iname fastlane ; find . -iname '*.sh'
grep -rn "MetricKit\|MXMetricManager\|Crashlytics\|Sentry\|Firebase" --include="*.swift" .
grep -rn "notarytool\|stapler\|altool" . --include="*.sh" --include="*.yml" --include="*.py"
```

**跑测试并取权威计数（别数日志行）：**

```bash
# iOS 单测
xcodebuild test -project FirstCC.xcodeproj -scheme 钱伲 \
  -destination "platform=iOS Simulator,name=iPhone 17" \
  -only-testing:钱伲Tests -derivedDataPath /tmp/firstcc-ios-test -jobs 4

# Mac 单测
xcodebuild test -project FirstCC.xcodeproj -scheme Qianeymac \
  -destination "platform=macOS" \
  -only-testing:QianeymacTests -derivedDataPath /tmp/firstcc-test-build -jobs 4

# ✅ 权威计数（2026-09-24 起统一用这个，不要 grep 日志）
for d in /tmp/firstcc-ios-test /tmp/firstcc-test-build; do
  XC=$(ls -dt $d/Logs/Test/*.xcresult | head -1)
  xcrun xcresulttool get test-results summary --path "$XC" \
    | python3 -c "import json,sys; d=json.load(sys.stdin); print({k:d[k] for k in ('result','passedTests','failedTests','skippedTests')})"
done
```

**全量构建（干净 DerivedData，避免增量空跑冒充成功）：**

```bash
rm -rf /tmp/firstcc-build-full /tmp/firstcc-mac-build-full
xcodebuild -project FirstCC.xcodeproj -scheme 钱伲 \
  -destination "platform=iOS Simulator,name=iPhone 17" \
  -derivedDataPath /tmp/firstcc-build-full -jobs 4 SWIFT_COMPILATION_MODE=wholemodule build
xcodebuild -project FirstCC.xcodeproj -scheme Qianeymac -destination "platform=macOS" \
  -derivedDataPath /tmp/firstcc-mac-build-full -jobs 4 SWIFT_COMPILATION_MODE=wholemodule build
# 验证「真编了」：grep -cE "SwiftCompile" 应为数百，不是 0
```

> ⚠️ **计数纪律（本项目踩过三次）**：
> ① 数构建警告要用**主行去重**（`^/Users/…: warning:`），不要用「含某句话的日志行数」——
> 每条警告有主行 + `| \`- warning:` 续行，总结阶段还会重复打印一次，行数必然虚高。
> ② 数测试用例要用 **`.xcresult`**，不要 grep 日志 —— 日志行会被 stdout 交错截断。
> ③ 别把「增量空跑」当成功 —— `BUILD SUCCEEDED` 也可能是 0 个编译步骤，先看 `SwiftCompile` 计数。
> ④ 但 `SwiftCompile` 的**行数取决于编译模式**：iOS 那条命令带 `SWIFT_COMPILATION_MODE=wholemodule`，
> 整个模块一条命令、每架构一行 → **只有 2 行是正常的**；Mac 不加该 flag，走逐文件 → 数百行。
> **判真编没编，要看那一行里是否列出了你改的文件名，不是数行数。**
> （2026-09-24 本轮我自己又差点被 2 行误导一次，重新查证后才确认是真编译。）

---

## 八、修订记录

- **2026-09-24 八次修订**：§六-8 两件收尾（用户裁定「1、3 解决；2 放代办独立修」）。
  ① `TransactionServiceImpl.applyCurrency` 改走 `convertedAmount` setter（→ `fenValue`），
  并**纠正那条把根因记成「Swift 6.3 / macOS 26 beta bug」的注释**；
  ② 新增 `SplitServiceImpl.equalShares`，AA 分账除不尽的余数补给最后一名成员，
  使 `sum(entries) == totalAmount` 恒成立 —— 修掉「付清了却永远到不了 `.settled`、
  「一键结算」按钮永不消失」；连带收掉 `SplitFormView` 里的**两份重复等分算法**
  （一份被 service 丢弃、一份是会说谎的预览）。
  （本轮共新增 3 条用例，实测数字见本节末尾。）
  *教训*：**「项目自己的测试就断言 3333」不等于「3333 是对的」** —— 七次修订时我把
  「余数不分配」判成「保持既有行为」，漏看了 3333×3 = 9999 补不齐总额，那个判据从头就是坏的。
  另记一条**防止过度外推**：`Int64(truncating:)` 有坑，但 `Double(truncating:)` **没有**
  （实测逐位等于 `.doubleValue`），全仓 50+ 处 `Double(truncating:)` 不要照着 §六-6 批量改。
  **但「陷阱不在那个 API 上」不等于「换掉它是空操作」** —— 见下条。
  **审查纠出我两处过度断言，均已实测更正**（细节见 §六-8）：
  ① 我写「`Double(truncating:)` 没陷阱、现实输入下新旧一致」——**陷阱那句对，结论错**。
  旧写法是 `Int64(Double 中间值)`，多了一趟 Double 舍入；实测 iOS 路径那种 16 位有效数字的汇率
  （`AddEditTransactionView` 用 `Decimal(string:)`，如 1/3）下，金额扫 −1000.00…+1000.00
  **200001 例里 12598 例（6.3%）差 1 分**，且**新值才是正确截断**
  （`-983.04 × 1/3`：旧 `-32768` / 新 `-32767`，精确值 `-32767.9999…`）。所以这条改动
  **不是纯重构** —— 它会在下次保存时静默纠正存量 `convertedAmountInFen`（≤1 分，方向是变正确）。
  ② `equalShares` 的 docstring 原写「恒有 `sum(shares) == totalAmount`」——对 `count ≥ 1` 成立，
  对 `count == 0` 不成立（返回 `[]`，合计 0 ≠ 总额），已把范围写进注释。
  *教训*：**改一处换算，先量「新旧到底一不一样」，别用「这个 API 上没有那个陷阱」替代测量。*
  **审查还发现同一不变量只修了 1/3**：`.percentage`/`.fixed` 不经 `equalShares`，每份各按分截断，
  合计仍会少于总额（实测 ¥99.99 按 33/33/34 → `3299+3299+3399 = 9997` ≠ 9999，**差 2 分**），
  症状与 `.equal` **完全相同**：仍卡 `.partial`、「一键结算」按钮仍永不消失。
  **我先按规矩只记待办 + 一条刻画测试交用户裁定，用户当天裁定「一起修」，已实施**：
  新增 `SplitServiceImpl.balancedToTotal(_:totalAmount:)`，在 `createSplit` 的 switch **之后**统一调用，
  三种模式都满足 `sum(entries) == totalAmount`（对 `.equal` 差值为 0，是空操作）。
  原刻画测试改为正向断言（`test_percentage_unevenShares_sumEqualsTotal`，256/256/**265** 且付清到 `.settled`），
  另加 `test_fixed_subFenAmounts_sumEqualsTotal`（3333/**6667**）与
  `test_balancedToTotal_invariants`（含空数组/负数/故意对不上）。
  本轮共新增 5 条用例。实测：iOS `305` 执行 / `303` 通过 / `2` 跳过 / `0` 失败，Mac `42/42`，双端 `BUILD SUCCEEDED`。
  **双 agent 审查（简化/高度 + 正确性）后已应用**：
  ① 两条新用例原先只断言 `map(\.amountInFen).sorted()` —— 那是**多重集**断言，
  钉不住「差额落在输入顺序的最后一名」（`members` 与 `amounts` 是两个按下标对齐的数组，错位时照样通过）。
  已按姊妹用例的写法改成**按成员反查**（`members[2] → 265`、`m2 → 6667`）。
  ② `test_balancedToTotal_invariants` 删掉与 `test_fixed_subFenAmounts_sumEqualsTotal` 重复的一行；
  另一行的输入改成**真实百分比形状**（`32.9967 + 32.9967 + 33.9966 == 99.99`，即「输入合计精确、
  逐份截断丢 2 分」），原先那行（`32.99/32.99/33.99` 合计 99.97）其实是「调用方自己就凑不齐」，
  与注释引的例子不同源。
  ③ `equalShares` 的余数那一行**不是冗余**：`SplitFormView` 的「均分金额」预览直接调它、
  不经过 `balancedToTotal`，删掉预览会比入库少最多 人数−1 分 —— 审查结论与我的判断一致，未动。
  *简化建议里唯一被我否掉的一条*：让 `equalShares` 转调 `balancedToTotal` 以消掉那句重复的余数写法
  （审查实测 90/90 输出一致）—— 判为**过度间接**：为省一行重复写法换来一次数组往返 +
  「必须读另一个函数才知道不变量从哪来」，而现行写法 4 行自解释。
  **记入待决、未实施**（均为审查实测、当前不可达）：见 §六-8-2 的
  「`amounts.count > members.count` 静默失效」与「`fen.reduce` 的 Int64 溢出 crash」。
- **2026-09-24 七次修订（用户批准后落地修复）**：§六-6 的三项**全部修完**。
  ① 新增 `Decimal.fenValue`（朝零截断），**13 处** `Decimal → Int64` setter 改走它；
  ② `TransactionServiceTests` 的 `isDeleted` 断言改为「按 id 重新 fetch 为 0 行」，跳过删除；
  ③ 新增 `钱伲Tests/DecimalCurrencyTests.swift`（12 用例）锁住 `fenValue` 行为。
  实测 iOS `300` 执行 / `298` 通过 / `2` 跳过 / `0` 失败，Mac `42/42`，双端构建 `BUILD SUCCEEDED`。
  **复核还纠出我自己一处错误归因**：§六-6 ② 与 §八「六次修订」原写 `isDeleted` 变 false 是
  「context 被 `reset()`」所致 —— 全仓根本没有 `reset()`，实测真因就是 `deleteTransaction`
  结尾的 `save()`（`isDeleted` 只在删除待保存期间为 true）。三处注释/文档已一并更正，
  memory `reference_coredata_isdeleted_on_fault` 同步重写。
  *教训：结论碰巧对不等于因果链对。*
  **审查还点了两处未闭环（未动，待用户裁定）**：① `TransactionServiceImpl:370` 是全项目最后一处
  没走 `fenValue` 的元→分换算（用 Double 中间值，注释把根因误记成「Swift 6.3 beta 的 bug」，
  且 `Int64(Double)` 遇 NaN 是 fatal error 而 `fenValue` 不崩）；② `ExportServiceTests` 那对
  `disabled_` 测试的跳过理由同属误归因（它们用 `SplitEntry(amount: 200/100)` 直接构造，本就整除）。
  *两个值得记住的点*：**helper 放进了已有的 `Decimal+Currency.swift` 而不是新建文件** ——
  `FirstCC/Extensions/` 不在同步组里（同步组只覆盖 5 个目录），新建文件要手改 6 处 `project.pbxproj`，
  而那个文件当时带着**无关的未提交改动**，放已有文件里把「混提交」的风险直接消掉了；
  **`Decimal.RoundingMode` 没有 `.floor`**，且 `.down` 是朝 −∞、`.up` 是朝 +∞，名字反直觉，
  朝零截断只能写 `v < 0 ? .up : .down`。

- **2026-09-24** 建立。取代 `project_release_checklist` / `project_prerelease_review` 两份 2026-08 memory。
  全部条目重新实测；销掉 3 条假警报（隐私清单、账期 Picker、拆分统计），
  纠正 1 条渠道判断（Mac 公证不需要），新增 3 条本轮发现（素材全缺、
  货币码表三套、荡漾计然命名待定），并把 Swift 6 迁移等独立工程项归位到 §六。
- **2026-09-24 二次修正（用户指出）**：§三-7「Dashboard 预算概览」原被写为「未做」，
  实为**已落地**（预算概览两端都有），未做的只是「移除最近交易段」且已降为可选项。
  *教训：把「并存」误判成「未做」—— 判断某项做没做，要看目标功能在不在，而不是看旧状态还在不在。*
- **2026-09-24 三次修正（自查）**：§二-5 初稿断言「两个平台对外显示名都是 `荡漾计然`、
  会触发 2.3.8 拒审」——**这是错的，而且是我自己犯的**：我只打了 **Debug** 包就下了结论。
  实测 **Release 产物压根没有 `CFBundleDisplayName`**，设备显示名是 `钱伲`（Mac `Qianey`）。
  已整段重写。
  *教训：验「上架会怎样」必须用**上架用的那个 configuration**（Release），
  Debug 结论不能外推到 Release。项目里已有同类纪律（[[feedback_verify_api_by_compile_not_grep]]）。*
- **2026-09-24 六次修订（用户批准后做实验）**：把 §六-6 那两处 `XCTSkipIf(true, …)` 暂时去掉实跑，
  跑完**已完全还原**（两个测试文件与 HEAD 字节一致，已用 `git diff HEAD` 验证）。结论：
  **① 是真 bug（根因锁定，见 §六-6）、② 不是 bug（级联正常，是测试断言写错）**。
  *过程中一个值得记住的行为*：`deleteTransaction` 结尾 `save()` 之后，被删对象转为 fault，
  而 **`isDeleted` 此时是 `false`**（它只在「删除待保存」期间为 `true`）—— 我一开始把
  `income.isDeleted == false` 当成「没删除」的证据，差点把「测试写错」误记成「产品 bug」。
  改用「按 id 重新 fetch 应为空」才看清真相。
  *教训：判断「行没了没有」要查 store，不要问内存对象的 `isDeleted`。*
  （注：本条初稿把机制写成「context 被 `reset()`」，**是错的**，已在七次修订后续更正 ——
  全仓没有 `reset()`，真因只是 `save()`。见 §六-6 ② 的更正块。）
- **2026-09-24 五次修订（完整工作流复跑）**：按用户要求把工作流严格跑了一遍 ——
  ① **双端全量构建**均 `BUILD SUCCEEDED`（iOS 真编 320 个 `.swift`、Mac 359 个，0 error；
  警告 70 / 93 条，均既有、与本次清理无关）；② **单测全绿**（iOS 284 通过 / 4 跳过 / 0 失败，
  Mac 42 通过 / 0 失败）；③ 新增 **§六-6**：4 个被 `XCTSkipIf(true)` 无条件关掉的断言，
  其中 2 个指向 service 层（`SplitEntry.amountInFen` 写为 0；删除可报销支出的级联删除），
  **②的代码路径看起来已存在 → 跳过理由疑似过期**，且跳过字符串里的方法名
  `deleteReimbursableExpense` 在代码中根本不存在；④ §一 测试层补上实测分解（343 = 330 单测 + 13 UI）；
  ⑤ §七 补 `.xcresult` 权威计数与「干净 DerivedData」命令，计数纪律扩到三条。
  *教训（我自己犯的）*：本轮我一度用 `ls README*` 判断有无 CI，zsh 因「无匹配」中断整条命令，
  我据此向用户说「项目无 CI」—— **实为假阴性**，`.github/workflows/test.yml` 一直都在。
  *别用会因无匹配而中断的 glob 去证明「某物不存在」。*
- **2026-09-24 四次修订（用户裁定）**：§二-5 的「遗留残留」定案 ——
  ① Debug 显示名 `荡漾计然` **是用户有意保留的开发版标识**（同一设备对照测试时靠图标名区分），
  **不是残留，保持不动**；② `generate_xcodeproj.py` 与两份 `project.pbxproj.backup.*` **已删除**
  （前者查实含 0 处「钱伲」、跑一次会毁掉工程；后者在 pbxproj 里 0 引用）；
  ③ `productName` 与 Catalog 孤儿条目**保留**（惰性/无效果，动真工程文件零收益）。
