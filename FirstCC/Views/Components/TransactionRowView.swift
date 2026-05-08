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
                    if transaction.isLending {
                        lendingStatusBadge
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
        if let d = transaction.lendingDirection { return d.systemIcon }
        return transaction.category?.iconName ?? transaction.type.systemIcon
    }

    private var iconColor: Color {
        if transaction.isLending {
            switch transaction.lendingDirection {
            case .lendOut, .repay: return .orange
            case .borrowIn, .collect: return .green
            case .none: return .orange
            }
        }
        switch transaction.type {
        case .income: return .green
        case .expense: return .red
        case .transfer: return .blue
        case .lending: break
        case .adjustment: return .purple
        }
        return .secondary
    }

    private var titleText: String {
        if let d = transaction.lendingDirection { return d.displayName }
        return transaction.category?.name ?? transaction.type.displayName
    }

    private var subtitleText: String? {
        if transaction.isLending {
            let from = transaction.account?.name ?? "—"
            let to = transaction.toAccount?.name ?? "—"
            return "\(NSLocalizedString(from, comment: "")) → \(NSLocalizedString(to, comment: ""))"
        }
        return transaction.note
    }

    @ViewBuilder
    private var amountView: some View {
        switch transaction.type {
        case .income:
            CurrencyText(amount: transaction.amount, currencyCode: transaction.currencyCode, showSign: true, font: .body, foregroundColor: .green)
        case .expense:
            CurrencyText(amount: transaction.amount, currencyCode: transaction.currencyCode, showSign: true, font: .body, foregroundColor: .red)
        case .transfer:
            HStack(spacing: 0) {
                Text("↔")
                CurrencyText(amount: abs(transaction.amount), currencyCode: transaction.currencyCode, font: .body, foregroundColor: .blue)
            }
        case .lending:
            CurrencyText(amount: transaction.amount, currencyCode: transaction.currencyCode, showSign: true, font: .body, foregroundColor: transaction.amount >= 0 ? .green : .orange)
        case .adjustment:
            CurrencyText(amount: transaction.amount, currencyCode: transaction.currencyCode, showSign: true, font: .body, foregroundColor: transaction.amount >= 0 ? .green : .red)
        }
    }

    @ViewBuilder
    private var lendingStatusBadge: some View {
        if let d = transaction.lendingDirection {
            switch transaction.lendingStatus {
            case .pending:
                Text(LocalizedStringKey(d.pendingLabel))
                    .font(.caption2)
                    .padding(.horizontal, 4)
                    .background(Color.orange.opacity(0.15))
                    .foregroundStyle(.orange)
                    .clipShape(Capsule())
            case .settled:
                Text(LocalizedStringKey("已结清"))
                    .font(.caption2)
                    .padding(.horizontal, 4)
                    .background(Color.green.opacity(0.15))
                    .foregroundStyle(.green)
                    .clipShape(Capsule())
            case .none: EmptyView()
            }
        }
    }
}
