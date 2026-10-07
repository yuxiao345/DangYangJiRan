import SwiftUI
import AppKit

// ============================================================
// App Store 创意素材生成器 —— Header / Search Results 通用
// ============================================================
// 规格来源（Apple 官方，2026-10-05 启用）：
//   https://developer.apple.com/help/app-store-connect/reference/app-information/creative-assets-specifications
//
//   · 16:9 PNG  5244 x 2950  —— 唯一一种「通用素材」，可同时用于
//                                产品页页眉 与 搜索结果（勾选 Use header asset in search results）
//   · 21:9      3840 x 1646  —— 仅产品页页眉（本脚本未使用）
//   · 3:2       1920x1280 ~ 3840x2560 —— 仅搜索结果（本脚本未使用）
//   · 图片不得含 alpha 通道 / 透明      ← 脚本末尾 stripAlpha() 强制保证
//   · 素材需满足 4+ 分级；禁止出现价格、折扣、网址、版权符、未获得的奖项
//   · 只在 iOS 27 / iPadOS 27 及以上显示（Mac 端无此素材位）
//
// 用法：
//   swift tools/appstore-assets/make_banner.swift            # 中英 × 深浅 共 4 张
//   swift tools/appstore-assets/make_banner.swift --zh       # 只出中文
//   swift tools/appstore-assets/make_banner.swift --en       # 只出英文
//   swift tools/appstore-assets/make_banner.swift --light    # 只出浅色
//   swift tools/appstore-assets/make_banner.swift --dark     # 只出深色
//   （可组合：--zh --light）
//
// 输入：tools/appstore-assets/screenshots/ 下的真机截图（见该目录 README 的拍摄说明）
// 输出：tools/appstore-assets/output/banner-{zh,en}-{dark,light}.png
// ============================================================

// MARK: - 路径（一律相对脚本自身，不依赖当前工作目录）

let SCRIPT_DIR = URL(fileURLWithPath: CommandLine.arguments[0])
    .deletingLastPathComponent()
    .standardizedFileURL
let REPO_ROOT = SCRIPT_DIR
    .deletingLastPathComponent()   // tools/
    .deletingLastPathComponent()   // repo root
let FONT_DIR = REPO_ROOT.appendingPathComponent("FirstCC/Resources/Fonts").path
let SHOT_DIR = SCRIPT_DIR.appendingPathComponent("screenshots").path
let OUT_DIR  = SCRIPT_DIR.appendingPathComponent("output").path

// MARK: - 画布（Apple 通用素材规格）

let CANVAS_W: CGFloat = 5244
let CANVAS_H: CGFloat = 2950

// MARK: - 主题色（深 / 浅各一套）
// 全部取自 FirstCC/DesignSystem/Color+Design.swift 的对应外观取值，
// 保证素材与 App 在该外观下观感一致。改色请先改那边，再同步这里。

func hex(_ s: String, alpha: Double = 1) -> Color {
    let v = UInt64(s.hasPrefix("#") ? String(s.dropFirst()) : s, radix: 16) ?? 0
    return Color(red: Double((v >> 16) & 0xFF) / 255.0,
                 green: Double((v >> 8) & 0xFF) / 255.0,
                 blue: Double(v & 0xFF) / 255.0,
                 opacity: alpha)
}

/// 一个外观下的整套配色。
/// 背景光斑对应 App 的 LiquidBackgroundModifier：
/// `designBackground` + 「designSurfaceTint」+「designTertiaryContainer」两团模糊圆。
struct Theme {
    let name: String            // 进文件名：banner-{lang}-{name}.png
    let bg: Color
    let ink: Color              // 主标题
    let muted: Color            // 副标题
    let bar: Color              // 绿色分隔条
    let blob1: Color            // designSurfaceTint
    let blob2: Color            // designTertiaryContainer
    let phoneStroke: Color
    let phoneShadow: Color
}

let DARK = Theme(
    name: "dark",
    bg: hex("#131313"),                     // designBackground (dark)
    ink: hex("#f0ffed"),                    // designPrimary (dark)
    muted: hex("#e5e2e1", alpha: 0.55),     // designOnSurface (dark)
    bar: hex("#00ff7f"),                    // designPrimaryFixedDim (dark)
    blob1: hex("#00e471", alpha: 0.10),     // designSurfaceTint (dark)
    blob2: hex("#e6d8ff", alpha: 0.10),     // designTertiaryContainer (dark)
    phoneStroke: Color.white.opacity(0.14),
    phoneShadow: Color.black.opacity(0.55)
)

let LIGHT = Theme(
    name: "light",
    bg: hex("#fcf9f8"),                     // designBackground (light)
    ink: hex("#1c1b1b"),                    // designOnBackground (light)
    muted: hex("#5c5f60"),                  // designSecondary (light)
    bar: hex("#00d16b"),                    // designPrimaryContainer (light)
    blob1: hex("#006d35", alpha: 0.08),     // designSurfaceTint (light)
    // App 里浅色光斑是 6% 的 #b5b6b6，放在 5244px 的海报上几乎看不见，
    // 这里提到 0.22 —— 这是**有意的、只为海报尺度的偏离**，不是在挑刺 App 的配色。
    blob2: hex("#b5b6b6", alpha: 0.22),
    phoneStroke: Color.black.opacity(0.10),
    phoneShadow: Color.black.opacity(0.22)
)

// MARK: - 字体注册（用 App 自带字体，保证与 App 内字形一致）

func registerFonts() {
    let files = ["SpaceGrotesk-Bold.ttf", "SpaceGrotesk-SemiBold.ttf",
                 "SpaceGrotesk-Medium.ttf", "SpaceGrotesk-Regular.ttf",
                 "JetBrainsMono-Medium.ttf", "JetBrainsMono-Bold.ttf"]
    for f in files {
        var err: Unmanaged<CFError>?
        let url = URL(fileURLWithPath: "\(FONT_DIR)/\(f)")
        _ = CTFontManagerRegisterFontsForURL(url as CFURL, .process, &err)
    }
    print("✓ 字体注册完成（\(FONT_DIR)）")
}

// MARK: - 文案
// ⚠️ 改文案前先确认可证实性：本项目的隐私主张仅以下几条为真——
//    「无广告」（零第三方 SDK）、「无追踪」（PrivacyInfo.xcprivacy 里 NSPrivacyTracking=false）、
//    「无需注册」（无 App 级账号）、「数据存于你自己的 iCloud」（CloudKit 私有库）、
//    「家庭共享账本」（CKShare）。
//    **不要写「数据不上传服务器」**——CloudKit 会同步到用户 iCloud，那句是假的。

struct Copy {
    let lang: String
    let headline: [String]   // 逐行，手动断行
    let sub: String
    let useGrotesk: Bool     // 拉丁文案用品牌字体；中文走系统字体（与 App 内一致）
    let sizeMul: CGFloat     // 主标题字号 = CANVAS_H * sizeMul；拉丁字宽差异大，单独调
}

let ZH = Copy(
    lang: "zh",
    headline: ["隐私优先的", "手记账本"],
    sub: "无广告 · 无追踪 · 家庭共享账本",
    useGrotesk: false,
    sizeMul: 0.120
)

let EN = Copy(
    lang: "en",
    headline: ["Private manual", "bookkeeping"],
    sub: "No ads. No tracking. Shared with family.",
    useGrotesk: true,
    sizeMul: 0.098
)

// MARK: - 截图载入
// 命名规则：中文 `{base}-{theme}.png`，英文 `{base}-{theme}-en.png`。
// 深色主题必须配深色截图、浅色主题必须配浅色截图——不然手机里是「白屏贴在深色海报上」。

func shotName(base: String, theme: String, lang: String) -> String {
    lang == "zh" ? "\(base)-\(theme).png" : "\(base)-\(theme)-\(lang).png"
}

func loadShot(base: String, theme: String, lang: String) -> NSImage? {
    let name = shotName(base: base, theme: theme, lang: lang)
    let path = "\(SHOT_DIR)/\(name)"
    guard FileManager.default.fileExists(atPath: path),
          let img = NSImage(contentsOfFile: path) else {
        print("⚠️ 缺图: \(name)（将用占位块代替，先看版式）")
        return nil
    }
    return img
}

/// 英文图缺失时回落到中文版并**明确告警**——「英文店面配中文界面」是要在送审前
/// 抓出来的问题，不能静默降级。
func loadShotOrFallback(base: String, theme: String, lang: String) -> NSImage? {
    if lang == "zh"
        || FileManager.default.fileExists(atPath: "\(SHOT_DIR)/\(shotName(base: base, theme: theme, lang: lang))") {
        return loadShot(base: base, theme: theme, lang: lang)
    }
    print("⚠️ 缺英文截图 \(shotName(base: base, theme: theme, lang: lang))，英文版将回落到中文界面（需重拍）")
    return loadShot(base: base, theme: theme, lang: "zh")
}

// MARK: - 手机外框

struct PhoneFrame: View {
    let image: NSImage?
    let width: CGFloat
    let height: CGFloat
    let theme: Theme

    var body: some View {
        // iPhone 屏幕圆角约为宽度的 11.5%
        let corner: CGFloat = width * 0.115

        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    theme.bg.opacity(0.6)
                    Text("截图占位").foregroundStyle(theme.ink.opacity(0.3))
                        .font(.system(size: width * 0.06))
                }
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .strokeBorder(theme.phoneStroke, lineWidth: width * 0.006)
        )
        .shadow(color: theme.phoneShadow, radius: width * 0.09, x: 0, y: width * 0.05)
    }
}

// MARK: - 主画面

struct Banner: View {
    let theme: Theme
    let copy: Copy
    let shotA: NSImage?   // 主屏（右前，完整可见）
    let shotB: NSImage?   // 副屏（左后，右缘被主屏压掉一部分）

    var body: some View {
        ZStack {
            // ── 背景：复刻 App 的 LiquidBackgroundModifier（底色 + 两团模糊光斑）
            theme.bg
            Circle()
                .fill(theme.blob1)
                .frame(width: CANVAS_H * 1.05, height: CANVAS_H * 1.05)
                .blur(radius: 420)
                .offset(x: -CANVAS_W * 0.30, y: -CANVAS_H * 0.34)
            Circle()
                .fill(theme.blob2)
                .frame(width: CANVAS_H * 0.95, height: CANVAS_H * 0.95)
                .blur(radius: 420)
                .offset(x: CANVAS_W * 0.36, y: CANVAS_H * 0.38)

            HStack(spacing: 0) {
                // ── 左：文案区
                copyBlock
                    .frame(width: CANVAS_W * 0.42, alignment: .leading)
                    .padding(.leading, CANVAS_W * 0.058)

                // ── 右：双机位
                phoneStack
                    .frame(width: CANVAS_W * 0.50, alignment: .center)
                    .padding(.trailing, CANVAS_W * 0.028)
            }
        }
        .frame(width: CANVAS_W, height: CANVAS_H)
    }

    private var copyBlock: some View {
        VStack(alignment: .leading, spacing: CANVAS_H * 0.045) {

            // 主标题
            VStack(alignment: .leading, spacing: CANVAS_H * 0.012) {
                ForEach(Array(copy.headline.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(copy.useGrotesk
                              ? .custom("SpaceGrotesk-Bold", size: CANVAS_H * copy.sizeMul)
                              : .system(size: CANVAS_H * copy.sizeMul, weight: .bold))
                        .foregroundStyle(theme.ink)
                        .fixedSize()
                }
            }

            // 像素风分隔条（呼应 App 内的 PixelProgressBar）
            Rectangle()
                .fill(theme.bar)
                .frame(width: CANVAS_W * 0.085, height: CANVAS_H * 0.008)

            // 副文案
            Text(copy.sub)
                .font(.system(size: CANVAS_H * 0.038, weight: .medium))
                .foregroundStyle(theme.muted)
                .fixedSize()
        }
    }

    private var phoneStack: some View {
        let phoneH = CANVAS_H * 0.74
        let phoneW = phoneH * (1206.0 / 2622.0)   // iPhone 17 屏幕比例

        return HStack(spacing: -phoneW * 0.16) {
            PhoneFrame(image: shotB, width: phoneW, height: phoneH, theme: theme)
                .rotationEffect(.degrees(-4))
                .offset(y: CANVAS_H * 0.035)
            PhoneFrame(image: shotA, width: phoneW, height: phoneH, theme: theme)
                .rotationEffect(.degrees(3))
                .offset(y: -CANVAS_H * 0.02)
        }
    }
}

// MARK: - 渲染 + 强制去 alpha
// Apple 原文：「Images can't include alpha channels or transparencies.」
// ImageRenderer 出的是 RGBA，必须重绘进 noneSkipLast 的 context 才能得到 RGB。

@MainActor
func stripAlpha(_ src: CGImage, fill: Color) -> CGImage? {
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    guard let ctx = CGContext(data: nil, width: src.width, height: src.height,
                              bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
    // 先铺不透明底色（与主题底色一致），杜绝任何「半透明被当成透明」的可能
    ctx.setFillColor(NSColor(fill).cgColor)
    ctx.fill(CGRect(x: 0, y: 0, width: src.width, height: src.height))
    ctx.draw(src, in: CGRect(x: 0, y: 0, width: src.width, height: src.height))
    return ctx.makeImage()
}

@MainActor
func render(theme: Theme, copy: Copy, shotA: NSImage?, shotB: NSImage?, label: String) {
    let renderer = ImageRenderer(content: Banner(theme: theme, copy: copy, shotA: shotA, shotB: shotB))
    renderer.scale = 1
    guard let cg = renderer.cgImage else { print("❌ \(label): 渲染失败"); return }
    guard let flat = stripAlpha(cg, fill: theme.bg) else { print("❌ \(label): 去 alpha 失败"); return }

    let rep = NSBitmapImageRep(cgImage: flat)
    rep.hasAlpha = false
    guard let data = rep.representation(using: .png, properties: [:]) else {
        print("❌ \(label): PNG 编码失败"); return
    }

    try? FileManager.default.createDirectory(atPath: OUT_DIR, withIntermediateDirectories: true)
    let out = "\(OUT_DIR)/\(label).png"
    try? data.write(to: URL(fileURLWithPath: out))

    let mb = Double(data.count) / 1_048_576.0
    print(String(format: "✓ %@  %dx%d  %.1f MB", out, flat.width, flat.height, mb))
}

// MARK: - 入口

registerFonts()

// 选图理由（改图前先读）：
//   主屏用「记一笔」而不是总览页——总览页顶部那个大字是**净资产**，而 DummyDataSeeder
//   生成的三年数据支出远大于收入，净资产是 -67 万，放在对外素材上很难看；
//   且「数字键盘 + 金额」一眼就说清这是**手动录入**的记账工具，正对本 App 的定位。
//   若将来换回总览页，先把演示数据调成净资产为正。
//
// 截图来源：中文 = `{base}-{theme}.png`，英文 = `{base}-{theme}-en.png`。
// 中英各一套（Apple 要求素材按语言分别出图）；深浅各一套——**手机里的界面必须与海报底色同一外观**，
// 深色海报上贴浅色截图会变成一块突兀的白。

/// 主屏 / 副屏的截图基名。换素材内容改这两行。
let SCREEN_MAIN = "14-addtx"        // 主屏：记一笔（数字键盘）
let SCREEN_SUB  = "11-transactions" // 副屏：流水列表
let args = CommandLine.arguments

MainActor.assumeIsolated {
    let all = !args.contains("--zh") && !args.contains("--en")
    let wantZH = all || args.contains("--zh")
    let wantEN = all || args.contains("--en")
    let themes: [Theme] = args.contains("--dark") ? [DARK]
                        : args.contains("--light") ? [LIGHT]
                        : [DARK, LIGHT]

    for theme in themes {
        for copy in [ZH, EN] where (copy.lang == "zh" ? wantZH : wantEN) {
            let a = loadShotOrFallback(base: SCREEN_MAIN, theme: theme.name, lang: copy.lang)
            let b = loadShotOrFallback(base: SCREEN_SUB,  theme: theme.name, lang: copy.lang)
            render(theme: theme, copy: copy, shotA: a, shotB: b,
                   label: "banner-\(copy.lang)-\(theme.name)")
        }
    }
}
