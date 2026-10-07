# 素材源截图

`make_banner.swift` 从本目录读取真机截图，命名规则是**两个变量拼出来的**：

```
中文：{基名}-{外观}.png
英文：{基名}-{外观}-en.png
```

`外观` = `dark` / `light`。缺文件时画占位块，不中断渲染（英文缺图会额外打一条告警并回落到中文）。

> ⚠️ **深色海报必须配深色截图，浅色海报必须配浅色截图。**
> 深色海报上贴浅色截图，手机上就是一块突兀的白；反之亦然。生成器不会替你检查这个。

## banner 当前用的两屏（共 8 个文件）

| 基名 | 内容 | 角色 |
|---|---|---|
| `14-addtx` | 记一笔（数字键盘，金额 128.50） | **主屏**（右侧靠前，完整可见） |
| `11-transactions` | 流水列表（含日历条） | **副屏**（左侧靠后，右缘被主屏压掉一部分） |

即这 8 个：`{14-addtx,11-transactions}-{dark,light}{,-en}.png`。

## 其余截图（banner 不用）

| 文件 | 内容 |
|---|---|
| `10-dashboard-{dark,light}{,-en}.png` | 总览页，4 张 |
| `12-reports-cat-{dark,light}{,-en}.png` | 报表·分类占比（周期「本月」，L1 不下钻），4 张 |
| `12-reports-trend-{dark,light}{,-en}.png` | 报表·收支趋势（周期「近1年」），4 张 |
| `12-reports-dim-{dark,light}{,-en}.png` | 报表·多维分析（「本月」+ 商家维度，L1 不下钻），4 张 |
| `13-accounts-{dark,light}{,-en}.png` | 账户列表，4 张 |
| `16-transactions-light.png` | 流水列表，浅色（与 `11-transactions-light.png` 同屏，冗余） |
| `17-budget-{dark,light}{,-en}.png` | 设置 → 账本设置 → 预算管理，4 张 |
| `ipad13/` 下 12 张（`10-dashboard`、`13-accounts`、`12-reports-cat` × 深浅 × 中英）| 13 英寸 iPad 专用，见下节 |

留着做 App Store **截图**素材时会用到。

> **报表与账户那 16 张是 2026-10-07 拍的**，旧的单张 `12-reports-dark.png` 已删除
> （它被 `12-reports-cat-dark.png` 取代）。
> 其中 **`12-reports-trend-*` 那 4 张当天又重拍过一次**：`ReportViewModel` 修掉了
> 月份轴依赖「年」字、以及横轴月份乱序两个 bug（commit `39a16ab`）。中文那 2 张的
> 月份顺序原本也是乱的，所以中英各 2 张一起重拍。
> **预算那 4 张也是 2026-10-07 补的**——之前只有英文版被重拍过（旧英文版标题还是中文
> 「预算管理」，因为当时 String Catalog 缺 `en`），中文那对是原先拍的、一直没入库。
>
> 报表拍的是**默认周期**：分类占比/多维分析=`本月`，收支趋势=`近1年`。本月数据够满
> （¥10,362、7 个分类），不必改成`本年`。多维分析有下钻，**只拍 L1**。

> **总览页那 4 张是 2026-10-07 重拍的。** 重拍前净资产是 **-¥672,834.47**，
> 大字放对外素材上很难看；现在调成了 **+¥205,505.13**。
> **调的是账户初始余额，不是交易**——`AccountServiceImpl` 里
> `余额 = initialBalance + Σ交易`，所以 5950 笔交易一笔没动，
> `11-transactions` / `14-addtx` 那几张**不受影响**，不必因净资产重拍。
> 只有账户页因为余额变了要跟着重拍（已重拍）。
>
> （报表那几张后来确实重拍了，但**与净资产无关**——是因为原来只有中文版，
> 英文版是新补的。）
>
> 净资产现在是正的了，**总览页其实已经够格当 banner 主屏**。当前仍用「记一笔」是因为
> 它一眼说清这是**手动录入**的记账工具，更对本 App 的定位——这是选型偏好，不是限制。
>
> ⚠️ **重拍总览时会踩的坑**：净资产**默认是打码的**（`showNetWorth` 默认 false，
> 显示成圆点），冷启动后必须点一下眼睛图标、并**等完 2–4 秒的逐位揭示动画**才能拍，
> 否则拍到的是一排点。另外英文布局下 `Net Worth` 比 `净资产` 宽，眼睛按钮的 x 坐标
> 会从约 89.8 移到约 125.8——按旧坐标点会误触卡片的「展开明细」开关。

## iPad 13 英寸（2064×2752）

**为什么必须单独拍**：`钱伲` 的 `TARGETED_DEVICE_FAMILY = "1,2"`（含 iPad），
App Store Connect 就强制要求 **13 英寸 iPad 显示屏截屏**，否则提交时报
「你必须上传 13 英寸 iPad 显示屏的截屏」。iPhone 那套尺寸不合用。

放在 `ipad13/` 子目录，12 张：

```
10-dashboard-{dark,light}{,-en}.png
13-accounts-{dark,light}{,-en}.png
12-reports-cat-{dark,light}{,-en}.png
```

设备用 **iPad Pro 13-inch (M4) → 2064×2752**，命名与内容跟 iPhone 那套一一对应
（同一屏、同一外观、同一语言），便于对照。

### 三个 iPad 专属的坑

1. **必须打 Release 包，不能沿用 Debug 包。**
   Debug 设了 `INFOPLIST_KEY_CFBundleDisplayName = 荡漾计然`（有意留的开发版标识），
   而 **iPad 的状态栏会在左上角显示 `CFBundleDisplayName`**（日期旁边）。
   iPhone 有灵动岛、状态栏不显示它，所以 iPhone 那套一直没暴露这个问题。
   Release 没有这个 key → 回落到 `PRODUCT_NAME`（`钱伲`），才是该上架的名字。
   → 命令换成 `-configuration Release`，产物路径 =
   `Build/Products/Release-iphonesimulator/钱伲.app`。

2. **iPadOS 18+ 把经典 `TabView` + `.tabItem` 渲染成顶部居中的悬浮标签栏**
   （既不是底栏，也不是侧边栏）。`MainTabView.swift` 没有任何 `.tabViewStyle` /
   sidebar 适配代码，属原生默认行为，**不是 bug、不用改**。

3. **英文那 6 张里有中文专有名词**（账本名「我的账本」、商户名、账户名）。
   它们和 iPhone 那套一样是**用户数据**，切 app 语言翻不掉——要干净就得改 sqlite
   里的数据（见「改名映射」）。**本轮决定「就这样收下」，不做数据改名**，
   所以英文 iPad 截图里保留这些中文专有名词。若日后要重拍，先按「改名映射」改名。

### 切外观的两个 plist，别搞混（踩过）

iOS 模拟器的 app 偏好有**两个同名文件**：

| 路径 | 谁写 | 谁读 |
|---|---|---|
| `data/Library/Preferences/com.qianey.app.plist`（设备级）| `simctl spawn … defaults write` | **app 读它拿 `appearanceMode`** |
| `data/Containers/Data/Application/<UUID>/Library/Preferences/com.qianey.app.plist`（容器级）| app 自己写的 key | 朴素地拷容器时会拷到它 |

**在新设备上拍深色时**，`defaults write` 必须写在**那台设备**上：

```bash
xcrun simctl spawn <该设备的 UDID> defaults write com.qianey.app appearanceMode dark
```

两个容易误判的坑：
- 只拷贝容器级 plist，会**丢掉 `appearanceMode`**（它在设备级那个里）。
- `xcrun simctl ui <dev> appearance` 报的是**系统**外观（light），
  **不是** app 自己的 `appearanceMode` 设置——别拿它当判断依据。

## 怎么拍

必须是**真机截图**，不能用 `FirstCC/Design/` 下那些早期设计稿——尺寸不齐，且与当前真机 UI 对不上，
素材与实物不符会踩 Guideline 2.3。

### 1. 建 Debug 包并装进模拟器

```bash
xcodebuild -project FirstCC.xcodeproj -scheme 钱伲 \
  -destination "platform=iOS Simulator,name=iPhone 17" \
  -derivedDataPath /tmp/firstcc-asset-build -jobs 4 SWIFT_COMPILATION_MODE=wholemodule

xcrun simctl install <UUID> /tmp/firstcc-asset-build/Build/Products/Debug-iphonesimulator/钱伲.app
xcrun simctl launch  <UUID> com.qianey.app
```

**必须是 Debug 包**——下面那个灌数据按钮包在 `#if DEBUG` 里，Release 包没有。

### 2. 灌演示数据（复用项目自带的 seeder，不用新写代码）

`LedgerSettingsView.swift` 里有个 **「生成3年测试数据」** 按钮（瓢虫图标），调 `DummyDataSeeder`，
在当前账本里生成约 2000–4000 笔随机支出 + 每月收入，覆盖过去 3 年。

前置条件：`DummyDataSeeder` 里有 `guard !accounts.isEmpty`，**必须先建至少一个账户**，否则直接跳过。

操作路径：

1. 首启 → 创建账本（`CreateLedgerView` 会自动灌默认分类 + 商家）
2. 账户 tab → 右下悬浮 **+** → 建 2–3 个账户
3. 设置 tab → **账本设置** → 点进账本详情页 → **滚到最底部** → 点「生成3年测试数据」
4. 等菊花转完（几十秒到几分钟，取决于机器）

### 3. 切外观与语言

两者都是 app 级设置，**不改模拟器本身的系统设置**：

```bash
# 外观：dark / light
xcrun simctl spawn <UUID> defaults write com.qianey.app appearanceMode dark

# 语言：英文界面（不影响模拟器系统语言）
xcrun simctl spawn <UUID> defaults write com.qianey.app AppleLanguages -array en

xcrun simctl terminate <UUID> com.qianey.app
xcrun simctl launch    <UUID> com.qianey.app
```

拍完**记得清掉语言**，免得影响后续：

```bash
xcrun simctl spawn <UUID> defaults delete com.qianey.app AppleLanguages
```

### 4. 截图

```bash
xcrun simctl io <UUID> screenshot tools/appstore-assets/screenshots/14-addtx-dark-en.png
```

`simctl io screenshot` 出的是**屏幕原始缓冲**（1206×2622），矩形、无圆角——圆角由 `make_banner.swift`
的 `PhoneFrame` 补。**不要自己先裁圆角**，也不要改用 MCP 的截图工具（那是缩略图，尺寸不对）。

⚠️ **目标是已存在的文件时，`simctl io screenshot` 会失败**：
`You don't have permission to save the file … Operation not permitted`。
**而且 `sips` 仍然会报出旧文件那正确的 1206×2622——很容易误判成功。**
→ **每次截图前先 `rm -f <目标文件>`**，再核尺寸。

拍完用 `sips -g pixelWidth -g pixelHeight <文件>` 核对必须是 1206×2622，
并**用 Read 工具把图逐张看一遍**（尺寸对不代表内容对）。

## `-en` 那套截图还要求演示数据是英文的

切 app 语言只翻译**控件文案**，翻译不了**数据内容**。第一版英文截图里
控件全英文、但商户名列着「永辉超市 / 山姆会员商店」、账户名叫「支付宝 / 微信零钱 / 中国移动」——
一眼假，且违反「素材按语言分别出图」的要求。

拍 `-en` 前必须把演示数据也改成英文。**注意：`String Catalog` 只管控件文案，
碰不到数据。**

### 哪些控件名会自动变英文，哪些不会

- **会**：账户类型分组头（`现金/借记卡/信用卡/电子钱包`）、报表名、周期名、维度名——
  这些是 catalog 条目，切语言即变。
- **不会**：账本名、账户名、成员名、商户名、项目名。全是用户数据。
- **看情况**：分类名。它是用户数据，但内置分类同时是 catalog 的 key，报表模块会
  统一查一次（见下面那条），所以「餐饮饮食」这类内置分类会自动出英文名。

- **分类名曾经也是例外，分两批修完**：报表模块最初有几处用裸 `Text(item.name)`
  渲染分类名，不走 `LocalizedStringKey`，所以即使 catalog 里有
  「餐饮饮食 → Food & Dining」也查不到。
  - `39a16ab` 修了 3 处**纯列表**：`CategoryPieChartView.swift:279`、
    `MemberPieChartView.swift:112`、`MemberCategoryCrossView.swift:82`（成员列）。
  - 2026-10-07 又补修 **6 处漏网的**：
    - **环形图图例** `DonutChartContent.swift:21`——之前一直没修，是英文截图里
      最显眼的中文残留。
    - 与之**必须同改**的 `CategoryPieChartView.swift:218`（`gradientLookup` 的 key）。
      两处用的是同一个字符串当 key，只改一边会让配色全部查不到、**所有扇区变灰**。
    - `MemberCategoryCrossView.swift:110`（**分类列**——上次只改了同文件的成员列）。
    - Mac 3 处：`CategoryBarList.swift:100`、`DonutChart.swift:174`、
      `MacBudgetChartView.swift:615/666`。
  - ⚠️ **图例那处不能照抄 `Text(LocalizedStringKey(...))`**：Swift Charts 的图例
    显示的是 plottable 的**值**而不是标签，而值必须是 `String`，用不了
    `LocalizedStringKey`。所以共享的 `CategoryExpenseItem` 上加了
    `var localizedName: String { NSLocalizedString(name, comment: "") }`——
    这是本项目 scenario E 的既有写法（`AccountType`、`LedgerType` 等 15+ 处在用）。
  → **catalog 里有条目的分类现在会出英文名，图例也一样，不必再改分类数据。**
  只有 catalog 里没有的分类仍显示中文——**实测默认 94 个分类里只有 2 个缺 `en`**
  （`数码产品`、`停车车位`，都在 L2，L1 报表图拍不到）。

### 改名映射（照抄，别现编）

账户 7 个：信用卡→`Credit Card`｜现金→`Cash`｜微信支付→`WeChat Pay`｜工资卡→`Salary Card`｜
招商银行储蓄卡→`CMB Debit Card`｜支付宝→`Alipay`｜微信零钱→`WeChat Balance`

成员：配偶→`Spouse`｜自己→`Me`｜孩子→`Child`
项目：日常→`Daily`
账本：我的账本→`My Ledger`｜预算本：家庭月度预算→`Household Monthly`

商户 48 个（**多维分析·商家维度每个约 120 笔，48 个全露**）：
携程旅行→Trip.com｜美团→Meituan｜铁路 12306→China Railway 12306｜京东物流→JD Logistics｜
滴滴出行→DiDi｜极兔速递→J&T Express｜居然之家→Easyhome｜韵达快递→Yunda Express｜
苏宁易购→Suning｜大润发→RT-Mart｜物美→Wumart｜饿了么→Ele.me｜永辉超市→Yonghui Mart｜
屈臣氏→Watsons｜飞猪旅行→Fliggy｜闲鱼→Xianyu｜盒马鲜生→Freshippo｜得物→Poizon｜
拼多多→Pinduoduo｜全友家居→QuanU Home｜开市客→Costco｜安居客→Anjuke｜大众点评→Dianping｜
山姆会员商店→Sam's Club｜华润万家→CR Vanguard｜菜鸟网络→Cainiao｜网易严选→NetEase Yanxuan｜
唯品会→Vipshop｜中国电信→China Telecom｜阿里巴巴 1688→Alibaba 1688｜红星美凯龙→Red Star Macalline｜
哈啰出行→HelloRide｜淘宝 / 天猫→Taobao / Tmall｜中国移动→China Mobile｜贝壳找房→Beike｜
小红书→Xiaohongshu｜圆通速递→YTO Express｜顺丰速运→SF Express｜去哪儿→Qunar｜
沃尔玛→Walmart｜联华超市→Lianhua Supermarket｜中国联通→China Unicom｜申通快递→STO Express｜
京东→JD.com｜德邦快递→Deppon Express｜中国广电→China Broadnet｜中通快递→ZTO Express｜
中国邮政 EMS→China Post EMS

**分类不用改**（2026-10-07 起，**含图例**）：报表模块走 `LocalizedStringKey` /
`NSLocalizedString`，catalog 里有条目的分类自动显示英文。
> 历史备注（在那之前必须做、现已作废）：94 条分类名要逐条改成英文，映射直接查
> `Localizable.xcstrings` 取官方英文名（`餐饮饮食→Food & Dining`、
> `交通出行→Transportation`、`购物消费→Shopping` 等），不要自己翻；
> catalog 里没有的只有 2 条：`数码产品→Digital Products`、`停车车位→Parking`。

### 怎么改

48 个商户靠 UI 手点不现实。**直接改 sqlite**：先把
`<容器>/Library/Application Support/FirstCC.sqlite{,-wal,-shm}` 三件套整目录备份，改完
**原样拷回**还原（比逐条改回去可靠）。改之前必须
`xcrun simctl terminate <UUID> com.qianey.app`（CoreData 开着会覆盖你的写入），
改完 `PRAGMA wal_checkpoint(TRUNCATE);` 再 launch。
装过一次 app 后**容器 UUID 会变**，路径每次重新 `get_app_container` 取，别缓存。

中文界面用的是 app 级语言（`AppleLanguages`），**与这些数据名无关**，
所以中文那套截图不受影响，不必重拍；改完名直接回改回中文即可。

> 判断 `-en` 截图干不干净：看**流水列表**里「商户名」和**记一笔**里「账户名」这两处，
> 它们是最容易漏的中文。只翻控件、不翻数据是常见错误。

## 这批截图里已知的显示缺陷（是 app 的 bug，不是拍错）

拍照时如果发现下面这些，**不要以为是拍错了、也不要自行修图**——它们是 app 当前的真实行为，
图是如实反映。修要改 Swift 代码。

**已修（2026-10-07，commit `39a16ab`）——重拍时不必再绕过：**

- 英文「收支趋势」月份轴显示 `26Oct`，且比中文版少了年份分组条、少了图例右侧的
  「2025 – 2026」范围标注。`ReportViewModel` 原先把 `year(.twoDigits)\(month(.abbreviated))`
  拼成的**显示串**当分组 key，再靠找「年」字反解析年份；英文串里没有「年」字，年份就丢了。
  现在改成从 `Date` 组件直接取年月，分组 key 用与 locale 无关的「年*100+月」。
- 同一个函数里横轴月份乱序（fetch 没带 `sortDescriptors`，按 Core Data 任意返回顺序画）
  ——已按年月升序排序。
- 英文报表列表出现中文分类名——报表 3 处裸 `Text(name)` 已改成
  `Text(LocalizedStringKey(name))`（见上一节）。

**已修（2026-10-07，第二批量，含本轮）：**

- **英文环形图**图例**仍是中文分类名**——`39a16ab` 只修了纯列表，图例那处
  （`DonutChartContent.swift:21`）漏了，因为图例显示的是 plottable 的**值**、
  值必须是 `String`，`LocalizedStringKey` 救不了。已改走
  `CategoryExpenseItem.localizedName`，并同步改了 `gradientLookup` 的 key。
- 同一缺陷另 5 处（Mac 柱状列表/环形图悬浮面板/预算执行卡片、iOS 交叉表分类列）
  ——见上一节。
- ⚠️ **`tools/appstore-assets/screenshots/` 下已入库的 6 张英文报表图**
  （`12-reports-cat-{dark,light}-en.png` 与 `ipad13/` 里同名的 2 张）
  **拍的是修复前的图例**，图例仍是中文分类名。**本轮先不重拍**（用户决定），
  所以这 6 张与当前代码不符。中文那套不受影响（中文 key 查回中文）。

**未修（拍到就如实留着）：**

| 现象 | 根因 | 影响面 |
|---|---|---|
| Mac「资产变化」报表的 x 轴标签 | `ReportViewModel.swift:904` 硬编码 `String(format: "%02d年%d月", …)`，违反 CLAUDE.md 的日期格式规范（应用 `Date.FormatStyle` 随 locale 自适应） | Mac 英文界面 |
| 账户新增/编辑表单里出现英文 `Logo` | `Section("Logo")`（`AccountsManagementView.swift:207`、`AddEditAccountView.swift:98`）——key 本身是英文，中文侧没有值 | 中文界面 |

## 隐私提醒

演示数据会写进模拟器的本地 store。模拟器一般没有登录 iCloud 账号，
`CoreDataStack` 里 `cloudKitAvailable` 依赖 `ubiquityIdentityToken`，因此**不会**同步到真机 iCloud。
拍完想清干净就 `xcrun simctl erase <UUID>`。
