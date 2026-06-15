import SwiftUI
@preconcurrency import CoreData

struct AccountDetailContent: View {
    @Environment(AppContainer.self) private var appContainer
    @Environment(\.managedObjectContext) private var modelContext
    let account: Account
    @State private var transactions: [Transaction] = []
    @State private var balance: Decimal = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(account.name).font(.title2.weight(.semibold)).foregroundStyle(Color.designOnSurface)
                    Text(account.typeDisplayName).font(.caption).foregroundStyle(Color.designOnSurfaceVariant)
                }
                HStack(spacing: 4) {
                    Text(CurrencyFormatter.currencySymbol(for: account.currencyCode))
                        .font(.title3).foregroundStyle(Color.designPrimaryFixedDim)
                    Text(CurrencyFormatter.formatDecimal(amount: balance, fractionDigits: 2))
                        .font(.largeTitle.weight(.bold)).foregroundStyle(Color.designOnSurface)
                }
                Divider()
                Text("交易记录").font(.headline).foregroundStyle(Color.designOnSurface)
                if transactions.isEmpty {
                    Text("暂无交易记录")
                        .foregroundStyle(Color.designOnSurfaceVariant).padding(.top, 20)
                } else {
                    LazyVStack(spacing: 8) {
                        ForEach(transactions) { t in
                            TransactionRowView(transaction: t)
                        }
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .designScreen()
        .onAppear(perform: load)
    }

    private func load() {
        balance = appContainer.accountService.calculateBalance(for: account, context: modelContext)
        transactions = (try? appContainer.transactionService.fetchTransactions(
            for: appContainer.currentLedger!, context: modelContext, filters: TransactionFilters()
        ))?.filter { $0.account?.id == account.id || $0.toAccount?.id == account.id }
            .sorted { $0.date > $1.date } ?? []
    }
}

