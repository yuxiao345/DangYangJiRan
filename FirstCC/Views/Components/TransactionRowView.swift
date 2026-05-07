import SwiftUI

struct TransactionRowView: View {
    let transaction: Transaction

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .font(.title3)
                .foregroundStyle(iconColor)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(LocalizedStringKey(titleText))
                        .font(.body)
                    if transaction.isReimbursable {
                        let reimbursed = transaction.reimbursementStatus == .reimbursed
                        Text(LocalizedStringKey(reimbursed ? "已报销" : "待报销"))
                            .font(.caption2)
                            .padding(.horizontal, 4)
                            .background((reimbursed ? Color.green : Color.orange).opacity(0.15))
                            .foregroundStyle(reimbursed ? .green : .orange)
                            .clipShape(Capsule())
                    }
                    if transaction.refundGroupId != nil {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.caption2)
                            .foregroundStyle(.blue)
                    }
                    if let photos = transaction.photoURLs, !photos.isEmpty {
                        Image(systemName: "camera.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                if let subtitle = subtitleText {
                    Text(LocalizedStringKey(subtitle))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                amountView
                Text(transaction.date.formatted(date: .numeric, time: .omitted))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private var iconName: String {
        transaction.category?.iconName ?? transaction.type.systemIcon
    }

    private var iconColor: Color {
        switch transaction.type {
        case .income: .green
        case .expense: .red
        case .transfer: .blue
        case .lending: .orange
        case .adjustment: .purple
        }
    }

    private var titleText: String {
        if transaction.type == .lending, let cp = transaction.counterparty {
            return cp
        }
        return transaction.category?.name ?? transaction.type.displayName
    }

    private var subtitleText: String? {
        if transaction.type == .lending {
            return transaction.note
        }
        return transaction.note
    }

    @ViewBuilder
    private var amountView: some View {
        switch transaction.type {
        case .income:
            CurrencyText(amount: abs(transaction.amount), currencyCode: transaction.currencyCode, font: .body, foregroundColor: .green)
        case .expense:
            CurrencyText(amount: abs(transaction.amount), currencyCode: transaction.currencyCode, font: .body, foregroundColor: .red)
        case .transfer:
            HStack(spacing: 0) {
                Text("↔")
                CurrencyText(amount: abs(transaction.amount), currencyCode: transaction.currencyCode, font: .body, foregroundColor: .blue)
            }
        case .lending:
            CurrencyText(amount: abs(transaction.amount), currencyCode: transaction.currencyCode, showSign: transaction.amount > 0, font: .body, foregroundColor: transaction.amount >= 0 ? .green : .orange)
        case .adjustment:
            CurrencyText(amount: transaction.amount, currencyCode: transaction.currencyCode, showSign: true, font: .body, foregroundColor: transaction.amount >= 0 ? .green : .red)
        }
    }
}
