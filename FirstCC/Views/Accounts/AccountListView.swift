import SwiftUI
import SwiftData

struct AccountListView: View {
    @EnvironmentObject private var appContainer: AppContainer
    @Environment(\.modelContext) private var modelContext
    @State private var showAddSheet = false
    @State private var accounts: [Account] = []
    @State private var balances: [UUID: Decimal] = [:]

    var body: some View {
        List {
            ForEach(accountGroups, id: \.type) { group in
                Section(group.type.displayName) {
                    ForEach(group.accounts) { account in
                        NavigationLink {
                            AccountDetailView(account: account)
                        } label: {
                            AccountRowView(account: account, balance: balances[account.id] ?? 0)
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
        }
    }
}
