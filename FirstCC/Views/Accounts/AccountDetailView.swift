import SwiftUI
import SwiftData

struct AccountDetailView: View {
    let account: Account
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appContainer: AppContainer
    @State private var balance: Decimal = 0
    @State private var transactions: [Transaction] = []

    var body: some View {
        List {
            Section("余额") {
                CurrencyText(amount: abs(balance), currencyCode: account.currencyCode, font: .largeTitle, foregroundColor: balance >= 0 ? Color.blue : Color.red)
                    .fontWeight(.bold)
            }

            if account.type == .creditCard {
                Section("信用额度") {
                    if let limit = account.creditLimit {
                        LabeledContent("总额度") {
                            CurrencyText(amount: limit, currencyCode: account.currencyCode, font: .body)
                        }
                    }
                    if let billDate = account.billDate {
                        LabeledContent("账单日", value: billDate.formatted(date: .abbreviated, time: .omitted))
                    }
                    if let dueDate = account.dueDate {
                        LabeledContent("还款日", value: dueDate.formatted(date: .abbreviated, time: .omitted))
                    }
                }
            }

            Section("最近交易") {
                if transactions.isEmpty {
                    Text("暂无交易")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(transactions.prefix(20)) { t in
                        TransactionRowView(transaction: t)
                    }
                }
            }
        }
        .navigationTitle(LocalizedStringKey(account.name))
        .onAppear(perform: load)
    }

    private func load() {
        balance = appContainer.accountService.calculateBalance(for: account, context: modelContext)
        guard let ledger = appContainer.currentLedger else { return }
        let accountID = account.id
        let all = (try? appContainer.transactionService.fetchTransactions(for: ledger, context: modelContext, filters: nil)) ?? []
        transactions = all.filter { $0.account?.id == accountID || $0.toAccount?.id == accountID }
    }
}
