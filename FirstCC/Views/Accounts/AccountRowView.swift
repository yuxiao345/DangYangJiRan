import SwiftUI

struct AccountRowView: View {
    let account: Account
    let balance: Decimal

    var body: some View {
        HStack(spacing: 12) {
            accountIcon
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(account.name))
                    .font(.body)
                Text(account.type.displayName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            CurrencyText(amount: abs(balance), currencyCode: account.currencyCode, font: .body, foregroundColor: balance >= 0 ? .primary : Color.red)
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
