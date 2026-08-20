import SwiftUI
@preconcurrency import CoreData

struct AccountListView: View {
    @Environment(AppContainer.self) private var appContainer
    @Environment(\.managedObjectContext) private var modelContext
    @State private var showAddSheet = false
    @State private var accounts: [Account] = []
    @State private var balances: [UUID: Decimal] = [:]
    @State private var lendingInfos: [UUID: AccountRowView.LendingAccountInfo] = [:]

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                totalAssetsCard
                accountGroupsView
            }
            .padding(16)
        }
        .scrollClipDisabled()
        .designScreen()
        .navigationTitle("账户")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showAddSheet = true } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showAddSheet, onDismiss: { loadAccounts() }) {
            AddEditAccountView()
        }
        .onAppear(perform: loadAccounts)
        .onReceive(NotificationCenter.default.publisher(for: .transactionDidChange)) { _ in
            loadAccounts()
        }
    }

    // MARK: - Total Assets Hero Card

    private var totalAssetsCard: some View {
        let total = balances.values.reduce(Decimal.zero, +)
        return VStack(alignment: .leading, spacing: 8) {
            Text("净资产")
                .font(.designLabel)
                .foregroundStyle(Color.designOnSurfaceVariant)
                .tracking(1.2)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(CurrencyFormatter.currencySymbol(for: appContainer.currentLedger?.defaultCurrencyCode ?? "CNY"))
                    .font(.custom("JetBrainsMono-Medium", fixedSize: 24))
                    .foregroundStyle(Color.designPrimaryFixedDim)
                Text(CurrencyFormatter.formatDecimal(amount: total, fractionDigits: 2))
                    .font(.designDisplayMobile)
                    .foregroundStyle(Color.designOnSurface)
                    .tracking(-0.6)
            }

            HStack(spacing: 8) {
                Text("共 \(accounts.count) 个账户")
                    .font(.custom("JetBrainsMono-Medium", fixedSize: 12))
                    .foregroundStyle(Color.designOnSurfaceVariant)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color.designSurfaceContainer.opacity(0.6))
                    )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .glassCard(cornerRadius: 24)
        .overlay(alignment: .topTrailing) {
            Circle()
                .fill(Color.designPrimaryFixedDim.opacity(0.12))
                .frame(width: 80, height: 80)
                .blur(radius: 24)
                .offset(x: 10, y: -10)
        }
    }

    // MARK: - Account Groups

    private var accountGroupsView: some View {
        let groups = accountGroups
        return ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
            VStack(alignment: .leading, spacing: 12) {
                groupHeader(type: group.type, count: group.accounts.count, customName: group.customName)

                ForEach(group.accounts) { account in
                    NavigationLink {
                        AccountDetailView(account: account)
                    } label: {
                        AccountRowView(
                            account: account,
                            balance: balances[account.id] ?? 0,
                            lendingInfo: lendingInfos[account.id]
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func groupHeader(type: AccountType, count: Int, customName: String? = nil) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.accountAccent(for: type))
                .frame(width: 3, height: 20)

            Text(customName ?? type.displayName)
                .font(.designBodyMedium.weight(.bold))
                .foregroundStyle(Color.designOnSurface)

            Text("(\(count))")
                .font(.custom("JetBrainsMono-Medium", fixedSize: 13))
                .foregroundStyle(Color.designOnSurfaceVariant.opacity(0.5))
        }
    }

    // MARK: - Helpers

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

    private func loadAccounts() {
        guard let ledger = appContainer.currentLedger else { return }
        accounts = (try? appContainer.accountService.fetchAccounts(for: ledger, context: modelContext)) ?? []
        for account in accounts {
            balances[account.id] = appContainer.accountService.calculateBalance(for: account, context: modelContext)
            if account.type == .lending {
                lendingInfos[account.id] = computeLendingInfo(account: account, ledger: ledger)
            }
        }
    }

    private func computeLendingInfo(account: Account, ledger: Ledger) -> AccountRowView.LendingAccountInfo {
        let all = (try? appContainer.transactionService.fetchTransactions(for: ledger, context: modelContext, filters: nil)) ?? []
        let accountID = account.id
        let lendOutRaw = LendingDirection.lendOut.rawValue
        let pendingRaw = LendingStatus.pending.rawValue
        let borrowInRaw = LendingDirection.borrowIn.rawValue
        let lendingTypeRaw = TransactionType.lending.rawValue

        let allLending = all.filter { $0.typeRaw == lendingTypeRaw }

        let lendOutPending = allLending
            .filter { $0.lendingDirectionRaw == lendOutRaw && $0.lendingStatusRaw == pendingRaw && $0.toAccount?.id == accountID }
            .reduce(Decimal.zero) { $0 + $1.ledgerAmount + $1.settledAmountInLedgerCurrency }

        let borrowInPending = allLending
            .filter { $0.lendingDirectionRaw == borrowInRaw && $0.lendingStatusRaw == pendingRaw && $0.account?.id == accountID }
            .reduce(Decimal.zero) { $0 + $1.ledgerAmount - $1.settledAmountInLedgerCurrency }

        return AccountRowView.LendingAccountInfo(
            lendOutPending: -lendOutPending,
            borrowInPending: borrowInPending
        )
    }
}
