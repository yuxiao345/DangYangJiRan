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
                        .font(.designBodyMedium)
                    if transaction.isReimbursable {
                        let status = transaction.reimbursementStatus
                        Text(status.displayName)
                            .font(.designLabel)
                            .padding(.horizontal, 4)
                            .background((status == .reimbursed ? Color.designPrimaryFixedDim : Color.orange).opacity(0.15))
                            .foregroundStyle(status == .reimbursed ? Color.designPrimaryFixedDim : .orange)
                            .clipShape(Capsule())
                    }
                    if transaction.isLending {
                        lendingStatusBadge
                    }
                    if transaction.isSplitParent {
                        Image(systemName: "rectangle.split.2x2")
                            .font(.designBodySmall)
                            .foregroundStyle(Color.designTertiaryContainer)
                    }
                    if transaction.refundGroupId != nil {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.designBodySmall)
                            .foregroundStyle(Color.designPrimaryContainer)
                    }
                    if let photos = transaction.photoURLs, !photos.isEmpty {
                        Image(systemName: "camera.fill")
                            .font(.designBodySmall)
                            .foregroundStyle(Color.designOnSurfaceVariant)
                    }
                }
                if let subtitle = subtitleText {
                    Text(LocalizedStringKey(subtitle))
                        .font(.designBodySmall)
                        .foregroundStyle(Color.designOnSurfaceVariant)
                        .lineLimit(1)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                amountView
                Text(transaction.date.formatted(date: .numeric, time: .omitted))
                    .font(.designBodySmall)
                    .foregroundStyle(Color.designOnSurfaceVariant)
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
            case .borrowIn, .collect: return .designAccentGreen
            case .none: return .orange
            }
        }
        switch transaction.type {
        case .income: return .designAccentGreen
        case .expense: return .designAccentRed
        case .transfer: return .blue
        case .lending: break
        case .adjustment: return .designAccentPurple
        }
        return Color.designOnSurfaceVariant
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
            CurrencyText(amount: transaction.amount, currencyCode: transaction.currencyCode, showSign: true, size: 17, foregroundColor: .designPrimaryFixedDim)
        case .expense:
            CurrencyText(amount: transaction.amount, currencyCode: transaction.currencyCode, showSign: true, size: 17, foregroundColor: .designAccentRed)
        case .transfer:
            HStack(spacing: 0) {
                Text("↔")
                CurrencyText(amount: abs(transaction.amount), currencyCode: transaction.currencyCode, size: 17, foregroundColor: .blue)
            }
        case .lending:
            CurrencyText(amount: transaction.amount, currencyCode: transaction.currencyCode, showSign: true, size: 17, foregroundColor: transaction.amount >= 0 ? .designPrimaryFixedDim : .orange)
        case .adjustment:
            CurrencyText(amount: transaction.amount, currencyCode: transaction.currencyCode, showSign: true, size: 17, foregroundColor: transaction.amount >= 0 ? .designPrimaryFixedDim : .designAccentRed)
        }
    }

    @ViewBuilder
    private var lendingStatusBadge: some View {
        if let d = transaction.lendingDirection {
            switch transaction.lendingStatus {
            case .pending:
                Text(LocalizedStringKey(d.pendingLabel))
                    .font(.designLabel)
                    .padding(.horizontal, 4)
                    .background(Color.orange.opacity(0.15))
                    .foregroundStyle(.orange)
                    .clipShape(Capsule())
            case .settled:
                Text(LendingStatus.settled.displayName)
                    .font(.designLabel)
                    .padding(.horizontal, 4)
                    .background(Color.designPrimaryFixedDim.opacity(0.1))
                    .foregroundStyle(Color.designPrimaryFixedDim)
                    .clipShape(Capsule())
            case .none: EmptyView()
            }
        }
    }
}
