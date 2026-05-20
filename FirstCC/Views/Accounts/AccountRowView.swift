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
        HStack(spacing: 12) {
            accountIcon
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(account.name))
                    .font(.designBodyMedium)
                Text(account.type.displayName)
                    .font(.designBodySmall)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                CurrencyText(amount: balance, currencyCode: account.currencyCode, showSign: true, size: 17, foregroundColor: balance >= 0 ? .green : .red)

                if account.type == .lending, let info = lendingInfo {
                    HStack(spacing: 4) {
                        Text("应收")
                            .font(.designBodySmall)
                            .foregroundStyle(.secondary)
                        CurrencyText(amount: info.lendOutPending, currencyCode: account.currencyCode, showSign: false, size: 11, foregroundColor: info.lendOutPending > 0 ? .orange : .secondary)
                    }
                    HStack(spacing: 4) {
                        Text("应付")
                            .font(.designBodySmall)
                            .foregroundStyle(.secondary)
                        CurrencyText(amount: info.borrowInPending, currencyCode: account.currencyCode, showSign: false, size: 11, foregroundColor: info.borrowInPending > 0 ? .blue : .secondary)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var accountIcon: some View {
        if let data = account.customIconData, let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 4))
        } else {
            Image(systemName: account.iconName ?? "creditcard")
                .font(.title3)
                .foregroundStyle(accountColor)
        }
    }

    private var accountColor: Color {
        if let hex = account.colorHex {
            Color(hex: hex)
        } else {
            .blue
        }
    }
}
