import SwiftUI
@preconcurrency import CoreData

struct AccountDetailView: View {
    // NSManagedObject refreshes via NotificationCenter.transactionDidChange —
    // not through ObservableObject. Don't add @ObservedObject here.
    let account: Account
    @Environment(\.managedObjectContext) private var modelContext
    @Environment(AppContainer.self) private var appContainer
    @State private var balance: Decimal = 0
    @State private var transactions: [Transaction] = []
    @State private var showEditSheet = false
    /// 按年月折叠的展开状态。收敛规则住在共享的 `MonthExpansionState` 里（可单测），
    /// 这里只持有一份。
    @State private var expansion = MonthExpansionState()

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
                .accessibilityLabel(Text("编辑账户"))
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

                // 对账功能测试覆盖不足，暂不上架：入口只留在 Debug 包，Release 里整段不编译。
                // 与下方 OCRTestView 同款门控。对账视图与 service 都保留着，随时可进来继续测。
                #if DEBUG
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
                #endif

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

    // MARK: - Transaction List

    @ViewBuilder
    private var transactionList: some View {
        let groups = transactionDateGroups
        let months = groups.groupedByMonth()
        // 余额必须由**全量**日组回推，与展开了哪些月份无关：只喂展开的月份，
        // 被收起月份之前的所有天的余额会整体偏移。
        let balances = groups.dailyClosingBalances(startingFrom: balance)
        ForEach(months) { month in
            VStack(alignment: .leading, spacing: 8) {
                monthHeader(month)
                if expansion.isExpanded(month.month) {
                    // 天组间距沿用本页既有的 24pt——月份头自己充当月与月之间的分隔，
                    // 不再额外加间距（否则展开后比改版前更松散）。
                    VStack(alignment: .leading, spacing: 24) {
                        ForEach(month.dayGroups) { group in
                            daySection(group, balances: balances)
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
                    // 14pt = 与明细行副标题（designBodySmall）同档；原先是 designLabel 的 12pt，偏小。
                    // 家族/字重仍沿用 designLabel 的 JetBrainsMono-Bold，relativeTo 用 .caption 好与
                    // 那档正文同步缩放；日头与月合计各保持原样（12pt / 13pt）。
                    .font(.custom("JetBrainsMono-Bold", size: 14, relativeTo: .caption))
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
                    CurrencyText(amount: dayBalance, currencyCode: account.currencyCode, size: 13, foregroundColor: Color.designOnSurfaceVariant.opacity(0.6))
                }
            }

            ForEach(group.transactions, id: \.objectID) { t in
                NavigationLink {
                    TransactionDetailView(transaction: t)
                } label: {
                    TransactionRowView(transaction: t)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Date grouping

    private var transactionDateGroups: [TransactionDayGroup] {
        transactions.groupedByDay()
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
        // 注意是**每次** load 都收敛一次，不是只在首次设：`load()` 会在交易增删改后重跑
        // （本页走 transactionDidChange，从交易详情返回时还会再走 onAppear），
        // 而「最新月份被删空 / 改期到更早月份」「跨月后录的第一笔」都要靠这次收敛纠正。
        // 规则本身在共享的 `MonthExpansionState.reconcile` 里，有单测。
        expansion.reconcile(months: transactionDateGroups.groupedByMonth().map(\.month))
    }

}
