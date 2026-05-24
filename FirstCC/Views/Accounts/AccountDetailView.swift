import SwiftUI
@preconcurrency import CoreData

struct AccountDetailView: View {
    let account: Account
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
                Text(CurrencyFormatter.formatDecimal(amount: balance, fractionDigits: 2, showAbs: true))
                    .font(.designDisplayMobile)
                    .foregroundStyle(Color.designOnSurface)
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
                    transactionRow(t)
                }
            }
        }
    }

    private func transactionRow(_ t: Transaction) -> some View {
        HStack(spacing: 12) {
            iconView(for: t)
                .frame(width: 36, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.designSurfaceContainer.opacity(0.6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.designOutlineVariant.opacity(0.3), lineWidth: 1)
                        )
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(titleText(for: t)))
                    .font(.designBodyMedium)
                    .foregroundStyle(Color.designOnSurface)
                if let sub = subtitleText(for: t) {
                    Text(LocalizedStringKey(sub))
                        .font(.designBodySmall)
                        .foregroundStyle(Color.designOnSurfaceVariant)
                        .lineLimit(1)
                }
            }

            Spacer()

            CurrencyText(
                amount: t.amount,
                currencyCode: t.currencyCode,
                showSign: true,
                size: 15,
                foregroundColor: amountColor(for: t)
            )
        }
        .padding(12)
        .glassCard(cornerRadius: 12)
    }

    // MARK: - Transaction helpers

    private func iconView(for t: Transaction) -> some View {
        let name = t.category?.iconName ?? t.type.systemIcon
        return Image(systemName: name)
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(iconColor(for: t))
    }

    private func iconColor(for t: Transaction) -> Color {
        if t.isLending { return .orange }
        switch t.type {
        case .income: return .designPrimaryFixedDim
        case .expense: return .designAccentRed
        case .transfer: return .blue
        case .lending: return .orange
        case .adjustment: return .designAccentPurple
        }
    }

    private func titleText(for t: Transaction) -> String {
        if let d = t.lendingDirection { return d.displayName }
        if t.type == .transfer { return t.type.displayName }
        return t.category?.name ?? t.type.displayName
    }

    private func subtitleText(for t: Transaction) -> String? {
        if t.isLending || t.type == .transfer {
            let from = t.account?.name ?? "—"
            let to = t.toAccount?.name ?? "—"
            return "\(from) → \(to)"
        }
        return t.note
    }

    private func amountColor(for t: Transaction) -> Color {
        switch t.type {
        case .income: return .designPrimaryFixedDim
        case .expense: return .designAccentRed
        case .transfer: return .blue
        case .lending: return t.amount >= 0 ? .designPrimaryFixedDim : .orange
        case .adjustment: return t.amount >= 0 ? .designPrimaryFixedDim : .designAccentRed
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
        let accountID = account.id

        let asSource: NSFetchRequest<Transaction> = {
            let req = NSFetchRequest<Transaction>(entityName: "Transaction")
            req.predicate = NSPredicate(format: "account.id == %@ AND parentTransaction == nil", accountID as CVarArg)
            req.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
            return req
        }()
        let asDest: NSFetchRequest<Transaction> = {
            let req = NSFetchRequest<Transaction>(entityName: "Transaction")
            req.predicate = NSPredicate(format: "toAccount.id == %@ AND parentTransaction == nil", accountID as CVarArg)
            req.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
            return req
        }()
        let source = (try? modelContext.fetch(asSource)) ?? []
        let dest = (try? modelContext.fetch(asDest)) ?? []
        transactions = (source + dest).sorted { $0.date > $1.date }
    }

}
