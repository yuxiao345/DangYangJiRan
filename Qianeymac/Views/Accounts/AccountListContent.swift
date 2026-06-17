import SwiftUI
@preconcurrency import CoreData

struct AccountListContent: View {
    @Environment(AppContainer.self) private var appContainer
    @Environment(\.managedObjectContext) private var modelContext
    @State private var accounts: [Account] = []
    @State private var balances: [UUID: Decimal] = [:]

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(groupedAccounts, id: \.key) { group in
                    Text(group.key).font(.caption).foregroundStyle(Color.designOnSurfaceVariant)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    ForEach(group.value) { account in
                        NavigationLink(value: account) {
                            HStack {
                                Label(account.name, systemImage: account.type.systemIcon)
                                Spacer()
                                Text(CurrencyFormatter.formatDecimal(amount: balances[account.id] ?? 0, currencyCode: account.currencyCode))
                                    .foregroundStyle((balances[account.id] ?? 0) >= 0 ? Color.designPrimaryFixedDim : Color.designAccentRed)
                            }
                            .padding(10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                if accounts.isEmpty {
                    Text("暂无账户").foregroundStyle(Color.designOnSurfaceVariant).padding(.top, 60)
                }
            }
            .padding(16)
        }
        .designScreen()
        .navigationDestination(for: Account.self) { account in
            AccountDetailContent(account: account)
        }
        .onAppear(perform: load)
        .onReceive(NotificationCenter.default.publisher(for: .transactionDidChange)) { _ in load() }
    }

    private var groupedAccounts: [(key: String, value: [Account])] {
        Dictionary(grouping: accounts) { $0.typeDisplayName }
            .sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
    }

    private func load() {
        guard let ledger = appContainer.currentLedger else { return }
        accounts = (try? appContainer.accountService.fetchAccounts(for: ledger, context: modelContext)) ?? []
        for a in accounts {
            balances[a.id] = appContainer.accountService.calculateBalance(for: a, context: modelContext)
        }
    }
}
