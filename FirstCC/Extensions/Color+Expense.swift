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
}
