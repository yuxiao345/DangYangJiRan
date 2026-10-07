# App Store 上架材料

本目录收纳钱伲的 App Store 上架素材与文案。

| 文件 | 用途 |
|---|---|
| `metadata.md` | **上架文案**：名称 / 副标题 / 关键词 / 推广文本 / 描述 / 新功能，中英双语 |
| `make_banner.swift` | **创意素材生成器**：出 21:9 页眉 / 3:2 搜索 / 16:9 通用 三种规格 |
| `safecheck.swift` | **安全区自查图生成器**：把安全区之外压暗、描黄框，肉眼复核用 |
| `check_lengths.py` | 校验 `metadata.md` 各字段是否超 ASC 字符上限 |
| `screenshots/` | 生成素材用的真机截图（拍摄方法见其 README） |
| `output/` | 生成的素材成品（**可直接上传的那些**） |
| `diag/` | 诊断图：安全区自查、Apple 官方示例、模板预览。**不要上传 App Store** |

> **隐私政策页 / 支持页不在这个目录，也不在本仓库。** 它们在独立的公开仓库
> `~/Documents/AI/qianey-legal/`（App Store 必填的两个 URL 靠它落地）。
> **也不要放进本仓库的 `docs/`**——那里已有内部文档，Pages 会把整个目录公开。

## 创意素材（Header / Search Results）

Apple 2026-10-05 启用的新素材位，**只在 iOS 27 / iPadOS 27 及以上显示**，Mac 端没有这个位置，不需要做。

## 规格（Apple 官方）

来源：[Creative assets specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/creative-assets-specifications)
与 [Asset best practices](https://developer.apple.com/app-store/asset-best-practices/)

| 位置 | 比例 | 像素 | 格式 | 本脚本输出 |
|---|---|---|---|---|
| 产品页页眉 | 21:9 | 3840 × 1646 | jpeg / jpg / png | `header-21x9-*.png` |
| 搜索结果 | 3:2 | 1920×1280 ～ 3840×2560 | jpeg / jpg / png | `search-3x2-*.png` |
| 两者通用 | 16:9 | 5244 × 2950 | 仅 png | `universal-16x9-*.png` |

**优先用专用规格（21:9 / 3:2）**，它们的安全区宽得多，版式能舒展。16:9「通用素材」
的唯一好处是一张图两用（上传后在 ASC 勾选 **Use header asset in search results**），
代价是安全区被压到画布宽的 26.7%，字号被迫缩小。三个都出了，用哪个由你决定。

Apple 的其他硬约束：

- **不得包含 alpha 通道或透明**（脚本用 `stripAlpha()` 强制转成 `noneSkipLast` 的 RGB，并先铺不透明底色）。
  验证：`sips -g hasAlpha output/header-21x9-zh-dark.png` 必须输出 `hasAlpha: no`。
- 素材需满足 **4+ 分级**，即使 App 本身分级更高。
- **禁止**出现具体价格 / 折扣、网址、版权符号、未获得的奖项、其他平台 logo。
- 文案要**按语言分别出图**（英文素材出现在中文店面和英文截图一样是错误）。
- 送审：可**走 Asset Library 独立提交，不必动 App 版本**。

## 安全区（ART SAFE AREA）—— 本项目最重要的一条约束

Apple 在网页上**没有公布**安全区数值，只在 best-practices 里写了一句
*"Be sure your focal point artwork is within the center of your composition to prevent
any unwanted clipping."* 第三方文章也都承认拿不到数。**数字只存在于官方模板文件里。**

下面这套值是从官方 Sketch 模板 `creative_assets-templates.sketch` 的 `Art Safe Area`
图层里取出来的，并用模板自带的 `previews/preview.png` 做了**像素级复核**
（通用版实测左右各 36.60%、上 22.39%、下 45.02%，与图层几何完全吻合）：

| 格式 | 安全区像素 | 占画布 | 边距 |
|---|---|---|---|
| 页眉 21:9 | 1646 × 661 | 42.9% × 40.2% | 四边基本等距（各约 29%） |
| 搜索 3:2 | 2168 × 1030 | 56.5% × 40.2% | 四边等距（左右 21.8%、上下 29.9%） |
| 通用 16:9 | 1402 × 962 | **26.7% × 32.6%** | 左右各 36.6%；**上 22.4%、下 45.0%（偏上，不居中）** |

复现方法：`unzip` 那个 `.sketch`（本质是 zip），在 `pages/*.json` 里找
`Art Safe Area` 图层，注意 Sketch 的 `frame.x/y` 是**相对父级**的，要逐层累加。

**由此定下的构图：背景出血，品牌文案与焦点必须落在安全区内。**
Apple 官方示例（见 `diag/Apple官方示例-*.png`）就是这么做的——页眉里森林、海景满幅出血，
而文字/标志居中。安全区外的东西在某些设备或方向下会被裁掉，而 **Apple 明确说它不公布
裁剪算法**，只建议用 ASC 的 Preview 工具看实际效果。所以别赌，文案一律放安全区里；
手机这类**装饰性**内容才允许被裁。

### 这条约束是怎么强制住的

脚本**不靠肉眼**：`fittedHeadlineScale()` 用 `NSHostingView.fittingSize` 量文案块的
**真实布局尺寸**（不是像素测量——手机阴影会干扰像素法），放不下就自动等比缩小，
直到占安全区不超过 96%。每次运行都会打印余量：

```
▸ 通用素材 universal-16x9  5244x2950  安全区 1402x962 (占宽 26.7% 占高 32.6%)
  zh ✅ 文案块 1208x853 / 安全区 1402x962  余量 194x109
  en ⚠️ 文案块 1319x742 / 安全区 1402x962  余量 83x220  （已自动缩到 0.185，原设 0.205）
```

出现 `⚠️ ... 已自动缩到` 就说明原始字号装不下、被自动缩过——这是提示，不是错误。
**改了文案（变长）后务必重跑，看余量是不是还够。**

数字是护栏，肉眼还得看一遍。`safecheck.swift` 把安全区之外压暗、给安全区描一圈黄框，
**验收标准：全部品牌文案必须整块落在黄框内**（手机这类装饰性内容允许出框）。

```bash
swift tools/appstore-assets/safecheck.swift \
  tools/appstore-assets/output/header-21x9-zh-dark.png \
  tools/appstore-assets/diag/自查-header-21x9.png \
  0.285677 0.712760 0.299514 0.701093
```

> ⚠️ 末尾那四个分数是**从 `FORMATS` 抄过去的**（`1097.0 / 3840` 除一下即得），
> 不是单一真相来源。Apple 改了模板就要**两处一起改**。之所以不做成 `make_banner.swift`
> 的 `--safecheck` 开关去共用 `FORMATS`，是为了让它能在成品图已生成、而生成器本身
> 跑不起来时照常独立运行。

成品 `diag/自查-*.png` 已随仓库提供；`diag/旧构图/` 与 `diag/banner-*-safearea.png`
是改版前的一次性对照材料，体积大且可从 git 历史取回，已由 `.gitignore` 排除。

## 设计约束（本项目）

- 画面 = **真实 App 界面 + 文案**。Apple 对搜索位的要求是 *"state the obvious"*（一眼看出干嘛）
  和 *"showcase the firsthand experience"*（露真实界面），所以手机里必须是真机截图，不是设计稿。
- 背景复刻 App 的 `LiquidBackgroundModifier`，颜色取自 `Color+Design.swift`，
  字体用 App 自带的 Space Grotesk / JetBrains Mono。深浅色各出一套——
  **手机里的界面必须与海报底色同一外观**，深色海报上贴浅色截图会变成一块突兀的白。
- **文案可证实性**：只允许写以下为真的主张——
  - `无广告`（全项目零第三方依赖）
  - `无追踪`（`PrivacyInfo.xcprivacy` 里 `NSPrivacyTracking = false`）
  - `无需注册`（无 App 级账号体系）
  - `数据存于你自己的 iCloud`（CloudKit 私有库）
  - `家庭共享账本`（CKShare）

  ⚠️ **不要写「数据不上传服务器」**——本 App 走 CloudKit，数据会同步进用户的 iCloud，
  那句是假的，属于 Guideline 2.3 虚假元数据。

## 用法

```bash
# 全格式 × 中英 × 深浅，共 12 张
swift tools/appstore-assets/make_banner.swift

# 按格式筛
swift tools/appstore-assets/make_banner.swift --format=header     # 只出 21:9 页眉
swift tools/appstore-assets/make_banner.swift --format=search     # 只出 3:2 搜索
swift tools/appstore-assets/make_banner.swift --format=universal  # 只出 16:9 通用

# 按语言 / 外观筛（可组合）
swift tools/appstore-assets/make_banner.swift --zh --light
```

输出的 12 个文件，命名规则 `{format}-{lang}-{theme}.png`：

```
output/header-21x9-{zh,en}-{dark,light}.png
output/search-3x2-{zh,en}-{dark,light}.png
output/universal-16x9-{zh,en}-{dark,light}.png
```

输入读 `screenshots/`，输出写 `output/`，路径都相对脚本自身，从任何目录执行都可以。
缺图时不会报错中止，而是画占位块——方便截图还没拍好时先看版式。

## 换素材 / 改文案

- **改文案**：编辑 `make_banner.swift` 里的 `ZH` / `EN` 两个 `Copy` 常量。
  中文断行是手动的（`headline` 数组每项一行）。字号用 `headlineScale`（相对**安全区高度**的
  比例，不是画布——这样同一套参数在三种宽高比下都能自适应），装不下会被自动缩，见上文。
- **换截图**：改 `make_banner.swift` 里 `SCREEN_MAIN` / `SCREEN_SUB` 两个基名，然后替换
  `screenshots/` 下对应文件即可；哪张当主屏/副屏、为什么这么选，见 `screenshots/README.md`。
  ⚠️ **主屏不要用总览页**：演示数据的净资产是负数（-67 万），大字放在素材上很难看。
- **改安全区**：只有 Apple 改了模板才需要动，改 `FORMATS` 里那几个分数即可（别写死像素）。
- **英文素材的手机里必须是英文界面**。Apple 要求素材按语言分别出图，
  英文店面配中文 UI 属于素材与语言不符。切 app 级语言的方法见 `screenshots/README.md`。
  商户名这类**演示数据**也要一起换成英文（永辉超市→Yonghui Mart 等），否则一眼看穿。
- **改底色/品牌色**：先改 `FirstCC/DesignSystem/Color+Design.swift`，再同步脚本顶部那几个常量，
  两边不要各改各的。
