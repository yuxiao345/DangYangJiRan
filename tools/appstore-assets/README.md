# App Store 上架材料

本目录收纳钱伲的 App Store 上架素材与文案。

| 文件 | 用途 |
|---|---|
| `metadata.md` | **上架文案**：名称 / 副标题 / 关键词 / 推广文本 / 描述 / 新功能，中英双语 |
| `make_banner.swift` | **创意素材生成器**：出 16:9 通用素材（产品页页眉 + 搜索结果） |
| `check_lengths.py` | 校验 `metadata.md` 各字段是否超 ASC 字符上限 |
| `screenshots/` | 生成素材用的真机截图（拍摄方法见其 README） |
| `output/` | 生成的素材成品 |

> **隐私政策页 / 支持页不在这个目录，也不在本仓库。** 它们在独立的公开仓库
> `~/Documents/AI/qianey-legal/`（App Store 必填的两个 URL 靠它落地）。
> **也不要放进本仓库的 `docs/`**——那里已有内部文档，Pages 会把整个目录公开。

## 创意素材（Header / Search Results）

Apple 2026-10-05 启用的新素材位，**只在 iOS 27 / iPadOS 27 及以上显示**，Mac 端没有这个位置，不需要做。

## 规格（Apple 官方）

来源：[Creative assets specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/creative-assets-specifications)

| 位置 | 比例 | 像素 | 格式 |
|---|---|---|---|
| 产品页页眉 | 21:9 | 3840 × 1646 | jpeg / jpg / png |
| 产品页页眉 | 16:9 | 5244 × 2950 | 仅 png |
| 搜索结果 | 3:2 | 1920×1280 ～ 3840×2560 | jpeg / jpg / png |
| 搜索结果 | 16:9 | 5244 × 2950 | 仅 png |

**本脚本出的是 16:9 / 5244 × 2950 的「通用素材」**——这是唯一一种能同时用于
产品页页眉和搜索结果的规格。上传后在 App Store Connect 里勾选
**Use header asset in search results** 即可一图两用。

Apple 的其他硬约束：

- **不得包含 alpha 通道或透明**（脚本用 `stripAlpha()` 强制转成 `noneSkipLast` 的 RGB，并先铺不透明底色）。
  验证：`sips -g hasAlpha output/banner-zh.png` 必须输出 `hasAlpha: no`。
- 素材需满足 **4+ 分级**，即使 App 本身分级更高。
- **禁止**出现具体价格 / 折扣、网址、版权符号、未获得的奖项、其他平台 logo。
- 文案要**按语言分别出图**（英文素材出现在中文店面和英文截图一样是错误）。
- 送审：可**走 Asset Library 独立提交，不必动 App 版本**。

## 设计约束（本项目）

- 画面 = **真实 App 界面 + 文案**。Apple 对搜索位的要求是 *"state the obvious"*（一眼看出干嘛）
  和 *"showcase the firsthand experience"*（露真实界面），所以手机里必须是真机截图，不是设计稿。
- 背景复刻 App 的 `LiquidBackgroundModifier`，颜色取自 `Color+Design.swift` 深色模式值，
  字体用 App 自带的 Space Grotesk / JetBrains Mono。
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
# 中英 × 深浅，共 4 张
swift tools/appstore-assets/make_banner.swift

# 按语言 / 外观筛（可组合）
swift tools/appstore-assets/make_banner.swift --zh
swift tools/appstore-assets/make_banner.swift --en
swift tools/appstore-assets/make_banner.swift --light
swift tools/appstore-assets/make_banner.swift --zh --light
```

输出的 4 个文件：

```
output/banner-zh-dark.png    output/banner-zh-light.png
output/banner-en-dark.png    output/banner-en-light.png
```

输入读 `screenshots/`，输出写 `output/`，路径都相对脚本自身，从任何目录执行都可以。
缺图时不会报错中止，而是画占位块——方便截图还没拍好时先看版式。

## 换素材 / 改文案

- **改文案**：编辑 `make_banner.swift` 里的 `ZH` / `EN` 两个 `Copy` 常量。
  中文断行是手动的（`headline` 数组每项一行）；拉丁文案的字号系数 `sizeMul` 要单独调，
  因为 Space Grotesk 比中文字宽，同样的系数会撑出画布。
- **换截图**：改 `make_banner.swift` 末尾 `loadShot(...)` 的两个文件名，然后替换
  `screenshots/` 下对应文件即可；哪张当主屏/副屏、为什么这么选，见 `screenshots/README.md`。
  ⚠️ **主屏不要用总览页**：演示数据的净资产是负数（-67 万），大字放在素材上很难看。
- **英文素材的手机里必须是英文界面**。Apple 要求素材按语言分别出图，
  英文店面配中文 UI 属于素材与语言不符。切 app 级语言的方法见 `screenshots/README.md`。
- **改底色/品牌色**：先改 `FirstCC/DesignSystem/Color+Design.swift`，再同步脚本顶部那几个常量，
  两边不要各改各的。
