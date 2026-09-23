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
| 影响上架的名称问题？ | iOS 的 `productName` / `CFBundleDisplayName` 仍是 **`荡漾计然`**，与 target `钱伲`、bundle id `com.qianey.app` 不一致 —— **待你定**（见 §二-5） |
| 测试规模？ | **343** 个用例（288 iOS XCTest + 42 Mac Swift Testing + 5 iOS UI + 8 Mac UI） |

---

## 一、完成度快照（2026-09-24 实测）

| 层 | 状态 | 依据 |
|---|---|---|
| 功能层 | **完整** | 18 个 `Services/Protocols/*.swift` + 22 个 `Implementations/*.swift`；Mac 6 大报表 12 个文件齐全（`Qianeymac/Views/Reports/`） |
| 测试层 | **343 用例** | 见 §七 复跑命令 |
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

### 4. i18n：332 条缺 `en`

- 1024 条中 **332 条没有 `en`**，其中 **313 条 `localizations` 完全为空**（既无 zh-Hans 也无 en）。
- 空条目的 key 多为符号/格式串（`''`、`' '`、`'–'`、`'%@年'`、`'%lld笔'`、`'↔'` …），
  但仍有 `'%@ 锁'`、`'%@:'` 这类**会显示给人看**的。
- ⚠️ **工作区正在继续增加空条目**：未提交的 `Localizable.xcstrings` 改动新增了
  `"你正在参与此共享账本，仅拥有者可管理成员"` 与 `"此账本已开启共享，其他用户可加入协作记账"`，
  两条的 `localizations` 都是**空的**。

### 5. 名称一致性 —— 🔴 **两个平台对外显示名都是 `荡漾计然`**（待你确认是否有意为之）

**构建产物实测**（不是读 pbxproj 推断）：

| | `CFBundleDisplayName`（设备上显示的名） | `CFBundleName` | Executable |
|---|---|---|---|
| iOS `钱伲.app` | **荡漾计然** | 钱伲 | 钱伲 |
| Mac `Qianey.app` | **荡漾计然** | Qianey | Qianey |

复跑：`/usr/libexec/PlistBuddy -c "Print :CFBundleDisplayName" <app>/Info.plist`

**根因**：`INFOPLIST_KEY_CFBundleDisplayName = "荡漾计然"` 设在 **项目级**
（`project.pbxproj:2075`，属项目级 Debug 配置 `F475504BEE6673842BA5B48F`），
**两个 app target 都继承它，且都没有覆盖**（全文件仅此一处 `CFBundleDisplayName`）。
另有 `productName = "荡漾计然"` 在 target 定义处（`:1110`，但 `productReference` 仍是 `钱伲.app`）。

**后果（两条，都影响上架）**：

1. **`5f74a0f` 改 Mac 名那轮其实没改到「显示名」。** 它把 `PRODUCT_NAME` 改成了 `Qianey`
   （影响 `.app` / executable / 模块名），但 Mac 上用户看到的名字仍是 `荡漾计然`。
   若那轮的目的是「让用户看到 Qianey」，则目标未达成。
2. **App Store Guideline 2.3.8 风险**：商店名（ASC Name）必须与**设备上显示的名字**相似。
   若 ASC Name 是 `钱伲` / `Qianey`，而设备名是 `荡漾计然`，就是 mismatch。
   另外 iOS 与 Mac 同账户**不能同名** —— 现在两边显示名**完全相同**（都是 `荡漾计然`），
   这一条也要一并考虑。

- → **需要你确认**：`荡漾计然` 是有意选的对外名，还是改名时漏掉的残留？
  确认后才知道该改哪一处（项目级 vs target 级 vs ASC）。
  **本轮只记录，未改动任何代码或工程配置。**

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
- **`.claude/agents/` 下的 `pbxproj-checker`**、`generate_xcodeproj.py` 的去留从未定论。

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

> ⚠️ **计数纪律（本项目踩过两次）**：数构建警告要用**主行去重**
> （`^/Users/…: warning:`），不要用「含某句话的日志行数」——每条警告有主行 + `| \`- warning:`
> 续行，总结阶段还会重复打印一次，行数必然虚高。

---

## 八、修订记录

- **2026-09-24** 建立。取代 `project_release_checklist` / `project_prerelease_review` 两份 2026-08 memory。
  全部条目重新实测；销掉 3 条假警报（隐私清单、账期 Picker、拆分统计），
  纠正 1 条渠道判断（Mac 公证不需要），新增 3 条本轮发现（素材全缺、
  货币码表三套、荡漾计然命名待定），并把 Swift 6 迁移等独立工程项归位到 §六。
- **2026-09-24 二次修正（用户指出）**：§三-7「Dashboard 预算概览」原被写为「未做」，
  实为**已落地**（预算概览两端都有），未做的只是「移除最近交易段」且已降为可选项。
  *教训：把「并存」误判成「未做」—— 判断某项做没做，要看目标功能在不在，而不是看旧状态还在不在。*
