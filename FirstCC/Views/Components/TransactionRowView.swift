import SwiftUI

struct TransactionRowView: View {
    @ObservedObject var transaction: Transaction

    #if os(macOS)
    private let titleFont: Font = .designBodySmall.weight(.medium)
    private let subtitleFont: Font = .designBodyCaption
    #else
    private let titleFont: Font = .designBodyMedium.weight(.medium)
    private let subtitleFont: Font = .designBodySmall
    #endif

    var body: some View {
        if transaction.managedObjectContext == nil {
            Color.clear.frame(height: 0)
        } else {
            rowContent
        }
    }

    private var rowContent: some View {
        HStack(spacing: 12) {
            // Left colored border
            RoundedRectangle(cornerRadius: 2)
                .fill(borderColor)
                .frame(width: 4)
                .padding(.vertical, 8)

            // Icon container
            RoundedRectangle(cornerRadius: 10)
                .fill(iconBgColor)
                .frame(width: 40, height: 40)
                .overlay {
                    Image(systemName: iconName)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(iconColor)
                }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(LocalizedStringKey(titleText))
                        .font(titleFont)
                        .foregroundStyle(Color.designOnSurface)
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
                        .font(subtitleFont)
                        .foregroundStyle(Color.designOnSurfaceVariant)
                        .lineLimit(1)
                }
            }

            Spacer()

            amountView
        }
        .padding(.vertical, 6)
        .padding(.trailing, 14)
        .glassCard(cornerRadius: 16)
    }

    // MARK: - Computed properties

    private static let shortDateFormat = Date.FormatStyle.dateTime.month(.abbreviated).day(.twoDigits)

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
        case .income: return .designPrimaryFixedDim
        case .expense: return .designAccentRed
        case .transfer: return .blue
        case .lending: break
        case .adjustment: return .designAccentPurple
        }
        return Color.designOnSurfaceVariant
    }

    private var iconBgColor: Color {
        switch transaction.type {
        case .income: return Color.designPrimaryFixedDim.opacity(0.1)
        case .expense: return Color.designAccentRed.opacity(0.1)
        case .transfer: return Color.blue.opacity(0.1)
        case .lending: return Color.orange.opacity(0.1)
        case .adjustment: return Color.designAccentPurple.opacity(0.1)
        }
    }

    private var borderColor: Color {
        if transaction.isLending { return .orange }
        switch transaction.type {
        case .income: return .designPrimaryFixedDim
        case .expense: return .designAccentRed
        case .transfer: return .blue
        case .lending: return .orange
        case .adjustment: return .designAccentPurple
        }
    }

    private var titleText: String {
        if let d = transaction.lendingDirection { return d.displayName }
        if transaction.type == .transfer {
            let counterparty = transaction.toAccount?.name ?? "—"
            if transaction.amount < 0 {
                return "转账至\(NSLocalizedString(counterparty, comment: ""))"
            } else {
                return "转账自\(NSLocalizedString(counterparty, comment: ""))"
            }
        }
        return transaction.category?.name ?? transaction.type.displayName
    }

    private var subtitleText: String? {
        if transaction.type == .transfer {
            let from = transaction.account?.name ?? "—"
            let dateStr = transaction.date.formatted(Self.shortDateFormat)
            return "\(NSLocalizedString(from, comment: "")) · \(dateStr)"
        }
        if transaction.isLending {
            let from = transaction.account?.name ?? "—"
            let to = transaction.toAccount?.name ?? "—"
            let dateStr = transaction.date.formatted(Self.shortDateFormat)
            return "\(NSLocalizedString(from, comment: "")) → \(NSLocalizedString(to, comment: "")) · \(dateStr)"
        }
        let parts = [transaction.merchant?.name, transaction.member?.name, transaction.date.formatted(Self.shortDateFormat)].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
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
