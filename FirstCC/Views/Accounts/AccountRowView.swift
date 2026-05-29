import SwiftUI

struct AccountRowView: View {
    let account: Account
    let balance: Decimal
    var lendingInfo: LendingAccountInfo? = nil

    struct LendingAccountInfo {
        let lendOutPending: Decimal
        let borrowInPending: Decimal
    }

    var body: some View {
        HStack(spacing: 10) {
            iconView
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 9)
                        .fill(Color.designSurfaceContainer.opacity(0.6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 9)
                                .stroke(accentColor.opacity(0.3), lineWidth: 1)
                        )
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(account.name))
                    .font(.designBodyMedium)
                    .foregroundStyle(Color.designOnSurface)
                if let badge = typeBadge {
                    Text(badge)
                        .font(.custom("JetBrainsMono-Medium", fixedSize: 10))
                        .foregroundStyle(accentColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(accentColor.opacity(0.12))
                        .clipShape(Capsule())
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                CurrencyText(
                    amount: balance,
                    currencyCode: account.currencyCode,
                    showSign: true,
                    size: 17,
                    foregroundColor: balanceColor
                )

                if account.type == .lending, let info = lendingInfo {
                    lendingSubtext(info: info)
                }
            }
        }
        .padding(14)
        .glassCard(cornerRadius: 16)
    }

    // MARK: - Icon

    private var iconView: some View {
        Image(systemName: account.iconName ?? account.type.systemIcon)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(accentColor)
    }

    // MARK: - Badge

    private var typeBadge: String? {
        switch account.type {
        case .creditCard:
            if balance < 0 { return "待还款" }
            return nil
        case .lending:
            return "借贷"
        default:
            return nil
        }
    }

    // MARK: - Lending subtext

    private func lendingSubtext(info: LendingAccountInfo) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if info.lendOutPending > 0 {
                HStack(spacing: 4) {
                    Text("应收")
                        .font(.designBodySmall)
                        .foregroundStyle(Color.designOnSurfaceVariant)
                    CurrencyText(amount: info.lendOutPending, currencyCode: account.currencyCode, showSign: false, size: 11, foregroundColor: .orange)
                }
            }
            if info.borrowInPending > 0 {
                HStack(spacing: 4) {
                    Text("应付")
                        .font(.designBodySmall)
                        .foregroundStyle(Color.designOnSurfaceVariant)
                    CurrencyText(amount: info.borrowInPending, currencyCode: account.currencyCode, showSign: false, size: 11, foregroundColor: .blue)
                }
            }
        }
    }

    // MARK: - Colors

    private var accentColor: Color {
        Color.accountAccent(for: account.type)
    }

    private var balanceColor: Color {
        if account.type == .creditCard {
            return balance < 0 ? .designAccentRed : .designPrimaryFixedDim
        }
        return balance >= 0 ? .designPrimaryFixedDim : .designAccentRed
    }
}
