import SwiftUI
import AppKit

// ============================================================
// App Store 创意素材生成器 —— Header 21:9 / Search 3:2 / 通用 16:9
// ============================================================
// 规格来源（Apple 官方，2026-10-05 启用）：
//   https://developer.apple.com/help/app-store-connect/reference/app-information/creative-assets-specifications
//   https://developer.apple.com/app-store/asset-best-practices/
//
//   · 16:9 PNG  5244 x 2950  —— 「通用素材」，可同时用于产品页页眉与搜索结果
//   · 21:9      3840 x 1646  —— 仅产品页页眉
//   · 3:2       1920x1280 ~ 3840x2560 —— 仅搜索结果
//   · 图片不得含 alpha 通道 / 透明      ← 脚本末尾 stripAlpha() 强制保证
//   · 素材需满足 4+ 分级；禁止出现价格、折扣、网址、版权符、未获得的奖项
//   · 只在 iOS 27 / iPadOS 27 及以上显示（Mac 端无此素材位）
//
// ── 安全区（ART SAFE AREA）────────────────────────────────
// Apple 在网页上**没有公布**安全区数值，只在 best-practices 里写了一句
//   「Be sure your focal point artwork is within the center of your composition
//     to prevent any unwanted clipping.」
// 数字只存在于官方模板文件里。下面这套值是从官方 Sketch 模板
//   creative_assets-templates.sketch → pages/*.json
// 的 `Art Safe Area` 图层取出来的，并用模板自带的 preview.png 做了**像素级复核**
// （通用版实测 左右各 36.60%、上 22.39%、下 45.02%，占宽 26.73%、占高 32.61%，
//  与图层几何完全吻合）。
//
// 结论：**背景可以出血，品牌文案与焦点必须落在安全区内。**
// 安全区外的东西在某些设备/方向下会被裁掉——Apple 明确说它不公布裁剪算法，
// 只让你用 ASC 的 Preview 工具看实际效果。所以别赌，文案一律放安全区里。
//
// 用法：
//   swift tools/appstore-assets/make_banner.swift                  # 全部格式 × 中英 × 深浅
//   swift tools/appstore-assets/make_banner.swift --zh --light     # 只出中文浅色
//   swift tools/appstore-assets/make_banner.swift --format=header  # 只出 21:9 页眉
//   （可组合：--zh --light --format=search）
//
// 输入：tools/appstore-assets/screenshots/ 下的真机截图（见该目录 README 的拍摄说明）
// 输出：tools/appstore-assets/output/{header-21x9,search-3x2,universal-16x9}-{zh,en}-{dark,light}.png
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

// MARK: - 格式与安全区

/// 一种上传格式：画布尺寸 + 官方安全区（都用相对画布的比例表示，避免写死像素）。
struct Format {
    let key: String         // 进文件名
    let title: String
    let w: CGFloat
    let h: CGFloat
    let safeL: CGFloat
    let safeR: CGFloat
    let safeT: CGFloat
    let safeB: CGFloat

    var safeW: CGFloat { (safeR - safeL) * w }
    var safeH: CGFloat { (safeB - safeT) * h }
    var safeMidX: CGFloat { (safeL + safeR) / 2 * w }
    var safeMidY: CGFloat { (safeT + safeB) / 2 * h }
    var safeDesc: String {
        String(format: "安全区 %.0fx%.0f (占宽 %.1f%% 占高 %.1f%%)  左边距 %.1f%% 上边距 %.1f%%",
               safeW, safeH, safeW / w * 100, safeH / h * 100, safeL * 100, safeT * 100)
    }
}

/// 三套安全区数值均取自官方模板 `Art Safe Area` 图层（见文件头注释）。
let FORMATS: [Format] = [
    // 官方模板画板 "Header - 3840x1646"：安全区本地坐标 x 1097→2743、y 493→1154，
    // 即 1646x661，左右各留 1097（3840/2 = 1920 正好落在安全区正中）。
    Format(key: "header-21x9", title: "产品页页眉", w: 3840, h: 1646,
           safeL: 1097.0 / 3840, safeR: 2743.0 / 3840,
           safeT: 493.0 / 1646,  safeB: 1154.0 / 1646),

    // 官方模板画板 "Search Result - 3840x2560"，安全区 2168x1030，四边等距
    Format(key: "search-3x2", title: "搜索结果", w: 3840, h: 2560,
           safeL: 836.0 / 3840, safeR: 3004.0 / 3840,
           safeT: 765.0 / 2560, safeB: 1795.0 / 2560),

    // 官方模板画板 "16x9Universal - 5244x2950"，安全区 1402x962。
    // ⚠️ 三套里**最窄**的一个（只占画布宽 26.7%）——因为它要同时适配页眉和搜索两种位置。
    //    纵向也不是居中的：上 22.4%、下 45.0%，安全区偏上。
    Format(key: "universal-16x9", title: "通用素材", w: 5244, h: 2950,
           safeL: 1921.0 / 5244, safeR: 3323.0 / 5244,
           safeT: 660.0 / 2950,  safeB: 1622.0 / 2950),
]

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
    let name: String            // 进文件名：{format}-{lang}-{name}.png
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
    let headline: [String]    // 逐行，手动断行
    let sub: String
    let useGrotesk: Bool      // 拉丁文案用品牌字体；中文走系统字体（与 App 内一致）
    /// 主标题字号相对**安全区高度**的比例。
    /// 以安全区为基准而不是画布，是为了让同一套参数在三种宽高比下都装得进安全区。
    let headlineScale: CGFloat
    /// 副标题占主标题字号的比例
    let subScale: CGFloat
}

let ZH = Copy(
    lang: "zh",
    headline: ["隐私优先的", "手记账本"],
    sub: "无广告 · 无追踪 · 家庭共享账本",
    useGrotesk: false,
    headlineScale: 0.240,
    subScale: 0.40
)

let EN = Copy(
    lang: "en",
    headline: ["Private manual", "bookkeeping"],
    sub: "No ads. No tracking. Shared with family.",
    useGrotesk: true,
    headlineScale: 0.205,
    subScale: 0.44
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
    let name = shotName(base: base, theme: theme, lang: lang)
    if lang == "zh" || FileManager.default.fileExists(atPath: "\(SHOT_DIR)/\(name)") {
        return loadShot(base: base, theme: theme, lang: lang)
    }
    print("⚠️ 缺英文截图 \(name)，英文版将回落到中文界面（需重拍）")
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

// MARK: - 文案块（单独成 View，便于用真实布局尺寸做安全区校对）

struct CopyBlockView: View {
    let theme: Theme
    let copy: Copy
    let format: Format
    /// 实际使用的比例（由 fittedHeadlineScale 决定，可能小于 copy.headlineScale）
    let headlineScale: CGFloat

    var body: some View {
        let headlineSize = format.safeH * headlineScale
        let subSize = headlineSize * copy.subScale
        let barH = max(6, format.safeH * 0.024)

        VStack(spacing: 0) {
            // 主标题
            VStack(spacing: headlineSize * 0.10) {
                ForEach(Array(copy.headline.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(copy.useGrotesk
                              ? .custom("SpaceGrotesk-Bold", size: headlineSize)
                              : .system(size: headlineSize, weight: .bold))
                        .foregroundStyle(theme.ink)
                        .fixedSize()
                }
            }

            // 像素风分隔条（呼应 App 内的 PixelProgressBar）
            Rectangle()
                .fill(theme.bar)
                .frame(width: format.safeW * 0.30, height: barH)
                .padding(.top, format.safeH * 0.085)

            // 副文案
            Text(copy.sub)
                .font(.system(size: subSize, weight: .medium))
                .foregroundStyle(theme.muted)
                .fixedSize()
                .padding(.top, format.safeH * 0.075)
        }
    }
}

/// 量文案块的**真实布局尺寸**（不是像素测量——手机阴影会干扰像素法）。
@MainActor
func copyBlockSize(theme: Theme, copy: Copy, format: Format, headlineScale: CGFloat) -> CGSize {
    NSHostingView(rootView: CopyBlockView(theme: theme, copy: copy, format: format,
                                          headlineScale: headlineScale)).fittingSize
}

/// 把文案自动缩到装得进安全区为止（目标：占安全区不超过 96%，四边留呼吸）。
/// 三种格式的安全区宽窄差很多（通用版只占画布宽 26.7%），
/// 用同一个比例必然有一种装不下；与其手调一个魔数，不如让它按各自的安全区自适应。
/// 返回实际使用的比例——比 copy.headlineScale 小就说明被缩过，调用方会打印出来。
@MainActor
func fittedHeadlineScale(theme: Theme, copy: Copy, format: Format) -> CGFloat {
    var scale = copy.headlineScale
    for _ in 0..<12 {
        let s = copyBlockSize(theme: theme, copy: copy, format: format, headlineScale: scale)
        let f = min(format.safeW / s.width, format.safeH / s.height)
        if f >= 1.04 { break }          // 已留 ≥4% 余量
        // f < 1（放不下）时按 f 一步缩到位；1 ≤ f < 1.04（勉强放下但余量不够）时每轮再收 3%。
        // 少了后一种情况会卡在 1.0x 的余量上不动——之前就是这么停在 1.5% 的。
        scale *= min(f, 1.0) * 0.97
    }
    return scale
}

// MARK: - 主画面
//
// 构图：**背景出血 + 品牌文案居中进安全区 + 左右两台手机**。
// 这与 Apple 官方示例的做法一致（页眉里文字/标志居中，森林、海景这些背景满幅出血）。
// 之前的「左文案 + 右手机」是屏幕截图海报的套路，焦点铺满整幅，
// 一旦按安全区裁剪就什么都不剩——所以整个版式推倒重来。

struct Banner: View {
    let theme: Theme
    let copy: Copy
    let format: Format
    let headlineScale: CGFloat
    let shotA: NSImage?   // 主屏（右侧）
    let shotB: NSImage?   // 副屏（左侧）

    var body: some View {
        ZStack {
            // ── 背景：复刻 App 的 LiquidBackgroundModifier（底色 + 两团模糊光斑），满幅出血
            theme.bg
            Circle()
                .fill(theme.blob1)
                .frame(width: format.h * 1.05, height: format.h * 1.05)
                .blur(radius: format.h * 0.14)
                .offset(x: -format.w * 0.30, y: -format.h * 0.34)
            Circle()
                .fill(theme.blob2)
                .frame(width: format.h * 0.95, height: format.h * 0.95)
                .blur(radius: format.h * 0.14)
                .offset(x: format.w * 0.36, y: format.h * 0.38)

            // ── 左右两台手机：只露一部分，允许被裁（装饰性内容）
            phoneBleed

            // ── 文案块：居中落在安全区内（不可裁的内容）
            CopyBlockView(theme: theme, copy: copy, format: format, headlineScale: headlineScale)
                .frame(width: format.safeW, height: format.safeH)
                .position(x: format.safeMidX, y: format.safeMidY)
        }
        .frame(width: format.w, height: format.h)
        .clipped()
    }

    // 手机分列左右，内侧边缘贴着安全区外沿。竖直方向完整可见（不裁上下）。
    // 手机是**装饰性内容**，允许被裁——真有更狠的裁剪时丢掉的是它，不是文案。
    private var phoneBleed: some View {
        let phoneH = format.h * 0.86
        let phoneW = phoneH * (1206.0 / 2622.0)   // iPhone 17 屏幕比例
        let y = format.h * 0.53
        let deg = 5.0
        let rad = deg * .pi / 180
        // 旋转后包围盒会变宽，定位要用旋转后的半宽，否则转角会戳进安全区
        let halfW = (phoneW / 2) * cos(rad) + (phoneH / 2) * sin(rad)
        // 内侧边缘距安全区留 2% 画布宽的空隙
        let inner = format.safeL * format.w - format.w * 0.02

        return ZStack {
            PhoneFrame(image: shotB, width: phoneW, height: phoneH, theme: theme)
                .rotationEffect(.degrees(-deg))
                .position(x: inner - halfW, y: y)
            PhoneFrame(image: shotA, width: phoneW, height: phoneH, theme: theme)
                .rotationEffect(.degrees(deg))
                .position(x: format.w - inner + halfW, y: y)
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
func render(theme: Theme, copy: Copy, format: Format,
            headlineScale: CGFloat, shotA: NSImage?, shotB: NSImage?) {
    let label = "\(format.key)-\(copy.lang)-\(theme.name)"
    let renderer = ImageRenderer(content: Banner(theme: theme, copy: copy, format: format,
                                                 headlineScale: headlineScale,
                                                 shotA: shotA, shotB: shotB))
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
    print(String(format: "✓ %@  %dx%d  %.1f MB", label, flat.width, flat.height, mb))
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

/// `--format=header` / `--format=search` / `--format=universal`，缺省出全部三种
func wantedFormats(_ args: [String]) -> [Format] {
    guard let raw = args.first(where: { $0.hasPrefix("--format=") })?
        .split(separator: "=").last.map(String.init) else { return FORMATS }
    let hit = FORMATS.filter { $0.key.hasPrefix(raw) }
    if hit.isEmpty {
        print("⚠️ 未知 --format=\(raw)；可用：header / search / universal。改为输出全部。")
        return FORMATS
    }
    return hit
}

MainActor.assumeIsolated {
    let all = !args.contains("--zh") && !args.contains("--en")
    let wantZH = all || args.contains("--zh")
    let wantEN = all || args.contains("--en")
    let themes: [Theme] = args.contains("--dark") ? [DARK]
                        : args.contains("--light") ? [LIGHT]
                        : [DARK, LIGHT]

    for format in wantedFormats(args) {
        print("▸ \(format.title) \(format.key)  \(Int(format.w))x\(Int(format.h))  \(format.safeDesc)")
        for copy in [ZH, EN] where (copy.lang == "zh" ? wantZH : wantEN) {
            // 按各自安全区自适应字号。文案块的布局尺寸只取决于 format + copy + scale，
            // theme 仅提供颜色、不参与布局，所以量一次即可，不必每个外观重量一遍。
            let probe = themes[0]
            let scale = fittedHeadlineScale(theme: probe, copy: copy, format: format)
            let s = copyBlockSize(theme: probe, copy: copy, format: format, headlineScale: scale)
            let shrunk = scale < copy.headlineScale - 1e-6
            print(String(format: "  %@ %@ 文案块 %.0fx%.0f / 安全区 %.0fx%.0f  余量 %.0fx%.0f%@",
                         copy.lang, shrunk ? "⚠️" : "✅", s.width, s.height,
                         format.safeW, format.safeH,
                         format.safeW - s.width, format.safeH - s.height,
                         shrunk ? String(format: "  （已自动缩到 %.3f，原设 %.3f）",
                                         scale, copy.headlineScale) : ""))

            for theme in themes {
                let a = loadShotOrFallback(base: SCREEN_MAIN, theme: theme.name, lang: copy.lang)
                let b = loadShotOrFallback(base: SCREEN_SUB,  theme: theme.name, lang: copy.lang)
                render(theme: theme, copy: copy, format: format,
                       headlineScale: scale, shotA: a, shotB: b)
            }
        }
    }
}
