import SwiftUI
import SwiftData

struct AccountListView: View {
    @EnvironmentObject private var appContainer: AppContainer
    @Environment(\.modelContext) private var modelContext
    @State private var showAddSheet = false
    @State private var accounts: [Account] = []
    @State private var balances: [UUID: Decimal] = [:]
    @State private var lendingInfos: [UUID: AccountRowView.LendingAccountInfo] = [:]

    var body: some View {
        List {
            ForEach(accountGroups, id: \.type) { group in
                Section(group.type.displayName) {
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
                    }
                }
            }
        }
        .navigationTitle("账户")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showAddSheet = true } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddEditAccountView()
        }
        .onAppear(perform: loadAccounts)
        .onReceive(NotificationCenter.default.publisher(for: .transactionDidChange)) { _ in
            loadAccounts()
        }
    }

    private var accountGroups: [(type: AccountType, accounts: [Account])] {
        var groups: [(AccountType, [Account])] = []
        for type in AccountType.allCases {
            let matched = accounts.filter { $0.type == type && !$0.isArchived }
            if !matched.isEmpty {
                groups.append((type, matched))
            }
        }
        return groups
    }

    private func loadAccounts() {
        guard let ledger = appContainer.currentLedger else { return }
        accounts = (try? appContainer.accountService.fetchAccounts(for: ledger, context: modelContext)) ?? []
        accounts = accounts.filter { !$0.isArchived }
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

        // 借出 = money went TO the lending account (toAccount)
        let lendOutPending = allLending
            .filter { $0.lendingDirectionRaw == lendOutRaw && $0.lendingStatusRaw == pendingRaw && $0.toAccount?.id == accountID }
            .reduce(Decimal.zero) { $0 + $1.amount + ($1.settledAmount ?? 0) }

        // 借入 = money came FROM the lending account (account)
        let borrowInPending = allLending
            .filter { $0.lendingDirectionRaw == borrowInRaw && $0.lendingStatusRaw == pendingRaw && $0.account?.id == accountID }
            .reduce(Decimal.zero) { $0 + $1.amount - ($1.settledAmount ?? 0) }

        return AccountRowView.LendingAccountInfo(
            lendOutPending: -lendOutPending,
            borrowInPending: borrowInPending
        )
    }
}
