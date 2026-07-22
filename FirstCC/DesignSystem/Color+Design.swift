import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

// MARK: - Hex helpers

private func hexComponents(_ hex: String) -> (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) {
    let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
    var int: UInt64 = 0
    Scanner(string: hex).scanHexInt64(&int)
    let r, g, b, a: UInt64
    switch hex.count {
    case 6:  (r, g, b, a) = ((int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF, 255)
    case 8:  (r, g, b, a) = ((int >> 24) & 0xFF, (int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
    default: (r, g, b, a) = (128, 128, 128, 255)
    }
    return (CGFloat(r) / 255, CGFloat(g) / 255, CGFloat(b) / 255, CGFloat(a) / 255)
}

private func dynamicColor(lightHex: String, darkHex: String) -> Color {
    #if os(iOS)
    let l = hexComponents(lightHex)
    let d = hexComponents(darkHex)
    return Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: d.r, green: d.g, blue: d.b, alpha: d.a)
            : UIColor(red: l.r, green: l.g, blue: l.b, alpha: l.a)
    })
    #elseif os(macOS)
    let l = hexComponents(lightHex)
    let d = hexComponents(darkHex)
    return Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return isDark
            ? NSColor(red: d.r, green: d.g, blue: d.b, alpha: d.a)
            : NSColor(red: l.r, green: l.g, blue: l.b, alpha: l.a)
    }))
    #endif
}

// MARK: - Design System Colors

extension Color {

    // MARK: Surface hierarchy

    static var designSurface: Color                  { dynamicColor(lightHex: "#fcf9f8", darkHex: "#131313") }
    static var designSurfaceDim: Color               { dynamicColor(lightHex: "#dcd9d9", darkHex: "#131313") }
    static var designSurfaceBright: Color            { dynamicColor(lightHex: "#fcf9f8", darkHex: "#3a3939") }
    static var designSurfaceContainerLowest: Color   { dynamicColor(lightHex: "#ffffff", darkHex: "#0e0e0e") }
    static var designSurfaceContainerLow: Color      { dynamicColor(lightHex: "#f6f3f2", darkHex: "#1c1b1b") }
    static var designSurfaceContainer: Color         { dynamicColor(lightHex: "#f0edec", darkHex: "#201f1f") }
    static var designSurfaceContainerHigh: Color     { dynamicColor(lightHex: "#ebe7e7", darkHex: "#2a2a2a") }
    static var designSurfaceContainerHighest: Color  { dynamicColor(lightHex: "#e5e2e1", darkHex: "#353534") }
    static var designSurfaceVariant: Color           { dynamicColor(lightHex: "#e5e2e1", darkHex: "#353534") }
    static var designSurfaceTint: Color              { dynamicColor(lightHex: "#006d35", darkHex: "#00e471") }
    static var designBackground: Color               { dynamicColor(lightHex: "#fcf9f8", darkHex: "#131313") }
    static var designOnBackground: Color             { dynamicColor(lightHex: "#1c1b1b", darkHex: "#e5e2e1") }

    // MARK: Primary — green brand

    static var designPrimary: Color                  { dynamicColor(lightHex: "#006d35", darkHex: "#f0ffed") }
    static var designOnPrimary: Color                { dynamicColor(lightHex: "#ffffff", darkHex: "#003917") }
    static var designPrimaryContainer: Color         { dynamicColor(lightHex: "#00d16b", darkHex: "#00ff7f") }
    static var designOnPrimaryContainer: Color       { dynamicColor(lightHex: "#005326", darkHex: "#007134") }
    static var designInversePrimary: Color           { dynamicColor(lightHex: "#006d35", darkHex: "#006d33") }

    // Primary-fixed (stronger accent variants)
    static var designPrimaryFixed: Color             { dynamicColor(lightHex: "#1b7a42", darkHex: "#63ff93") }
    static var designPrimaryFixedDim: Color          { designAccentGreen }
    static var designOnPrimaryFixed: Color           { dynamicColor(lightHex: "#00210c", darkHex: "#00210b") }
    static var designOnPrimaryFixedVariant: Color    { dynamicColor(lightHex: "#005226", darkHex: "#005224") }

    // MARK: Secondary — red in dark, gray in light

    static var designSecondary: Color                { dynamicColor(lightHex: "#5c5f60", darkHex: "#ffb3af") }
    static var designOnSecondary: Color              { dynamicColor(lightHex: "#ffffff", darkHex: "#68000e") }
    static var designSecondaryContainer: Color       { dynamicColor(lightHex: "#e1e3e4", darkHex: "#91081a") }
    static var designOnSecondaryContainer: Color     { dynamicColor(lightHex: "#626566", darkHex: "#ff9994") }
    static var designSecondaryFixed: Color           { dynamicColor(lightHex: "#e1e3e4", darkHex: "#ffdad7") }
    static var designSecondaryFixedDim: Color        { dynamicColor(lightHex: "#c5c7c8", darkHex: "#ffb3af") }

    // MARK: Tertiary — purple in dark, gray in light

    static var designTertiary: Color                 { dynamicColor(lightHex: "#5d5f5f", darkHex: "#fff9ff") }
    static var designOnTertiary: Color               { dynamicColor(lightHex: "#ffffff", darkHex: "#3c0090") }
    static var designTertiaryContainer: Color        { dynamicColor(lightHex: "#b5b6b6", darkHex: "#e6d8ff") }
    static var designOnTertiaryContainer: Color      { dynamicColor(lightHex: "#464748", darkHex: "#7521ff") }

    // MARK: Text

    static var designOnSurface: Color                { dynamicColor(lightHex: "#1c1b1b", darkHex: "#e5e2e1") }
    static var designOnSurfaceVariant: Color         { dynamicColor(lightHex: "#3c4a3d", darkHex: "#b9cbb8") }
    static var designInverseOnSurface: Color         { dynamicColor(lightHex: "#f3f0ef", darkHex: "#313030") }
    static var designInverseSurface: Color           { dynamicColor(lightHex: "#313030", darkHex: "#e5e2e1") }

    // MARK: Outline

    static var designOutline: Color                  { dynamicColor(lightHex: "#6c7b6c", darkHex: "#849584") }
    static var designOutlineVariant: Color           { dynamicColor(lightHex: "#bbcbba", darkHex: "#3b4b3c") }

    // MARK: Error

    static var designError: Color                    { dynamicColor(lightHex: "#ba1a1a", darkHex: "#ffb4ab") }
    static var designOnError: Color                  { dynamicColor(lightHex: "#ffffff", darkHex: "#690005") }
    static var designErrorContainer: Color           { dynamicColor(lightHex: "#ffdad6", darkHex: "#93000a") }
    static var designOnErrorContainer: Color         { dynamicColor(lightHex: "#93000a", darkHex: "#ffdad6") }

    // MARK: Glass — 8-char hex for per-mode alpha

    static var designGlassBg: Color                 { dynamicColor(lightHex: "FFFFFF66", darkHex: "FFFFFF08") }
    static var designGlassBgModal: Color            { dynamicColor(lightHex: "FFFFFFB2", darkHex: "FFFFFF14") }
    static var designGlassBorderHighlight: Color    { dynamicColor(lightHex: "FFFFFF4D", darkHex: "FFFFFF33") }
    static var designGlassBorderShadow: Color       { dynamicColor(lightHex: "FFFFFF00", darkHex: "FFFFFF0D") }

    // MARK: Convenience aliases

    static var designAccentGreen: Color              { dynamicColor(lightHex: "#006d35", darkHex: "#00ff7f") }
    static var designAccentPurple: Color             { dynamicColor(lightHex: "#7521ff", darkHex: "#d1bcff") }
    static var designAccentRed: Color                { dynamicColor(lightHex: "#ba1a1a", darkHex: "#ffb4ab") }

    // MARK: Progress state — 进度条 4 档阈值语义
    // Warning / Caution 底层用系统色，自动适配 light/dark。
    // 4 档阈值切色见 `Color.progressTint(for:)`。

    static var designProgressWarning: Color {
        #if os(iOS)
        Color(uiColor: .systemYellow)
        #elseif os(macOS)
        Color(nsColor: .systemYellow)
        #endif
    }

    static var designProgressCaution: Color {
        #if os(iOS)
        Color(uiColor: .systemOrange)
        #elseif os(macOS)
        Color(nsColor: .systemOrange)
        #endif
    }

    /// 4 档阈值切色：>100% 红 / 80-100% 橙 / 50-80% 黄 / <50% 绿。
    /// iOS / macOS 共用，iOS 3 处 + macOS 2 处调用点统一收口。
    static func progressTint(for ratio: Double) -> Color {
        if ratio > 1.0  { return .designAccentRed }
        if ratio >= 0.8 { return .designProgressCaution }
        if ratio >= 0.5 { return .designProgressWarning }
        return .designAccentGreen
    }
}
