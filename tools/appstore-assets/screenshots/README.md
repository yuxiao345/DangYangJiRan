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
| `10-dashboard-dark.png` | 总览页，深色 |
| `15-dashboard-light.png` | 总览页，浅色 |
| `12-reports-dark.png` | 报表，深色 |
| `13-accounts-dark.png` | 账户列表，深色 |
| `16-transactions-light.png` | 流水列表，浅色（与 `11-transactions-light.png` 同屏，冗余） |

留着做 App Store **截图**素材时会用到。

> **为什么主屏不用总览页。** `DummyDataSeeder` 生成的三年数据支出远大于收入，
> 总览页顶部那个大字是**净资产**，实测为 **-¥672,834.47**——放在对外素材上很难看。
> 另外 seeder 不建预算，总览页的「本月预算」卡片一直是空态，同样不适合上素材。
> 相比之下「记一笔」一眼就说清这是**手动录入**的记账工具，更对本 App 的定位。
> 若将来要用总览页当主屏，**先把演示数据调成净资产为正、并建一个预算**。

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

拍完用 `sips -g pixelWidth -g pixelHeight <文件>` 核对必须是 1206×2622。

## `-en` 那套截图还要求演示数据是英文的

切 app 语言只翻译**控件文案**，翻译不了**数据内容**。第一版英文截图里
控件全英文、但商户名列着「永辉超市 / 山姆会员商店」、账户名叫「支付宝 / 微信零钱 / 中国移动」——
一眼假，且违反「素材按语言分别出图」的要求。

拍 `-en` 前先把这几个演示数据改名（账户在**设置 → 账本设置 → 账户**，商户在**设置 → 账本设置 → 商户**）：

| 中文原名 | 英文改名后 |
|---|---|
| 支付宝 | Alipay |
| 微信零钱 | WeChat Balance |
| 永辉超市 | Yonghui Mart |
| 山姆会员商店 | Sam's Club |
| 中国移动 | China Mobile |

中文界面用的是 app 级语言（`AppleLanguages`），**与这些数据名无关**，
所以中文那套截图不受影响，不必重拍；改完名直接回改回中文即可。

> 判断 `-en` 截图干不干净：看**流水列表**里「商户名」和**记一笔**里「账户名」这两处，
> 它们是最容易漏的中文。只翻控件、不翻数据是常见错误。

## 隐私提醒

演示数据会写进模拟器的本地 store。模拟器一般没有登录 iCloud 账号，
`CoreDataStack` 里 `cloudKitAvailable` 依赖 `ubiquityIdentityToken`，因此**不会**同步到真机 iCloud。
拍完想清干净就 `xcrun simctl erase <UUID>`。
