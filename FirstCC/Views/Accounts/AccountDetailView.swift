import SwiftUI
@preconcurrency import CoreData

struct AccountDetailView: View {
    @ObservedObject var account: Account
    @Environment(\.managedObjectContext) private var modelContext
    @Environment(AppContainer.self) private var appContainer
    @State private var balance: Decimal = 0
    @State private var transactions: [Transaction] = []
    @State private var showEditSheet = false

    var body: some View {
        if account.managedObjectContext == nil {
            Color.clear
        } else {
            accountContent
        }
    }

    private var accountContent: some View {
        ScrollView {
            VStack(spacing: 24) {
                heroCard
                creditCardSection
                transactionList
            }
            .padding(16)
        }
        .scrollClipDisabled()
        .designScreen()
        .navigationTitle(LocalizedStringKey(account.name))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showEditSheet = true } label: {
                    Image(systemName: "pencil")
                }
                .accessibilityIdentifier("account-edit-button")
            }
        }
        .sheet(isPresented: $showEditSheet, onDismiss: { load() }) {
            AddEditAccountView(editing: account)
        }
        .onAppear(perform: load)
        .onReceive(NotificationCenter.default.publisher(for: .transactionDidChange)) { _ in load() }
    }

    // MARK: - Hero Card

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(LocalizedStringKey(account.name))
                .font(.designLabel)
                .foregroundStyle(Color.designOnSurfaceVariant)
                .tracking(1.2)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(CurrencyFormatter.currencySymbol(for: account.currencyCode))
                    .font(.custom("JetBrainsMono-Medium", fixedSize: 24))
                    .foregroundStyle(Color.designPrimaryFixedDim)
                Text(CurrencyFormatter.formatDecimal(amount: balance, fractionDigits: 2, showAbs: false))
                    .font(.designDisplayMobile)
                    .foregroundStyle(balance >= 0 ? Color.designPrimaryFixedDim : Color.designAccentRed)
                    .tracking(-0.6)
            }

            HStack(spacing: 8) {
                Text(account.typeDisplayName)
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

    // MARK: - Credit Card Section

    @ViewBuilder
    private var creditCardSection: some View {
        if account.type == .creditCard {
            VStack(spacing: 12) {
                if let limit = account.creditLimit {
                    creditInfoRow(label: "总额度") {
                        CurrencyText(amount: limit, currencyCode: account.currencyCode, size: 15, foregroundColor: .designOnSurface)
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

                NavigationLink {
                    CreditCardReconciliationView(account: account)
                } label: {
                    HStack {
                        Label("对账管理", systemImage: "checklist")
                            .font(.designBodyMedium)
                            .foregroundStyle(Color.designOnSurface)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(Color.designOnSurfaceVariant)
                    }
                    .padding(12)
                    .glassCard(cornerRadius: 12)
                }
                .buttonStyle(.plain)

                #if DEBUG
                NavigationLink {
                    OCRTestView(account: account)
                } label: {
                    HStack {
                        Label("OCR 识别测试", systemImage: "camera.viewfinder")
                            .font(.designBodyMedium)
                            .foregroundStyle(Color.designOnSurface)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(Color.designOnSurfaceVariant)
                    }
                    .padding(12)
                    .glassCard(cornerRadius: 12)
                }
                .buttonStyle(.plain)
                #endif
            }
        }
    }

    private func creditInfoRow<Content: View>(label: LocalizedStringKey, @ViewBuilder value: () -> Content) -> some View {
        HStack {
            Text(label)
                .font(.designBodyMedium)
                .foregroundStyle(Color.designOnSurfaceVariant)
            Spacer()
            value()
        }
        .padding(12)
        .glassCard(cornerRadius: 12)
    }

    // MARK: - Running Balance

    /// 每个日期组的期末余额 (key = 日期标签, value = 该日交易后的余额)
    private var dateBalances: [String: Decimal] {
        let groups = transactionDateGroups
        var result: [String: Decimal] = [:]
        var running = balance
        // groups 从最新到最旧排列，从当前余额逐步回推
        for group in groups {
            result[group.key] = running
            let dayNet = group.value.reduce(Decimal.zero) { $0 + $1.ledgerAmount }
            running -= dayNet
        }
        return result
    }

    // MARK: - Transaction List

    @ViewBuilder
    private var transactionList: some View {
        let groups = transactionDateGroups
        let balances = dateBalances
        ForEach(groups, id: \.key) { group in
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(group.key)
                        .font(.designLabel)
                        .foregroundStyle(Color.designOnSurfaceVariant.opacity(0.6))
                    Spacer()
                    if let dayBalance = balances[group.key] {
                        CurrencyText(amount: dayBalance, currencyCode: account.currencyCode, size: 13, foregroundColor: Color.designOnSurfaceVariant.opacity(0.6))
                    }
                }

                ForEach(group.value, id: \.objectID) { t in
                    NavigationLink {
                        TransactionDetailView(transaction: t)
                    } label: {
                        TransactionRowView(transaction: t)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Date grouping

    private var transactionDateGroups: [(key: String, value: [Transaction])] {
        transactions.groupedByRelativeDate()
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
