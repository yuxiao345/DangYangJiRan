import SwiftUI
@preconcurrency import CoreData

struct AccountListContent: View {
    @Environment(AppContainer.self) private var appContainer
    @Environment(\.managedObjectContext) private var modelContext
    @State private var accounts: [Account] = []
    @State private var balances: [UUID: Decimal] = [:]
    @State private var lendingInfos: [UUID: LendingInfo] = [:]

    struct LendingInfo {
        let lendOutPending: Decimal
        let borrowInPending: Decimal
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if accounts.isEmpty {
                Text("暂无账户")
                    .foregroundStyle(Color.designOnSurfaceVariant)
                    .padding(24)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("mac-account-list-empty-state")
            } else {
                ScrollView {
                    LazyVStack(spacing: 20) {
                        totalAssetsCard
                            .accessibilityIdentifier("mac-account-list-total-assets-card")
                        accountGroupsView
                    }
                    .padding(24)
                }
                .accessibilityIdentifier("mac-account-list")
            }
        }
        .designScreen()
        .onAppear(perform: loadAccounts)
        .onReceive(NotificationCenter.default.publisher(for: .transactionDidChange)) { _ in loadAccounts() }
        .navigationDestination(for: Account.self) { account in
            AccountDetailContent(account: account)
        }
    }

    // MARK: - Total Assets Card

    private var totalAssetsCard: some View {
        let total = balances.values.reduce(Decimal.zero, +)
        let currency = appContainer.currentLedger?.defaultCurrencyCode ?? "CNY"
        return VStack(alignment: .leading, spacing: 8) {
            Text("净资产")
                .font(.designLabel)
                .foregroundStyle(Color.designOnSurfaceVariant)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(CurrencyFormatter.currencySymbol(for: currency))
                    .font(.system(size: 28, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.designPrimaryFixedDim)
                Text(CurrencyFormatter.formatDecimal(amount: total, fractionDigits: 2))
                    .font(.system(size: 40, weight: .bold))
                    .foregroundStyle(Color.designOnSurface)
            }

            Text("共 \(accounts.count) 个账户")
                .font(.designBodyCaption)
                .foregroundStyle(Color.designOnSurfaceVariant)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Capsule().fill(Color.designSurfaceContainer.opacity(0.6)))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .glassCard(cornerRadius: 20)
    }

    // MARK: - Account Groups

    private var accountGroupsView: some View {
        let groups = accountGroups
        return ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
            VStack(alignment: .leading, spacing: 10) {
                groupHeader(type: group.type, count: group.accounts.count, customName: group.customName)

                ForEach(group.accounts) { account in
                    NavigationLink(value: account) {
                        accountRow(account)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func groupHeader(type: AccountType, count: Int, customName: String? = nil) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.accountAccent(for: type))
                .frame(width: 3, height: 18)

            Text(customName ?? type.displayName)
                .font(.designBodyMedium.weight(.semibold))
                .foregroundStyle(Color.designOnSurface)

            Text("\(count)")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Color.designOnSurfaceVariant.opacity(0.5))
        }
    }

    // MARK: - Account Row

    private func accountRow(_ account: Account) -> some View {
        let balance = balances[account.id] ?? 0
        let info = lendingInfos[account.id]
        let accent = Color.accountAccent(for: account.type)

        return HStack(spacing: 12) {
            Image(systemName: account.iconName ?? account.type.systemIcon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(accent)
                .frame(width: 36, height: 36)
                .background(accent.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(account.name)
                        .font(.designBodyMedium)
                        .foregroundStyle(Color.designOnSurface)
                    if account.isArchived {
                        Text("已归档")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(Color.designOnSurfaceVariant)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Capsule().fill(Color.designOnSurfaceVariant.opacity(0.12)))
                    }
                    if account.type == .creditCard, balance < 0 {
                        Text("待还款")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(Color.designAccentRed)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Capsule().fill(Color.designAccentRed.opacity(0.1)))
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                CurrencyText(amount: abs(balance), currencyCode: account.currencyCode,
                             size: 16, foregroundColor: balanceColor(balance, account: account))
                if let info {
                    if info.lendOutPending != 0 {
                        HStack(spacing: 4) {
                            Text("应收")
                                .font(.designBodyCaption)
                                .foregroundStyle(Color.designOnSurfaceVariant)
                            CurrencyText(amount: info.lendOutPending, currencyCode: account.currencyCode, showSign: false, size: 11, foregroundColor: .orange)
                        }
                    }
                    if info.borrowInPending != 0 {
                        HStack(spacing: 4) {
                            Text("应付")
                                .font(.designBodyCaption)
                                .foregroundStyle(Color.designOnSurfaceVariant)
                            CurrencyText(amount: info.borrowInPending, currencyCode: account.currencyCode, showSign: false, size: 11, foregroundColor: .blue)
                        }
                    }
                }
            }
        }
        .padding(12)
        .glassCard(cornerRadius: 14)
        .opacity(account.isArchived ? 0.55 : 1.0)
    }

    private func balanceColor(_ balance: Decimal, account: Account) -> Color {
        if account.type == .creditCard {
            return balance < 0 ? Color.designAccentRed : Color.designAccentGreen
        }
        return balance < 0 ? Color.designAccentRed : Color.designPrimaryFixedDim
    }

    // MARK: - Account Groups Data

    private var accountGroups: [(type: AccountType, accounts: [Account], customName: String?)] {
        var groups: [(AccountType, [Account], String?)] = []
        for type in AccountType.allCases {
            let matched = accounts.filter { $0.type == type && !$0.isArchived }
            if type == .other {
                let byName = Dictionary(grouping: matched) { $0.customTypeName?.isEmpty == false ? $0.customTypeName! : "自定义" }
                for (name, accts) in byName.sorted(by: { $0.key < $1.key }) {
                    groups.append((type, accts, name == "自定义" ? nil : name))
                }
            } else if !matched.isEmpty {
                groups.append((type, matched, nil))
            }
        }
        return groups
    }

    // MARK: - Data Loading

    private func loadAccounts() {
        guard let ledger = appContainer.currentLedger else { return }
        accounts = (try? appContainer.accountService.fetchAccounts(for: ledger, context: modelContext)) ?? []
        for a in accounts {
            balances[a.id] = appContainer.accountService.calculateBalance(for: a, context: modelContext)
            if a.type == .lending {
                lendingInfos[a.id] = computeLendingInfo(account: a, ledger: ledger)
            }
        }
    }

    private func computeLendingInfo(account: Account, ledger: Ledger) -> LendingInfo {
        let all = (try? appContainer.transactionService.fetchTransactions(for: ledger, context: modelContext, filters: nil)) ?? []
        let accountID = account.id
        let lendOutRaw = LendingDirection.lendOut.rawValue
        let borrowInRaw = LendingDirection.borrowIn.rawValue
        let pendingRaw = LendingStatus.pending.rawValue
        let lendingTypeRaw = TransactionType.lending.rawValue

        let allLending = all.filter { $0.typeRaw == lendingTypeRaw }

        let lendOutPending = allLending
            .filter { $0.lendingDirectionRaw == lendOutRaw && $0.lendingStatusRaw == pendingRaw && $0.toAccount?.id == accountID }
            .reduce(Decimal.zero) { $0 + $1.ledgerAmount + $1.settledAmountInLedgerCurrency }

        let borrowInPending = allLending
            .filter { $0.lendingDirectionRaw == borrowInRaw && $0.lendingStatusRaw == pendingRaw && $0.account?.id == accountID }
            .reduce(Decimal.zero) { $0 + $1.ledgerAmount - $1.settledAmountInLedgerCurrency }

        return LendingInfo(lendOutPending: -lendOutPending, borrowInPending: borrowInPending)
    }
}
