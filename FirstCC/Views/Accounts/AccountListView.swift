import SwiftUI
@preconcurrency import CoreData

struct AccountListView: View {
    @Environment(AppContainer.self) private var appContainer
    @Environment(\.managedObjectContext) private var modelContext
    @State private var showAddSheet = false
    @State private var accounts: [Account] = []
    @State private var balances: [UUID: Decimal] = [:]
    @State private var lendingInfos: [UUID: AccountRowView.LendingAccountInfo] = [:]
    /// 双栏时右栏显示的账户。存 id 而不是对象：reload 后旧对象可能已经失效。
    @State private var selectedAccountID: UUID?

    private var selectedAccount: Account? {
        guard let selectedAccountID else { return nil }
        return accounts.first { $0.id == selectedAccountID }
    }

    var body: some View {
        NavigationStack {
            AdaptiveTwoColumnLayout { availableWidth in
                twoColumnLayout(availableWidth: availableWidth)
            } compact: {
                stackedLayout
            }
            .designScreen()
            .safeAreaInset(edge: .bottom) {
                AddFloatingButton(title: "添加账户", identifier: "account-add-button") {
                    showAddSheet = true
                }
            }
            .navigationTitle("账户")
            .sheet(isPresented: $showAddSheet, onDismiss: { loadAccounts() }) {
                AddEditAccountView()
            }
            .onAppear(perform: loadAccounts)
            .onReceive(NotificationCenter.default.publisher(for: .transactionDidChange)) { _ in
                loadAccounts()
            }
        }
    }

    // MARK: - Layout

    /// iPhone 竖屏 / iPad 竖屏 / 窄窗口：保持原有的整页列表 + push 详情。
    private var stackedLayout: some View {
        ScrollView {
            LazyVStack(spacing: 24) {
                totalAssetsCard
                    .accessibilityIdentifier("account-list-total-assets-card")
                accountGroupsView { account in
                    NavigationLink {
                        AccountDetailView(account: account)
                    } label: {
                        accountRow(account)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
        }
        .accessibilityIdentifier("account-list")
        .scrollClipDisabled()
    }

    /// 宽屏：左栏账户列表独立滚动，右栏是选中账户的明细，同样独立滚动。
    private func twoColumnLayout(availableWidth: CGFloat) -> some View {
        let leftWidth = TwoColumnLayout.leftWidth(
            for: availableWidth, fraction: 0.34, min: 340, max: 420
        )

        return HStack(alignment: .top, spacing: 20) {
            ScrollView {
                LazyVStack(spacing: 24) {
                    totalAssetsCard
                        .accessibilityIdentifier("account-list-total-assets-card")
                    accountGroupsView { account in
                        Button {
                            selectedAccountID = account.id
                        } label: {
                            accountRow(account, isSelected: account.id == selectedAccountID)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(account.id == selectedAccountID ? .isSelected : [])
                    }
                }
                .padding(.vertical, 16)
            }
            .accessibilityIdentifier("account-list")
            .scrollClipDisabled()
            .frame(width: leftWidth)

            Group {
                if let selectedAccount {
                    // 换账户时重建整棵子树：AccountDetailView 的展开状态和已加载数据都按账户持有，
                    // 只改 account 属性不会重跑 onAppear，会残留上一个账户的月份折叠状态。
                    AccountDetailView(
                        account: selectedAccount,
                        embedded: true,
                        onAccountChanged: { loadAccounts() }
                    )
                    .id(selectedAccount.id)
                } else {
                    ContentUnavailableView(
                        "还没有账户",
                        systemImage: "creditcard",
                        description: Text("点击下方 + 添加账户")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .padding(.horizontal, 16)
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

    private func accountGroupsView<Row: View>(
        @ViewBuilder row: @escaping (Account) -> Row
    ) -> some View {
        let groups = accountGroups
        return ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
            VStack(alignment: .leading, spacing: 12) {
                groupHeader(type: group.type, count: group.accounts.count, customName: group.customName)

                ForEach(group.accounts) { account in
                    row(account)
                }
            }
        }
    }

    /// 账户行的统一渲染。双栏下额外画一圈选中描边。
    private func accountRow(_ account: Account, isSelected: Bool = false) -> some View {
        AccountRowView(
            account: account,
            balance: balances[account.id] ?? 0,
            lendingInfo: lendingInfos[account.id]
        )
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(Color.designPrimaryContainer, lineWidth: 1.5)
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
        reconcileSelection()
    }

    /// 双栏选中态收敛：首次进入自动选第一个可见账户；选中账户被删除/归档后回退。
    private func reconcileSelection() {
        let displayed = accountGroups.flatMap(\.accounts)
        if let selectedAccountID, displayed.contains(where: { $0.id == selectedAccountID }) {
            return
        }
        selectedAccountID = displayed.first?.id
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
