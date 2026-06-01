import SwiftUI
@preconcurrency import CoreData

struct AccountDetailView: View {
    @ObservedObject var account: Account
    @Environment(\.managedObjectContext) private var modelContext
    @EnvironmentObject private var appContainer: AppContainer
    @State private var balance: Decimal = 0
    @State private var transactions: [Transaction] = []
    @State private var showEditSheet = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                heroCard
                creditCardSection
                transactionList
            }
            .padding(16)
        }
        .designScreen()
        .navigationTitle(LocalizedStringKey(account.name))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showEditSheet = true } label: {
                    Image(systemName: "pencil")
                }
            }
        }
        .sheet(isPresented: $showEditSheet, onDismiss: { load() }) {
            AddEditAccountView(editing: account)
        }
        .onAppear(perform: load)
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
                Text(account.type.displayName)
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
            }
        }
    }

    private func creditInfoRow<Content: View>(label: String, @ViewBuilder value: () -> Content) -> some View {
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

    // MARK: - Transaction List

    @ViewBuilder
    private var transactionList: some View {
        let groups = transactionDateGroups
        ForEach(groups, id: \.key) { group in
            VStack(alignment: .leading, spacing: 8) {
                Text(group.key)
                    .font(.designLabel)
                    .foregroundStyle(Color.designOnSurfaceVariant.opacity(0.6))

                ForEach(group.value) { t in
                    TransactionRowView(transaction: t)
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
        req.predicate = NSPredicate(format: "account.id == %@ AND parentTransaction == nil", account.id as CVarArg)
        req.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
        transactions = (try? modelContext.fetch(req)) ?? []
    }

}
