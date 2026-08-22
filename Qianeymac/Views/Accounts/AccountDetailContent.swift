import SwiftUI
@preconcurrency import CoreData

struct AccountDetailContent: View {
    @Environment(AppContainer.self) private var appContainer
    @Environment(\.managedObjectContext) private var modelContext
    let account: Account
    @State private var transactions: [Transaction] = []
    @State private var balance: Decimal = 0
    @State private var selectedTransaction: Transaction?
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                heroCard
                    .accessibilityIdentifier("mac-account-detail-hero-card")
                creditCardSection
                transactionList
            }
            .padding(24)
        }
        .accessibilityIdentifier("mac-account-detail")
        .designScreen()
        .navigationTitle("")
        .onAppear(perform: load)
        .sheet(item: $selectedTransaction) { t in
            MacAddTransactionSheet(editing: t, displayMode: true)
        }
    }

    // MARK: - Hero Card

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(LocalizedStringKey(account.name))
                .font(.designLabel)
                .foregroundStyle(Color.designOnSurfaceVariant)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(CurrencyFormatter.currencySymbol(for: account.currencyCode))
                    .font(.system(size: 28, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.designPrimaryFixedDim)
                Text(CurrencyFormatter.formatDecimal(amount: balance, fractionDigits: 2))
                    .font(.system(size: 44, weight: .bold))
                    .foregroundStyle(balance >= 0 ? Color.designPrimaryFixedDim : Color.designAccentRed)
            }

            Text(account.typeDisplayName)
                .font(.designBodyCaption)
                .foregroundStyle(Color.designOnSurfaceVariant)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Capsule().fill(Color.designSurfaceContainer.opacity(0.6)))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .glassCard(cornerRadius: 20)
    }

    // MARK: - Credit Card Section

    @ViewBuilder
    private var creditCardSection: some View {
        if account.type == .creditCard {
            VStack(spacing: 10) {
                if let limit = account.creditLimit {
                    creditInfoRow(label: "总额度") {
                        CurrencyText(amount: limit, currencyCode: account.currencyCode, size: 14, foregroundColor: .designOnSurface)
                    }
                }
                if account.billingDay != 0 {
                    creditInfoRow(label: "账单日") {
                        Text("每月\(Int(account.billingDay))日")
                            .font(.designBodyMedium)
                            .foregroundStyle(Color.designOnSurface)
                    }
                }
                if account.dueDay != 0 {
                    creditInfoRow(label: "还款日") {
                        Text("每月\(Int(account.dueDay))日")
                            .font(.designBodyMedium)
                            .foregroundStyle(Color.designOnSurface)
                    }
                }
            }
        }
    }

    private func creditInfoRow<Content: View>(label: String, @ViewBuilder value: () -> Content) -> some View {
        HStack {
            Text(LocalizedStringKey(label))
                .font(.designBodyMedium)
                .foregroundStyle(Color.designOnSurfaceVariant)
            Spacer()
            value()
        }
        .padding(12)
        .glassCard(cornerRadius: 12)
    }

    // MARK: - Transaction List with Date Groups

    private var transactionDateGroups: [(key: String, value: [Transaction])] {
        transactions.groupedByRelativeDate()
    }

    private var dateBalances: [String: Decimal] {
        let groups = transactionDateGroups
        var result: [String: Decimal] = [:]
        var running = balance
        for group in groups {
            result[group.key] = running
            let dayNet = group.value.reduce(Decimal.zero) { $0 + $1.amount }
            running -= dayNet
        }
        return result
    }

    @ViewBuilder
    private var transactionList: some View {
        let groups = transactionDateGroups
        let balances = dateBalances

        if transactions.isEmpty {
            Text("暂无交易记录")
                .foregroundStyle(Color.designOnSurfaceVariant)
                .padding(.top, 20)
        } else {
            ForEach(groups, id: \.key) { group in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(group.key)
                            .font(.designLabel)
                            .foregroundStyle(Color.designOnSurfaceVariant.opacity(0.6))
                        Spacer()
                        if let dayBalance = balances[group.key] {
                            CurrencyText(amount: dayBalance, currencyCode: account.currencyCode,
                                         size: 13, foregroundColor: Color.designOnSurfaceVariant.opacity(0.6))
                        }
                    }

                    ForEach(group.value, id: \.objectID) { t in
                        Button {
                            selectedTransaction = t
                        } label: {
                            TransactionRowView(transaction: t)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Load

    private func load() {
        balance = appContainer.accountService.calculateBalance(for: account, context: modelContext)
        guard let ledger = appContainer.currentLedger else { return }

        let req = NSFetchRequest<Transaction>(entityName: "Transaction")
        req.predicate = NSPredicate(format: "(account.id == %@ OR (toAccount.id == %@ AND typeRaw == %@)) AND parentTransaction == nil",
                                    account.id as CVarArg, account.id as CVarArg, TransactionType.lending.rawValue)
        req.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
        transactions = (try? modelContext.fetch(req)) ?? []
    }
}
