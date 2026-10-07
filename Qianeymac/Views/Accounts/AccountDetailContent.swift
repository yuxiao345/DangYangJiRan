import SwiftUI
@preconcurrency import CoreData

struct AccountDetailContent: View {
    @Environment(AppContainer.self) private var appContainer
    @Environment(\.managedObjectContext) private var modelContext
    let account: Account
    @State private var transactions: [Transaction] = []
    @State private var balance: Decimal = 0
    @State private var selectedTransaction: Transaction?
    /// 按年月折叠的展开状态。收敛规则住在共享的 `MonthExpansionState` 里（可单测），
    /// 这里只持有一份。
    @State private var expansion = MonthExpansionState()
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

    private var transactionDateGroups: [TransactionDayGroup] {
        transactions.groupedByDay()
    }

    @ViewBuilder
    private var transactionList: some View {
        let groups = transactionDateGroups
        let months = groups.groupedByMonth()
        // 余额必须由**全量**日组回推，与展开了哪些月份无关：只喂展开的月份，
        // 被收起月份之前的所有天的余额会整体偏移。
        let balances = groups.dailyClosingBalances(startingFrom: balance)

        if transactions.isEmpty {
            Text("暂无交易记录")
                .foregroundStyle(Color.designOnSurfaceVariant)
                .padding(.top, 20)
        } else {
            ForEach(months) { month in
                VStack(alignment: .leading, spacing: 8) {
                    monthHeader(month)
                    if expansion.isExpanded(month.month) {
                        // 天组间距沿用本页既有的 20pt——月份头自己充当月与月之间的分隔，
                        // 不再额外加间距（否则展开后比改版前更松散）。
                        VStack(alignment: .leading, spacing: 20) {
                            ForEach(month.dayGroups) { group in
                                daySection(group, balances: balances)
                            }
                        }
                    }
                }
            }
        }
    }

    /// 月份分组头：chevron 右→下旋转 + 月份标题 + 当月收支合计。
    ///
    /// 合计口径是原始 `amount` 的正负号（进账 / 出账），不是按 `type` 分的收入 / 支出，
    /// 详见 `TransactionMonthGroup.outflow`；**因此两个合计的颜色与下面那些行的行色不是
    /// 同一套语义**（转账行蓝且抹掉符号、借贷负数行橙、支出行恒红，表头只有流入绿 /
    /// 流出红两桶），别照着行色去调表头。金额与回推余额同口径，是同一笔。
    /// 用 chevron 旋转而非 `DisclosureGroup`：交易行是通栏玻璃卡，
    /// `DisclosureGroup` 自带的系统缩进会把卡片边缘顶歪。
    private func monthHeader(_ month: TransactionMonthGroup) -> some View {
        let isExpanded = expansion.isExpanded(month.month)
        return Button {
            withAnimation(.easeInOut(duration: 0.25)) {
                expansion.toggle(month.month)
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.designOnSurfaceVariant)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))

                Text(month.title)
                    .font(.designLabel)
                    .foregroundStyle(Color.designOnSurfaceVariant)

                Spacer()

                // 两个合计都只在非零时出现，空月份不显示「+¥0.00」这种噪音。
                if month.inflow > 0 {
                    CurrencyText(amount: month.inflow, currencyCode: account.currencyCode,
                                 showSign: true, size: 13,
                                 foregroundColor: .designPrimaryFixedDim)
                }
                if month.outflow < 0 {
                    CurrencyText(amount: month.outflow, currencyCode: account.currencyCode,
                                 size: 13, foregroundColor: .designAccentRed)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text(isExpanded ? "收起该月明细" : "展开该月明细"))
    }

    private func daySection(_ group: TransactionDayGroup, balances: [Date: Decimal]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(group.title)
                    .font(.designLabel)
                    .foregroundStyle(Color.designOnSurfaceVariant.opacity(0.6))
                Spacer()
                if let dayBalance = balances[group.day] {
                    CurrencyText(amount: dayBalance, currencyCode: account.currencyCode,
                                 size: 13, foregroundColor: Color.designOnSurfaceVariant.opacity(0.6))
                }
            }

            ForEach(group.transactions, id: \.objectID) { t in
                Button {
                    selectedTransaction = t
                } label: {
                    TransactionRowView(transaction: t)
                }
                .buttonStyle(.plain)
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

        // 首屏只展开最新一个月，其余收起（银行 App 的通行做法）。
        // 每次 load 都收敛一次，规则在共享的 `MonthExpansionState.reconcile`（有单测），
        // 与 iOS 的 AccountDetailView 调的是同一份实现。
        // 本页目前只在 push 进来时 load 一次（没有 transactionDidChange 观察者，行内编辑的
        // sheet 也没有 onDismiss: load()），所以「刷新后收敛」这条路径暂时触发不到 ——
        // 但别因此把这行当多余删掉：一旦补上刷新（iOS 那边已有），少了它就会出现
        // 「最新月份被删空后整页一个展开的月份都不剩」的坏状态。
        expansion.reconcile(months: transactionDateGroups.groupedByMonth().map(\.month))
    }
}
