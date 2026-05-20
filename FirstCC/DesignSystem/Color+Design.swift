import SwiftUI
import UIKit

private func uiColorFromHex(_ hex: String) -> UIColor {
    let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
    var int: UInt64 = 0
    Scanner(string: hex).scanHexInt64(&int)
    let r, g, b, a: UInt64
    switch hex.count {
    case 6:
        (r, g, b, a) = ((int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF, 255)
    case 8:
        (r, g, b, a) = ((int >> 24) & 0xFF, (int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
    default:
        (r, g, b, a) = (128, 128, 128, 255)
    }
    return UIColor(red: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: CGFloat(a) / 255)
}

// MARK: - Design System Colors
//
// Uses UIColor(dynamicProvider:) → Color(uiColor:) so SwiftUI re-evaluates
// the color for the current trait collection on every render pass.

extension Color {

    // MARK: Surface hierarchy

    static var designSurface: Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? uiColorFromHex("#131313") : uiColorFromHex("#fcf9f8") })
    }
    static var designSurfaceDim: Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? uiColorFromHex("#131313") : uiColorFromHex("#dcd9d9") })
    }
    static var designSurfaceBright: Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? uiColorFromHex("#3a3939") : uiColorFromHex("#fcf9f8") })
    }
    static var designSurfaceContainerLowest: Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? uiColorFromHex("#0e0e0e") : uiColorFromHex("#ffffff") })
    }
    static var designSurfaceContainerLow: Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? uiColorFromHex("#1c1b1b") : uiColorFromHex("#f6f3f2") })
    }
    static var designSurfaceContainer: Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? uiColorFromHex("#201f1f") : uiColorFromHex("#f0edec") })
    }
    static var designSurfaceContainerHigh: Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? uiColorFromHex("#2a2a2a") : uiColorFromHex("#ebe7e7") })
    }
    static var designSurfaceContainerHighest: Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? uiColorFromHex("#353534") : uiColorFromHex("#e5e2e1") })
    }
    static var designSurfaceVariant: Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? uiColorFromHex("#353534") : uiColorFromHex("#e5e2e1") })
    }
    static var designSurfaceTint: Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? uiColorFromHex("#00e471") : uiColorFromHex("#006d35") })
    }
    static var designBackground: Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? uiColorFromHex("#131313") : uiColorFromHex("#fcf9f8") })
    }
    static var designOnBackground: Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? uiColorFromHex("#e5e2e1") : uiColorFromHex("#1c1b1b") })
    }

    // MARK: Primary — green brand

    static var designPrimary: Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? uiColorFromHex("#f0ffed") : uiColorFromHex("#006d35") })
    }
    static var designOnPrimary: Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? uiColorFromHex("#003917") : uiColorFromHex("#ffffff") })
    }
    static var designPrimaryContainer: Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? uiColorFromHex("#00ff7f") : uiColorFromHex("#00d16b") })
    }
    static var designOnPrimaryContainer: Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? uiColorFromHex("#007134") : uiColorFromHex("#005326") })
    }
    static var designInversePrimary: Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? uiColorFromHex("#006d33") : uiColorFromHex("#006d35") })
    }

    // Primary-fixed (stronger accent variants)
    static var designPrimaryFixed: Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? uiColorFromHex("#63ff93") : uiColorFromHex("#1b7a42") })
    }
    static var designPrimaryFixedDim: Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? uiColorFromHex("#00e471") : uiColorFromHex("#006d35") })
    }
    static var designOnPrimaryFixed: Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? uiColorFromHex("#00210b") : uiColorFromHex("#00210c") })
    }
    static var designOnPrimaryFixedVariant: Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? uiColorFromHex("#005224") : uiColorFromHex("#005226") })
    }

    // MARK: Secondary — red in dark, gray in light

    static var designSecondary: Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? uiColorFromHex("#ffb3af") : uiColorFromHex("#5c5f60") })
    }
    static var designOnSecondary: Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? uiColorFromHex("#68000e") : uiColorFromHex("#ffffff") })
    }
    static var designSecondaryContainer: Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? uiColorFromHex("#91081a") : uiColorFromHex("#e1e3e4") })
    }
    static var designOnSecondaryContainer: Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? uiColorFromHex("#ff9994") : uiColorFromHex("#626566") })
    }
    static var designSecondaryFixed: Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? uiColorFromHex("#ffdad7") : uiColorFromHex("#e1e3e4") })
    }
    static var designSecondaryFixedDim: Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? uiColorFromHex("#ffb3af") : uiColorFromHex("#c5c7c8") })
    }

    // MARK: Tertiary — purple in dark, gray in light

    static var designTertiary: Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? uiColorFromHex("#fff9ff") : uiColorFromHex("#5d5f5f") })
    }
    static var designOnTertiary: Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? uiColorFromHex("#3c0090") : uiColorFromHex("#ffffff") })
    }
    static var designTertiaryContainer: Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? uiColorFromHex("#e6d8ff") : uiColorFromHex("#b5b6b6") })
    }
    static var designOnTertiaryContainer: Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? uiColorFromHex("#7521ff") : uiColorFromHex("#464748") })
    }

    // MARK: Text

    static var designOnSurface: Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? uiColorFromHex("#e5e2e1") : uiColorFromHex("#1c1b1b") })
    }
    static var designOnSurfaceVariant: Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? uiColorFromHex("#b9cbb8") : uiColorFromHex("#3c4a3d") })
    }
    static var designInverseOnSurface: Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? uiColorFromHex("#313030") : uiColorFromHex("#f3f0ef") })
    }
    static var designInverseSurface: Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? uiColorFromHex("#e5e2e1") : uiColorFromHex("#313030") })
    }

    // MARK: Outline

    static var designOutline: Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? uiColorFromHex("#849584") : uiColorFromHex("#6c7b6c") })
    }
    static var designOutlineVariant: Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? uiColorFromHex("#3b4b3c") : uiColorFromHex("#bbcbba") })
    }

    // MARK: Error

    static var designError: Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? uiColorFromHex("#ffb4ab") : uiColorFromHex("#ba1a1a") })
    }
    static var designOnError: Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? uiColorFromHex("#690005") : uiColorFromHex("#ffffff") })
    }
    static var designErrorContainer: Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? uiColorFromHex("#93000a") : uiColorFromHex("#ffdad6") })
    }
    static var designOnErrorContainer: Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? uiColorFromHex("#ffdad6") : uiColorFromHex("#93000a") })
    }

    // MARK: Glass — 8-char hex for per-mode alpha

    static var designGlassBg: Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? uiColorFromHex("FFFFFF08") : uiColorFromHex("FFFFFF66") })
    }
    static var designGlassBgModal: Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? uiColorFromHex("FFFFFF14") : uiColorFromHex("FFFFFFB2") })
    }
    static var designGlassBorderHighlight: Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? uiColorFromHex("FFFFFF33") : uiColorFromHex("FFFFFF4D") })
    }
    static var designGlassBorderShadow: Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? uiColorFromHex("FFFFFF0D") : uiColorFromHex("FFFFFF00") })
    }

    // MARK: Convenience aliases

    static var designAccentGreen: Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? uiColorFromHex("#00ff7f") : uiColorFromHex("#006d35") })
    }
    static var designAccentPurple: Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? uiColorFromHex("#d1bcff") : uiColorFromHex("#7521ff") })
    }
    static var designAccentRed: Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? uiColorFromHex("#ffb4ab") : uiColorFromHex("#ba1a1a") })
    }
}
