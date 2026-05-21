import SwiftUI

extension Color {
    static func accountAccent(for type: AccountType) -> Color {
        switch type {
        case .cash, .debitCard: return .designPrimaryFixedDim
        case .creditCard: return .designSecondaryFixedDim
        case .eWallet: return .designAccentPurple
        case .housingFund: return .orange
        case .investment: return .blue
        case .loan: return .designAccentRed
        case .insurance: return .teal
        case .lending: return .orange
        case .other: return .designOnSurfaceVariant
        }
    }

    static func expenseHeat(fraction: Double) -> Color {
        let f = max(0, min(1, fraction))
        if f <= 0 { return .clear }

        // 3-stop gradient: light pink -> medium red -> deep red
        let r: Double
        let g: Double
        let b: Double

        if f < 0.4 {
            let t = f / 0.4
            r = 1.0
            g = 0.85 - t * 0.33
            b = 0.87 - t * 0.14
        } else if f < 0.75 {
            let t = (f - 0.4) / 0.35
            r = 1.0 - t * 0.02
            g = 0.52 - t * 0.24
            b = 0.73 - t * 0.28
        } else {
            let t = (f - 0.75) / 0.25
            r = 0.98 - t * 0.10
            g = 0.28 - t * 0.21
            b = 0.45 - t * 0.23
        }

        return Color(red: r, green: g, blue: b)
    }
}
