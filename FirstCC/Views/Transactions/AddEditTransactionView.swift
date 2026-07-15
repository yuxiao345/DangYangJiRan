import SwiftUI
@preconcurrency import CoreData
import PhotosUI

enum PickerSheetType: Identifiable {
    case account, toAccount, category, member, merchant, project, template
    var id: Self { self }
}

protocol NameProviding {
    var name: String { get }
}
extension Account: NameProviding {}
extension Category: NameProviding {}
extension Member: NameProviding {}
extension Merchant: NameProviding {}
extension Project: NameProviding {}

struct SplitItemDraft: Identifiable {
    var id = UUID()
    var amount: Decimal = 0
    var category: Category?
    var note: String = ""
    var member: Member?
    var merchant: Merchant?
    var project: Project?
}

struct AddEditTransactionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var modelContext
    @Environment(AppContainer.self) private var appContainer

    let editing: Transaction?
    let displayMode: Bool

    @State private var isEditing: Bool = false
    @State private var type: TransactionType = .expense
    @State private var amount: Decimal = 0
    @State private var amountString: String = ""
    @State private var showNumpad: Bool = false
    @State private var destAmount: Decimal = 0
    @State private var destAmountString: String = ""
    @State private var editingDestAmount: Bool = false
    @State private var showTemplates: Bool = false
    @State private var note: String = ""
    @State private var date: Date = Date()
    @State private var selectedAccount: Account?
    @State private var selectedToAccount: Account?
    @State private var selectedCategory: Category?
    @State private var selectedMember: Member?
    @State private var selectedMerchant: Merchant?
    @State private var selectedProject: Project?

    @State private var accounts: [Account] = []
    @State private var categories: [Category] = []
    @State private var members: [Member] = []
    @State private var merchants: [Merchant] = []
    @State private var projects: [Project] = []
    @State private var templates: [TransactionTemplate] = []
    @State private var showDeleteAlert = false
    @State private var errorMessage: String?
    @State private var pickerSheet: PickerSheetType?
    @State private var selectedPickerItems: [PhotosPickerItem] = []
    @State private var photoDataList: [Data] = []
    @State private var selectedPhotoItem: PhotoItem?

    // Reimbursement
    @State private var isReimbursable: Bool = false
    @State private var pendingExpenses: [Transaction] = []
    @State private var selectedExpenseIDs: Set<UUID> = []
    @State private var showReimbursementSection: Bool = false
    @State private var showAllPendingExpenses = false

    // Lending
    @State private var lendingDirection: LendingDirection = .lendOut
    @State private var pendingLendingTransactions: [Transaction] = []
    @State private var selectedLendingIDs: Set<UUID> = []
    @State private var showLendingSettlementSection: Bool = false

    // Split
    @State private var isSplit = false
    @State private var showDatePicker = false
    @State private var splitItems: [SplitItemDraft] = []
    @State private var selectedSplitItemID: UUID?
    @State private var splitAmountString: String = ""

    // Exchange rate
    @State private var exchangeRate: Decimal?
    @State private var isFetchingRate = false
    @State private var selectedCurrencyCode: String = "CNY"

    // Display-only data (loaded when displayMode=true, isViewing)
    @State private var linkedRefunds: [Transaction] = []
    @State private var settledExpenses: [Transaction] = []
    @State private var settledLendingTransactions: [Transaction] = []
    @State private var showRefundSheet = false
    @State private var showSplitForm = false

    private let currencies: [String] = ["CNY", "USD", "EUR", "JPY", "GBP", "HKD", "AUD", "CAD", "KRW", "TWD", "SGD", "CHF", "NZD", "THB", "MYR", "INR"]

    private let splitAmountFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        f.locale = Locale(identifier: "en_US")
        return f
    }()

    init(editing: Transaction? = nil, prefillType: TransactionType? = nil, prefillExpenseIDs: [UUID] = [], prefillDate: Date? = nil, displayMode: Bool = false) {
        self.editing = editing
        self.displayMode = displayMode
        if displayMode { _isEditing = State(initialValue: false) }
        if let t = prefillType {
            _type = State(initialValue: t)
        }
        if !prefillExpenseIDs.isEmpty {
            _selectedExpenseIDs = State(initialValue: Set(prefillExpenseIDs))
            _showReimbursementSection = State(initialValue: true)
        }
        if let d = prefillDate {
            _date = State(initialValue: d)
        }
    }

    private var isViewing: Bool { displayMode && !isEditing }

    private var isCrossCurrencyTransfer: Bool {
        guard type == .transfer,
              let src = selectedAccount, let dst = selectedToAccount else { return false }
        return src.effectiveCurrencyCode != dst.effectiveCurrencyCode
    }

    /// Whether the viewed transfer is an inflow record (account = destination, toAccount = source)
    private var isViewingTransferInflow: Bool {
        isViewing && type == .transfer && (editing?.amount ?? 0) >= 0
    }

    private var accountLabel: String {
        if type == .transfer || type == .lending {
            return isViewingTransferInflow ? String(localized: "转入账户") : String(localized: "转出账户")
        }
        return String(localized: "账户")
    }

    private var toAccountLabel: String {
        return isViewingTransferInflow ? String(localized: "转出账户") : String(localized: "转入账户")
    }

    var body: some View {
        baseContent
            .designScreen()
            .animation(.easeInOut(duration: 0.25), value: showNumpad)
            .task { loadData(); prefillEditing(); syncAmountString(); loadDisplayData() }
            .onChange(of: pickerSheet) { _, newValue in
                if newValue != nil { loadData() }
            }
            .onChange(of: type) { _, _ in loadCategories(); loadPendingExpenses(); loadPendingLendingTransactions(); destAmount = 0; destAmountString = "" }
            .onChange(of: selectedAccount) { _, _ in
                selectedLendingIDs = []
                loadPendingLendingTransactions()
                if editing == nil {
                    selectedCurrencyCode = selectedAccount?.currencyCode ?? "CNY"
                    exchangeRate = nil
                    if needsExchangeRate { fetchExchangeRate() }
                }
            }
            .onChange(of: selectedToAccount) { _, _ in
                selectedLendingIDs = []
                loadPendingLendingTransactions()
                destAmount = 0; destAmountString = ""
                if needsExchangeRate { fetchExchangeRate() }
            }
            .onChange(of: selectedExpenseIDs) { _, _ in
                guard !selectedExpenseIDs.isEmpty, editing == nil else { return }
                amount = selectedReimbursementTotal
                syncAmountString()
            }
            .alert("确认删除", isPresented: $showDeleteAlert) {
                Button("取消", role: .cancel) {}
                Button("删除", role: .destructive) { delete() }
            } message: {
                Text("此操作不可撤销，确定要删除此交易吗？")
            }
            .errorAlert("保存失败", message: $errorMessage)
            .sheet(item: $pickerSheet) { sheet in
                pickerContent(for: sheet)
            }
            .sheet(item: $selectedPhotoItem) { item in
                FullScreenPhotoView(data: item.data)
            }
            .sheet(isPresented: $showRefundSheet) {
                if let t = editing {
                    RefundSheetView(original: t) {
                        loadLinkedRefunds()
                    }
                }
            }
            .sheet(isPresented: $showSplitForm) {
                if let t = editing, let ledger = appContainer.currentLedger {
                    SplitFormView(transaction: t, ledger: ledger)
                }
            }
            .sheet(isPresented: $showDatePicker) {
                datePickerSheet
            }
    }

    private var datePickerSheet: some View {
        NavigationStack {
            VStack(spacing: 0) {
                DatePicker("", selection: $date, displayedComponents: [.date])
                    .datePickerStyle(.graphical)
                    .padding(.horizontal)

                HStack {
                    Text("时间")
                        .font(.designBodyMedium)
                        .foregroundStyle(.secondary)
                    Spacer()
                    DatePicker("", selection: $date, displayedComponents: [.hourAndMinute])
                        .labelsHidden()
                }
                .padding(.horizontal)
                .padding(.top, 8)

                Spacer()
            }
            .navigationTitle("选择日期")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("确认") { showDatePicker = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder
    private var baseContent: some View {
        if displayMode {
            contentView
                .navigationTitle(isEditing ? "编辑交易" : "交易详情")
                .navigationBarTitleDisplayMode(.inline)
                .navigationBarBackButtonHidden(isEditing)
                .toolbar { displayModeToolbar }
        } else {
            NavigationStack {
                contentView
                    .navigationTitle(editing != nil ? "编辑交易" : "记一笔")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { normalToolbar }
            }
        }
    }

    private var contentView: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 16) {
                    // Template quick-pick (hidden in display mode)
                    if !displayMode, !templates.isEmpty {
                        templateSection
                    }

                    Group {
                        // Type switcher
                        typeSwitcher

                        // Amount display + toggles
                        amountSection
                    }

                    // Cross-currency transfer: dest amount
                    if isCrossCurrencyTransfer {
                        destAmountSection
                    }

                    Group {
                        // Account grid
                        if !accounts.isEmpty {
                            accountGridSection
                        }

                        // To-account for transfer/lending
                        if (type == .transfer || type == .lending), !accounts.isEmpty {
                            toAccountGridSection
                        }

                        // Category grid (not split/transfer/lending)
                        if !isSplit, type != .transfer, type != .lending {
                            categoryGridSection
                            if let cat = selectedCategory, (cat.children?.count ?? 0) > 0 {
                                Text("已选择上级分类「\(cat.name)」，可展开选择更具体的子分类")
                                    .font(.caption).foregroundStyle(.orange)
                                    .padding(.horizontal)
                            }
                        }

                        // Split detail
                        if isSplit, type == .expense, !isViewing {
                            splitDetailSection
                        }

                        // Member grid
                        if !isSplit, type != .transfer, type != .lending {
                            memberGridSection
                        }

                        // Merchant + Project
                        if !isSplit, type != .transfer, type != .lending {
                            merchantSection
                            projectSection
                        }

                        // Lending direction
                        if type == .lending {
                            lendingDirectionSection
                        }

                        // Exchange rate
                        if needsExchangeRate {
                            exchangeRateSection
                        }

                        // Pending lending settlement (not in view mode)
                        if !isViewing, (lendingDirection == LendingDirection.collect || lendingDirection == LendingDirection.repay), !pendingLendingTransactions.isEmpty {
                            pendingLendingSection
                        }

                        // Pending reimbursement (not in view mode)
                        if !isViewing, type == .income, !pendingExpenses.isEmpty {
                            pendingReimbursementSection
                        }

                        // Details (note, date, photo)
                        detailsSection
                    }
                    .disabled(isViewing)

                    // --- Read-only extra sections (isViewing only) ---
                    if isViewing {
                        displayOnlySections
                    }

                    // Delete button (not in view mode)
                    if editing != nil, !isViewing {
                        deleteButton
                    }
                }
                .padding(16)
            }

            // Bottom: numpad + save button (hidden in view mode)
            if !isViewing {
                VStack(spacing: 12) {
                    if showNumpad {
                        if selectedSplitItemID != nil {
                            HStack {
                                Text("编辑子项金额")
                                    .font(.designLabel)
                                    .foregroundStyle(Color.designOnSurfaceVariant)
                                Spacer()
                                Text("\(CurrencyFormatter.currencySymbol(for: selectedCurrencyCode))\(splitAmountString.isEmpty ? "0.00" : splitAmountString)")
                                    .font(.custom("JetBrainsMono-Medium", fixedSize: 18))
                                    .foregroundStyle(Color.designPrimary)
                            }
                            .padding(.horizontal, 4)
                        }
                        numpadView
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        HStack(spacing: 12) {
                            Button {
                                clearAmount()
                            } label: {
                                Text("清空")
                                    .font(.designLabel)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 48)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(Color.designSurfaceContainer.opacity(0.5))
                                    )
                                    .foregroundStyle(Color.designOnSurfaceVariant)
                            }
                            .buttonStyle(.plain)
                            Button {
                                withAnimation { dismissNumpad() }
                            } label: {
                                Text("确认")
                                    .font(.designLabel)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 48)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(Color.designPrimaryContainer.opacity(0.2))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(Color.designPrimaryContainer.opacity(0.4), lineWidth: 1)
                                    )
                                    .foregroundStyle(Color.designPrimaryContainer)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    if !showNumpad {
                    Button {
                        save()
                    } label: {
                        HStack(spacing: 8) {
                            Text(editing != nil ? "更新账单" : "保存账单")
                                .font(.designBodyMedium.weight(.bold))
                            Image(systemName: "paperplane")
                                .font(.system(size: 16))
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(
                            Capsule()
                                .fill(Color.designPrimaryContainer.opacity(0.85))
                                .shadow(color: Color.designPrimaryContainer.opacity(0.4), radius: 20, x: 0, y: 0)
                        )
                        .foregroundStyle(Color.designOnPrimaryContainer)
                    }
                    .disabled(!canSave)
                    .opacity(canSave ? 1 : 0.4)
                    .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
                .padding(.top, 12)
                .background(
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .overlay(alignment: .top) {
                            Rectangle()
                                .fill(Color.designGlassBorderHighlight)
                                .frame(height: 1)
                        }
                )
            }
        }
    }

    // MARK: - Toolbars

    @ToolbarContentBuilder
    private var normalToolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("取消") { dismiss() }
        }
    }

    @ToolbarContentBuilder
    private var displayModeToolbar: some ToolbarContent {
        if isEditing {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { cancelEditing() }
            }
            ToolbarItem(placement: .primaryAction) {
                Button("保存") { save() }
                    .disabled(!canSave)
            }
        } else {
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 12) {
                    if canRefund {
                        Button { showRefundSheet = true } label: {
                            Label("退款", systemImage: "arrow.uturn.backward")
                        }
                    }
                    Button { enterEditMode() } label: {
                        Label("编辑", systemImage: "pencil")
                    }
                    Button(role: .destructive) { showDeleteAlert = true } label: {
                        Label("删除", systemImage: "trash")
                    }
                }
            }
        }
    }

    // MARK: - Display-Only Sections

    @ViewBuilder
    private var displayOnlySections: some View {
        // Split children read-only
        if let t = editing, t.hasSplitChildren, let children = t.splitChildren {
            VStack(alignment: .leading, spacing: 8) {
                Text("拆分明细")
                    .font(.designLabel)
                    .foregroundStyle(Color.designPrimary.opacity(0.8))
                VStack(spacing: 8) {
                    ForEach(Array(children)) { child in
                        HStack {
                            if let cat = child.category {
                                Image(systemName: cat.iconName)
                                    .foregroundStyle(Color(hex: cat.colorHex))
                                    .frame(width: 24)
                            } else {
                                Image(systemName: "questionmark.circle")
                                    .foregroundStyle(Color.designOnSurfaceVariant)
                                    .frame(width: 24)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(child.category.map { LocalizedStringKey($0.name) } ?? "未分类")
                                    .font(.designBodyMedium)
                                    .foregroundStyle(child.category != nil ? Color.designOnSurface : Color.designOnSurfaceVariant)
                                HStack(spacing: 4) {
                                    if let m = child.member {
                                        Text(m.name)
                                            .font(.designBodySmall)
                                            .foregroundStyle(Color.designOnSurfaceVariant)
                                    }
                                    if let n = child.note, !n.isEmpty {
                                        if child.member != nil { Text("·").font(.designBodySmall).foregroundStyle(.tertiary) }
                                        Text(n)
                                            .font(.designBodySmall)
                                            .foregroundStyle(.tertiary)
                                            .lineLimit(1)
                                    }
                                }
                            }
                            Spacer()
                            CurrencyText(amount: abs(child.amount), currencyCode: child.currencyCode, size: 17, foregroundColor: .designAccentRed)
                        }
                    }
                }
                .padding(12)
                .glassCard(cornerRadius: 12)
            }
        }

        // Member split group
        if let group = editing?.splitGroup {
            VStack(alignment: .leading, spacing: 8) {
                Text("成员分摊")
                    .font(.designLabel)
                    .foregroundStyle(Color.designPrimary.opacity(0.8))
                NavigationLink {
                    SplitDetailView(splitGroup: group)
                } label: {
                    HStack {
                        Label("成员分摊", systemImage: "person.2.circle")
                            .foregroundStyle(Color.designOnSurface)
                        Spacer()
                        Text(group.settlementStatus.displayName)
                            .font(.designBodySmall)
                            .foregroundStyle(group.settlementStatus == .settled ? Color.designPrimaryFixedDim : .orange)
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(Color.designOnSurfaceVariant)
                    }
                    .padding(12)
                    .glassCard(cornerRadius: 12)
                }
                .buttonStyle(.plain)
            }
        } else if let t = editing, t.type == .expense, !t.isSplitParent, !t.hasSplitChildren {
            VStack(alignment: .leading, spacing: 8) {
                Text("成员分摊")
                    .font(.designLabel)
                    .foregroundStyle(Color.designPrimary.opacity(0.8))
                Button {
                    showSplitForm = true
                } label: {
                    Label("创建成员分摊", systemImage: "person.2.badge.plus")
                        .foregroundStyle(Color.designAccentGreen)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .glassCard(cornerRadius: 12)
                }
                .buttonStyle(.plain)
            }
        }

        // Refund linking
        if let t = editing, t.refundGroupId != nil {
            VStack(alignment: .leading, spacing: 8) {
                Text("退款关联")
                    .font(.designLabel)
                    .foregroundStyle(Color.designPrimary.opacity(0.8))
                HStack {
                    Label("原交易退款", systemImage: "arrow.uturn.backward")
                        .foregroundStyle(Color.designOnSurface)
                    Spacer()
                    Text("已关联")
                        .font(.designBodySmall)
                        .foregroundStyle(Color.designPrimaryContainer)
                }
                .padding(12)
                .glassCard(cornerRadius: 12)
            }
        }

        // Linked refunds list
        if !linkedRefunds.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("已退款")
                    .font(.designLabel)
                    .foregroundStyle(Color.designPrimary.opacity(0.8))
                VStack(spacing: 8) {
                    ForEach(linkedRefunds, id: \.objectID) { refund in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("退款金额")
                                    .font(.designBodyMedium)
                                    .foregroundStyle(Color.designOnSurface)
                                Text(refund.date.formatted(date: .abbreviated, time: .omitted))
                                    .font(.designBodySmall)
                                    .foregroundStyle(Color.designOnSurfaceVariant)
                            }
                            Spacer()
                            CurrencyText(amount: abs(refund.amount), currencyCode: refund.currencyCode, size: 17, foregroundColor: .designPrimaryFixedDim)
                        }
                    }
                }
                .padding(12)
                .glassCard(cornerRadius: 12)
            }
        }

        // Reimbursement status
        if let t = editing, t.isReimbursable {
            VStack(alignment: .leading, spacing: 8) {
                Text("报销状态")
                    .font(.designLabel)
                    .foregroundStyle(Color.designPrimary.opacity(0.8))
                HStack {
                    Text("报销状态")
                        .font(.designBodyMedium)
                        .foregroundStyle(Color.designOnSurface)
                    Spacer()
                    switch t.reimbursementStatus {
                    case .pending:
                        Text(ReimbursementStatus.pending.displayName).foregroundStyle(.orange)
                    case .reimbursed:
                        Text(ReimbursementStatus.reimbursed.displayName).foregroundStyle(Color.designPrimaryFixedDim)
                    default:
                        Text("—").foregroundStyle(Color.designOnSurfaceVariant)
                    }
                }
                .padding(12)
                .glassCard(cornerRadius: 12)
            }
        }

        // Settled expenses (报销结算)
        if !settledExpenses.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("报销结算")
                    .font(.designLabel)
                    .foregroundStyle(Color.designPrimary.opacity(0.8))
                VStack(spacing: 8) {
                    ForEach(settledExpenses, id: \.objectID) { expense in
                        HStack {
                            Text(LocalizedStringKey(expense.category?.name ?? ""))
                                .font(.designBodyMedium)
                                .foregroundStyle(Color.designOnSurface)
                            Spacer()
                            CurrencyText(amount: abs(expense.amount), currencyCode: expense.currencyCode, size: 17)
                        }
                    }
                }
                .padding(12)
                .glassCard(cornerRadius: 12)
            }
        }

        // Lending status
        if let t = editing, t.isLending {
            VStack(alignment: .leading, spacing: 8) {
                Text("借贷状态")
                    .font(.designLabel)
                    .foregroundStyle(Color.designPrimary.opacity(0.8))
                HStack {
                    Text("借贷状态")
                        .font(.designBodyMedium)
                        .foregroundStyle(Color.designOnSurface)
                    Spacer()
                    switch t.lendingStatus {
                    case .pending:
                        if let d = t.lendingDirection {
                            Text(LocalizedStringKey(d.pendingLabel)).foregroundStyle(.orange)
                        }
                    case .settled:
                        Text(LendingStatus.settled.displayName).foregroundStyle(Color.designPrimaryFixedDim)
                    case .none:
                        Text("—").foregroundStyle(Color.designOnSurfaceVariant)
                    }
                }
                .padding(12)
                .glassCard(cornerRadius: 12)
            }

            if !settledLendingTransactions.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("借贷结算")
                        .font(.designLabel)
                        .foregroundStyle(Color.designPrimary.opacity(0.8))
                    VStack(spacing: 8) {
                        ForEach(settledLendingTransactions, id: \.objectID) { item in
                            HStack {
                                Text(LocalizedStringKey(item.lendingDirection?.displayName ?? ""))
                                    .font(.designBodyMedium)
                                    .foregroundStyle(Color.designOnSurface)
                                Spacer()
                                CurrencyText(amount: abs(item.amount), currencyCode: item.currencyCode, size: 17)
                            }
                        }
                    }
                    .padding(12)
                    .glassCard(cornerRadius: 12)
                }
            }
        }

        // Tags
        if let t = editing, !t.tags.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("标签")
                    .font(.designLabel)
                    .foregroundStyle(Color.designPrimary.opacity(0.8))
                FlowLayout(spacing: 6) {
                    ForEach(t.tags, id: \.self) { tag in
                        Text(tag)
                            .font(.designBodySmall)
                            .foregroundStyle(Color.designOnSurfaceVariant)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.designPrimaryContainer.opacity(0.1))
                            .clipShape(Capsule())
                    }
                }
                .padding(12)
                .glassCard(cornerRadius: 12)
            }
        }
    }

    // MARK: - Template Section

    private var templateSection: some View {
        VStack(spacing: 0) {
            // Collapsed: just the label + expand button
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showTemplates.toggle()
                }
            } label: {
                HStack {
                    Text("模板")
                        .font(.designLabel)
                        .foregroundStyle(Color.designOnSurfaceVariant)
                    Spacer()
                    HStack(spacing: 2) {
                        Text(showTemplates ? "收起" : "展开")
                        Image(systemName: showTemplates ? "chevron.up" : "chevron.down")
                    }
                    .font(.designLabel)
                    .foregroundStyle(Color.designAccentGreen)
                }
            }
            .buttonStyle(.plain)

            // Expanded: 4 common templates + 更多
            if showTemplates, !templates.isEmpty {
                HStack(spacing: 8) {
                    ForEach(topRecentItems(items: templates, recentKey: "recent_template", selected: nil)) { template in
                        templateChip(template)
                    }
                    Button {
                        openPicker(.template)
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 16))
                            Text("更多")
                                .font(.custom("SpaceGrotesk-Medium", fixedSize: 11))
                        }
                        .frame(width: 64, height: 56)
                        .glassCard(cornerRadius: 12)
                        .foregroundStyle(Color.designAccentGreen)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 8)
            }
        }
        .padding(12)
        .glassCard(cornerRadius: 12)
    }

    // MARK: - Type Switcher

    private var typeSwitcher: some View {
        HStack(spacing: 4) {
            ForEach([TransactionType.expense, .income, .transfer, .lending], id: \.self) { t in
                Button {
                    type = t
                } label: {
                    Label(t.displayName, systemImage: t.systemIcon)
                        .font(.designLabel)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            type == t
                                ? Color.designPrimaryContainer.opacity(0.2)
                                : Color.clear
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(
                                    type == t ? Color.designPrimaryContainer.opacity(0.4) : Color.clear,
                                    lineWidth: 1
                                )
                        )
                }
                .foregroundStyle(type == t ? Color.designPrimaryContainer : Color.designOnSurfaceVariant)
                .buttonStyle(.plain)
                .disabled(editing != nil)
            }
        }
        .padding(4)
        .glassCard(cornerRadius: 12)
    }

    // MARK: - Amount Section

    private var amountSection: some View {
        // Amount centered, toggles overlay on the right
        return VStack(spacing: 4) {
            Text(isCrossCurrencyTransfer ? "转出金额" : "金额录入")
                .font(.designLabel)
                .foregroundStyle(Color.designOnSurfaceVariant.opacity(0.7))
                .tracking(1.0)
            Button {
                withAnimation {
                    if showNumpad { dismissNumpad() }
                    else { showNumpad = true }
                }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(CurrencyFormatter.currencySymbol(for: selectedCurrencyCode))
                        .font(.custom("SpaceGrotesk-SemiBold", fixedSize: 24))
                        .foregroundStyle(Color.designPrimary)
                    Text(amountString.isEmpty ? "0.00" : amountString)
                        .font(.custom("JetBrainsMono-Medium", fixedSize: 32))
                        .foregroundStyle(Color.designPrimary)
                        .tracking(-0.02)
                    Image(systemName: showNumpad ? "keyboard.arrow.down" : "keyboard.arrow.up")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.designPrimaryContainer.opacity(0.5))
                }
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .overlay(alignment: .trailing) {
            if type == .expense {
                VStack(spacing: 12) {
                    toggleButton(label: "拆分记账", isOn: $isSplit)
                    toggleButton(label: "可报销", isOn: $isReimbursable)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .glassCard(cornerRadius: 24)
        .overlay(alignment: .bottom) {
            // Currency chip
            Menu {
                ForEach(currencies, id: \.self) { code in
                    Button {
                        selectedCurrencyCode = code
                        exchangeRate = nil
                        if needsExchangeRate { fetchExchangeRate() }
                    } label: {
                        Text("\(code) (\(currencyName(code)))")
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(selectedCurrencyCode)
                        .font(.designLabel)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 8))
                }
                .foregroundStyle(Color.designOnSurfaceVariant)
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .background(Color.designSurfaceContainer)
                .clipShape(Capsule())
            }
            .disabled(selectedAccount != nil && (type == .transfer || type == .lending))
            .offset(y: 12)
        }
    }

    private var destAmountSection: some View {
        let destCurrency = selectedToAccount?.currencyCode ?? "CNY"
        return VStack(spacing: 4) {
            // Exchange rate
            if amount != 0, destAmount != 0 {
                let srcCode = selectedAccount?.currencyCode ?? "CNY"
                let rate = destAmount / amount
                Text("1 \(srcCode) ≈ \(rate.formatted(.number.precision(.fractionLength(4)))) \(destCurrency)")
                    .font(.custom("JetBrainsMono-Medium", fixedSize: 13))
                    .foregroundStyle(Color.designOnSurfaceVariant)
            }

            Text("转入金额")
                .font(.designLabel)
                .foregroundStyle(Color.designOnSurfaceVariant.opacity(0.7))
                .tracking(1.0)
            Button {
                withAnimation {
                    if showNumpad && editingDestAmount { dismissNumpad() }
                    else {
                        editingDestAmount = true
                        if destAmount != 0 {
                            destAmountString = CurrencyFormatter.decimalFormatter.string(from: destAmount as NSDecimalNumber) ?? "\(destAmount)"
                        } else { destAmountString = "" }
                        showNumpad = true
                    }
                }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(CurrencyFormatter.currencySymbol(for: destCurrency))
                        .font(.custom("SpaceGrotesk-SemiBold", fixedSize: 24))
                        .foregroundStyle(Color.designPrimary)
                    Text(destAmountString.isEmpty ? "0.00" : destAmountString)
                        .font(.custom("JetBrainsMono-Medium", fixedSize: 32))
                        .foregroundStyle(Color.designPrimary)
                        .tracking(-0.02)
                    Image(systemName: showNumpad && editingDestAmount ? "keyboard.arrow.down" : "keyboard.arrow.up")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.designPrimaryContainer.opacity(0.5))
                }
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .glassCard(cornerRadius: 24)
        .overlay(alignment: .bottom) {
            // Currency chip (non-interactive, locked to dest account)
            Text(destCurrency)
                .font(.designLabel)
                .foregroundStyle(Color.designOnSurfaceVariant)
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .background(Color.designSurfaceContainer)
                .clipShape(Capsule())
                .offset(y: 12)
        }
    }

    private func toggleButton(label: LocalizedStringKey, isOn: Binding<Bool>) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            VStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(isOn.wrappedValue ? Color.designPrimaryFixedDim.opacity(0.2) : Color.designOnSurfaceVariant.opacity(0.1))
                    .frame(width: 36, height: 18)
                    .overlay(alignment: isOn.wrappedValue ? .trailing : .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(isOn.wrappedValue ? Color.designPrimaryFixedDim : Color.designOutline)
                            .frame(width: 12, height: 12)
                            .padding(.horizontal, 2)
                    }
                Text(label)
                    .font(.custom("SpaceGrotesk-Medium", fixedSize: 10))
                    .foregroundStyle(Color.designOnSurfaceVariant.opacity(0.7))
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Account Grid

    // MARK: - Account Row

    private var accountGridSection: some View {
        recentPickerRow(
            title: LocalizedStringKey(accountLabel),
            items: accounts,
            itemIcon: { $0.iconName ?? "creditcard" },
            itemColor: { Color(hex: $0.colorHex ?? "#007AFF") },
            recentKey: "recent_account",
            selectedItem: selectedAccount,
            onSelect: { selectedAccount = $0 },
            onMore: { openPicker(.account) }
        )
    }

    private var toAccountGridSection: some View {
        recentPickerRow(
            title: LocalizedStringKey(toAccountLabel),
            items: accounts.filter { $0.id != selectedAccount?.id },
            itemIcon: { $0.iconName ?? "creditcard" },
            itemColor: { Color(hex: $0.colorHex ?? "#007AFF") },
            recentKey: "recent_toaccount",
            selectedItem: selectedToAccount,
            onSelect: { selectedToAccount = $0 },
            onMore: { openPicker(.toAccount) }
        )
    }

    // MARK: - Category Row

    private var categoryGridSection: some View {
        recentPickerRow(
            title: "分类",
            items: categories,
            itemIcon: { $0.iconName },
            itemColor: { Color(hex: $0.colorHex) },
            recentKey: "recent_category",
            selectedItem: selectedCategory,
            onSelect: { selectedCategory = $0 },
            onMore: { openPicker(.category) }
        )
    }

    // MARK: - Member Row

    private var memberGridSection: some View {
        recentPickerRow(
            title: "成员",
            items: members,
            itemIcon: { _ in "person" },
            itemColor: { _ in Color.designSecondary },
            recentKey: "recent_member",
            selectedItem: selectedMember,
            onSelect: { selectedMember = $0 },
            onMore: { openPicker(.member) }
        )
    }

    // MARK: - Merchant Row

    private var merchantSection: some View {
        recentPickerRow(
            title: "商家",
            items: merchants,
            itemIcon: { _ in "bag" },
            itemColor: { _ in Color.designOnSurfaceVariant },
            recentKey: "recent_merchant",
            selectedItem: selectedMerchant,
            onSelect: { selectedMerchant = $0 },
            onMore: { openPicker(.merchant) }
        )
    }

    // MARK: - Project Row

    private var projectSection: some View {
        recentPickerRow(
            title: "项目",
            items: projects,
            itemIcon: { _ in "folder" },
            itemColor: { _ in Color.designOnSurfaceVariant },
            recentKey: "recent_project",
            selectedItem: selectedProject,
            onSelect: { selectedProject = $0 },
            onMore: { openPicker(.project) }
        )
    }

    // MARK: - Unified Recent Picker Row (4常用 + 更多)

    private func recentPickerRow<T: Identifiable>(
        title: LocalizedStringKey,
        items: [T],
        itemIcon: @escaping (T) -> String,
        itemColor: @escaping (T) -> Color,
        recentKey: String,
        selectedItem: T?,
        onSelect: @escaping (T?) -> Void,
        onMore: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 8) {
            HStack {
                Text(title)
                    .font(.designLabel)
                    .foregroundStyle(Color.designPrimary.opacity(0.8))
                Spacer()
                Button {
                    onMore()
                } label: {
                    HStack(spacing: 2) {
                        Text("更多")
                        Image(systemName: "chevron.right")
                    }
                    .font(.designLabel)
                    .foregroundStyle(Color.designAccentGreen)
                }
            }

            HStack(spacing: 8) {
                ForEach(topRecentItems(items: items, recentKey: recentKey, selected: selectedItem)) { item in
                    Button {
                        let isSel = selectedItem?.id == item.id as? AnyHashable
                        if !isSel {
                            saveRecentID("\(item.id)", forKey: recentKey)
                        }
                        onSelect(isSel ? nil : item)
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: itemIcon(item))
                                .font(.system(size: 18))
                                .foregroundStyle(
                                    selectedItem?.id == item.id as? AnyHashable
                                        ? Color.designPrimaryContainer
                                        : Color.designOnSurfaceVariant
                                )
                            if let np = item as? any NameProviding {
                                Text(LocalizedStringKey(np.name))
                                    .font(.system(size: 10))
                                    .lineLimit(1)
                                    .foregroundStyle(
                                        selectedItem?.id == item.id as? AnyHashable
                                            ? Color.designPrimaryContainer
                                            : Color.designOnSurfaceVariant
                                    )
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .glassCard(cornerRadius: 12)
                        .opacity(selectedItem?.id == item.id as? AnyHashable ? 1 : 0.55)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(
                                    selectedItem?.id == item.id as? AnyHashable
                                        ? Color.designPrimaryContainer.opacity(0.5)
                                        : Color.clear,
                                    lineWidth: 1
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func saveRecentID(_ id: String, forKey key: String) {
        var ids = UserDefaults.standard.stringArray(forKey: key) ?? []
        ids.removeAll { $0 == id }
        ids.insert(id, at: 0)
        UserDefaults.standard.set(Array(ids.prefix(8)), forKey: key)
    }

    /// Returns up to 4 items from the list, prioritizing recently-used and always including the selected item.
    private func topRecentItems<T: Identifiable>(items: [T], recentKey: String, selected: T?) -> [T] {
        let recentIDs = UserDefaults.standard.stringArray(forKey: recentKey) ?? []
        var result: [T] = []

        // Always include selected item first
        if let sel = selected {
            result.append(sel)
        }

        // Add recent items (skip selected since already added)
        for idStr in recentIDs {
            guard result.count < 4 else { break }
            if let item = items.first(where: { "\($0.id)" == idStr }),
               selected?.id != item.id as? AnyHashable {
                result.append(item)
            }
        }

        // Fill remaining slots from items list
        if result.count < 4 {
            for item in items {
                guard result.count < 4 else { break }
                if !result.contains(where: { "\($0.id)" == "\(item.id)" }) {
                    result.append(item)
                }
            }
        }

        return Array(result.prefix(4))
    }

    // MARK: - Split Detail Section

    private var splitDetailSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("拆分明细")
                    .font(.designLabel)
                    .foregroundStyle(Color.designPrimary.opacity(0.8))
                Spacer()
                Button {
                    let remaining = amount - splitTotal
                    splitItems.append(SplitItemDraft(amount: remaining > 0 ? remaining : 0))
                } label: {
                    Label("添加子项", systemImage: "plus")
                        .font(.designLabel)
                        .foregroundStyle(Color.designAccentGreen)
                }
            }

            ForEach(splitItems) { item in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Button {
                            selectSplitItem(item)
                        } label: {
                            HStack(spacing: 4) {
                                Text(CurrencyFormatter.currencySymbol(for: selectedCurrencyCode))
                                    .foregroundStyle(Color.designOnSurfaceVariant)
                                Text(formatSplitItemAmount(item))
                                    .font(.custom("JetBrainsMono-Medium", fixedSize: 17))
                                    .foregroundStyle(selectedSplitItemID == item.id ? Color.designPrimary : Color.designOnSurface)
                            }
                        }
                        .buttonStyle(.plain)
                        Spacer()
                        Button {
                            if selectedSplitItemID == item.id {
                                selectedSplitItemID = nil
                                splitAmountString = ""
                            }
                            splitItems.removeAll { $0.id == item.id }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(Color.designAccentRed)
                        }
                    }
                    HStack(spacing: 8) {
                        splitSubMenu(label: "分类", value: item.category?.name) {
                            ForEach(categories) { cat in
                                let indent = cat.parent != nil ? "    " : ""
                                Button {
                                    if let idx = splitItems.firstIndex(where: { $0.id == item.id }) {
                                        splitItems[idx].category = cat
                                    }
                                } label: {
                                    Label("\(indent)\(cat.name)", systemImage: cat.iconName)
                                }
                            }
                        }
                        if let cat = item.category, (cat.children?.count ?? 0) > 0 {
                            Text("含子分类").font(.system(size: 9)).foregroundStyle(.orange)
                        }
                        splitSubMenu(label: "成员", value: item.member?.name) {
                            ForEach(members) { m in
                                Button {
                                    if let idx = splitItems.firstIndex(where: { $0.id == item.id }) {
                                        splitItems[idx].member = m
                                    }
                                } label: {
                                    Label(m.name, systemImage: m.avatar)
                                }
                            }
                        }
                        splitSubMenu(label: "商家", value: item.merchant?.name) {
                            ForEach(merchants) { m in
                                Button {
                                    if let idx = splitItems.firstIndex(where: { $0.id == item.id }) {
                                        splitItems[idx].merchant = m
                                    }
                                } label: {
                                    Label(m.name, systemImage: "bag")
                                }
                            }
                        }
                        splitSubMenu(label: "项目", value: item.project?.name) {
                            ForEach(projects) { p in
                                Button {
                                    if let idx = splitItems.firstIndex(where: { $0.id == item.id }) {
                                        splitItems[idx].project = p
                                    }
                                } label: {
                                    Label(p.name, systemImage: "folder")
                                }
                            }
                        }
                    }
                    TextField("备注", text: Binding(
                        get: { item.note },
                        set: { if let idx = splitItems.firstIndex(where: { $0.id == item.id }) { splitItems[idx].note = $0 } }
                    ))
                    .font(.designBodySmall)
                    .textFieldStyle(.plain)
                }
                .padding(12)
                .glassCard(cornerRadius: 12)
            }

            HStack {
                Spacer()
                Text("合计 ¥\(splitTotal.formatted(.number.precision(.fractionLength(2)))) / ¥\(amount.formatted(.number.precision(.fractionLength(2))))")
                    .font(.custom("JetBrainsMono-Medium", fixedSize: 14))
                    .foregroundStyle(splitTotal == amount ? Color.designPrimaryFixedDim : Color.designAccentRed)
            }
        }
    }

    private func splitSubMenu<Content: View>(label: LocalizedStringKey, value: String?, @ViewBuilder content: () -> Content) -> some View {
        Menu {
            content()
        } label: {
            HStack(spacing: 4) {
                if let value {
                    Text(LocalizedStringKey(value))
                        .font(.designBodySmall)
                        .foregroundStyle(Color.designOnSurface)
                } else {
                    Text(label)
                        .font(.designBodySmall)
                        .foregroundStyle(Color.designOnSurfaceVariant)
                }
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8))
                    .foregroundStyle(Color.designOnSurfaceVariant.opacity(0.5))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.designSurfaceContainer)
            .clipShape(Capsule())
        }
    }

    // MARK: - Lending Direction

    private var lendingDirectionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("借贷方向")
                .font(.designLabel)
                .foregroundStyle(Color.designPrimary.opacity(0.8))
            HStack(spacing: 4) {
                ForEach(LendingDirection.allCases, id: \.self) { d in
                    Button {
                        lendingDirection = d
                        loadPendingLendingTransactions()
                    } label: {
                        Label(d.displayName, systemImage: d.systemIcon)
                            .font(.designLabel)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(
                                lendingDirection == d
                                    ? Color.designPrimaryContainer.opacity(0.2)
                                    : Color.clear
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(
                                        lendingDirection == d ? Color.designPrimaryContainer.opacity(0.4) : Color.clear,
                                        lineWidth: 1
                                    )
                            )
                    }
                    .foregroundStyle(lendingDirection == d ? Color.designPrimaryContainer : Color.designOnSurfaceVariant)
                    .buttonStyle(.plain)
                    .disabled(editing != nil)
                }
            }
            .padding(4)
            .glassCard(cornerRadius: 12)
        }
    }

    // MARK: - Exchange Rate

    private var exchangeRateSection: some View {
        let rateFrom = (type == .transfer) ? transferExchangeFrom : selectedCurrencyCode
        let rateTo = (type == .transfer) ? transferExchangeTo : ledgerCurrencyCode
        return VStack(alignment: .leading, spacing: 8) {
            Text("跨币种换算")
                .font(.designLabel)
                .foregroundStyle(Color.designPrimary.opacity(0.8))

            VStack(spacing: 12) {
                HStack {
                    Text("汇率")
                        .font(.designBodyCaption)
                        .foregroundStyle(Color.designOnSurfaceVariant)
                    Spacer()
                    if isFetchingRate {
                        ProgressView()
                    } else if let rate = exchangeRate {
                        Text("1 \(rateFrom) = \(rate.formatted(.number.precision(.fractionLength(4)))) \(rateTo)")
                            .font(.custom("JetBrainsMono-Medium", fixedSize: 13))
                            .foregroundStyle(Color.designOnSurfaceVariant)
                    } else {
                        Button("获取汇率") { fetchExchangeRate() }
                            .font(.designLabel)
                            .foregroundStyle(Color.designAccentGreen)
                    }
                }
                if let converted = convertedAmountPreview {
                    HStack {
                        Text("换算金额")
                            .font(.designBodyCaption)
                            .foregroundStyle(Color.designOnSurfaceVariant)
                        Spacer()
                        CurrencyText(amount: converted, currencyCode: rateTo, size: 15, foregroundColor: Color.designPrimaryFixedDim)
                    }
                }
            }
            .padding(12)
            .glassCard(cornerRadius: 12)
        }
    }

    // MARK: - Pending Lending Settlement

    private var pendingLendingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(lendingDirection == LendingDirection.collect ? LocalizedStringKey("关联待收") : LocalizedStringKey("关联待还"))
                .font(.designLabel)
                .foregroundStyle(Color.designPrimary.opacity(0.8))

            VStack(spacing: 8) {
                ForEach(pendingLendingTransactions, id: \.objectID) { item in
                    HStack {
                        Image(systemName: selectedLendingIDs.contains(item.id) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(selectedLendingIDs.contains(item.id) ? Color.designPrimaryFixedDim : Color.designOnSurfaceVariant)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(LocalizedStringKey(item.account?.name ?? ""))
                                .font(.designBodyMedium)
                                .foregroundStyle(Color.designOnSurface)
                            Text(displayLabelForLending(item))
                                .font(.designBodySmall)
                                .foregroundStyle(Color.designOnSurfaceVariant)
                        }
                        Spacer()
                        CurrencyText(amount: abs(item.amount), currencyCode: item.currencyCode, size: 15)
                    }
                    .padding(10)
                    .contentShape(Rectangle())
                    .onTapGesture { toggleLending(item.id) }
                }
                if !selectedLendingIDs.isEmpty {
                    HStack {
                        Text("已选合计")
                            .font(.designBodyMedium)
                            .foregroundStyle(Color.designOnSurface)
                        Spacer()
                        CurrencyText(amount: selectedLendingTotal, currencyCode: ledgerCurrencyCode, size: 17, foregroundColor: Color.designPrimaryFixedDim)
                    }
                    .padding(.top, 4)
                }
            }
            .padding(12)
            .glassCard(cornerRadius: 12)
        }
    }

    // MARK: - Pending Reimbursement

    private var pendingReimbursementSection: some View {
        let visible = showAllPendingExpenses ? pendingExpenses : Array(pendingExpenses.prefix(5))
        let hiddenCount = pendingExpenses.count - 5

        return VStack(alignment: .leading, spacing: 8) {
            Text("关联待报销")
                .font(.designLabel)
                .foregroundStyle(Color.designPrimary.opacity(0.8))

            VStack(spacing: 8) {
                ForEach(visible, id: \.objectID) { expense in
                    HStack {
                        Image(systemName: selectedExpenseIDs.contains(expense.id) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(selectedExpenseIDs.contains(expense.id) ? Color.designPrimaryFixedDim : Color.designOnSurfaceVariant)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(LocalizedStringKey(expense.category?.name ?? ""))
                                .font(.designBodyMedium)
                                .foregroundStyle(Color.designOnSurface)
                            HStack(spacing: 4) {
                                Text(expense.date.formatted(date: .abbreviated, time: .omitted))
                                if let m = expense.member {
                                    Text("·").foregroundStyle(.tertiary)
                                    Text(m.name)
                                }
                                if let p = expense.project {
                                    Text("·").foregroundStyle(.tertiary)
                                    Text(p.name)
                                }
                            }
                            .font(.designBodySmall)
                            .foregroundStyle(Color.designOnSurfaceVariant)
                            if let n = expense.note, !n.isEmpty {
                                Text(n)
                                    .font(.designBodySmall)
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)
                            }
                        }
                        Spacer()
                        CurrencyText(amount: abs(expense.amount), currencyCode: expense.currencyCode, size: 15)
                    }
                    .padding(10)
                    .contentShape(Rectangle())
                    .onTapGesture { toggleExpense(expense.id) }
                }

                if hiddenCount > 0 {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { showAllPendingExpenses.toggle() }
                    } label: {
                        HStack {
                            Image(systemName: showAllPendingExpenses ? "chevron.up" : "chevron.down")
                                .font(.system(size: 10, weight: .medium))
                            Text(showAllPendingExpenses ? "收起" : "展开全部 \(pendingExpenses.count) 条")
                        }
                        .font(.designBodySmall)
                        .foregroundStyle(Color.designAccentGreen)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 2)
                }

                if !selectedExpenseIDs.isEmpty {
                    HStack {
                        Text("已选合计")
                            .font(.designBodyMedium)
                            .foregroundStyle(Color.designOnSurface)
                        Spacer()
                        CurrencyText(amount: selectedReimbursementTotal, currencyCode: ledgerCurrencyCode, size: 17, foregroundColor: Color.designPrimaryFixedDim)
                    }
                    .padding(.top, 4)
                }
            }
            .padding(12)
            .glassCard(cornerRadius: 12)
        }
    }

    // MARK: - Details Section

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("详情")
                .font(.designLabel)
                .foregroundStyle(Color.designPrimary.opacity(0.8))

            VStack(spacing: 12) {
                // Note
                TextField("备注", text: $note)
                    .font(.designBodyMedium)
                    .foregroundStyle(Color.designOnSurface)
                    .padding(12)
                    .background(Color.designSurfaceContainer)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                // Date + Photo
                HStack(spacing: 12) {
                    Button {
                        showDatePicker = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "calendar")
                                .font(.designBodySmall)
                            Text(date.formatted(.dateTime.month(.abbreviated).day(.twoDigits).hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)))
                                .font(.designBodySmall)
                        }
                        .foregroundStyle(Color.designOnSurface)
                        .padding(10)
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .background(Color.designSurfaceContainer)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                    PhotosPicker(selection: $selectedPickerItems, maxSelectionCount: 5, matching: .images) {
                        HStack(spacing: 4) {
                            Image(systemName: "camera")
                            Text("附件")
                        }
                        .font(.designBodySmall)
                        .foregroundStyle(Color.designOnSurfaceVariant)
                        .padding(10)
                        .frame(maxWidth: .infinity)
                        .background(Color.designSurfaceContainer)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(photoDataList.count >= 5)
                }

                // Photo preview
                if !photoDataList.isEmpty {
                    photoGrid
                }
            }
            .padding(12)
            .glassCard(cornerRadius: 16)
        }
        .onChange(of: selectedPickerItems) { _, items in
            Task {
                for item in items {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        photoDataList.append(data)
                    }
                }
                selectedPickerItems = []
            }
        }
    }

    // MARK: - Delete Button

    private var deleteButton: some View {
        Button(role: .destructive) {
            showDeleteAlert = true
        } label: {
            Label("删除此交易", systemImage: "trash")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.designAccentRed.opacity(0.1))
                )
                .foregroundStyle(Color.designAccentRed)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Numpad

    private var numpadView: some View {
        NumpadGrid(
            onDigit: { appendDigit($0) },
            onDot: { appendDot() },
            onDelete: { backspace() }
        )
    }

    private func appendDigit(_ digit: Int) {
        if editingDestAmount {
            if let dotIndex = destAmountString.firstIndex(of: ".") {
                let decimals = destAmountString[dotIndex...].dropFirst()
                if decimals.count >= 2 { return }
            }
            if destAmountString == "0" || destAmountString == "0.00" { destAmountString = "\(digit)" }
            else { destAmountString += "\(digit)" }
        } else if selectedSplitItemID != nil {
            if let dotIndex = splitAmountString.firstIndex(of: ".") {
                let decimals = splitAmountString[dotIndex...].dropFirst()
                if decimals.count >= 2 { return }
            }
            if splitAmountString == "0" || splitAmountString == "0.00" { splitAmountString = "\(digit)" }
            else { splitAmountString += "\(digit)" }
            syncSplitAmountToItem()
        } else {
            if let dotIndex = amountString.firstIndex(of: ".") {
                let decimals = amountString[dotIndex...].dropFirst()
                if decimals.count >= 2 { return }
            }
            if amountString == "0" || amountString == "0.00" { amountString = "\(digit)" }
            else { amountString += "\(digit)" }
            syncAmountFromString()
        }
    }

    private func appendDot() {
        if editingDestAmount {
            if destAmountString.contains(".") { return }
            if destAmountString.isEmpty { destAmountString = "0." }
            else { destAmountString += "." }
        } else if selectedSplitItemID != nil {
            if splitAmountString.contains(".") { return }
            if splitAmountString.isEmpty { splitAmountString = "0." }
            else { splitAmountString += "." }
            syncSplitAmountToItem()
        } else {
            if amountString.contains(".") { return }
            if amountString.isEmpty { amountString = "0." }
            else { amountString += "." }
            syncAmountFromString()
        }
    }

    private func backspace() {
        if editingDestAmount {
            if destAmountString.count <= 1 { destAmountString = "0" }
            else { destAmountString.removeLast() }
        } else if selectedSplitItemID != nil {
            if splitAmountString.count <= 1 { splitAmountString = "0" }
            else { splitAmountString.removeLast() }
            syncSplitAmountToItem()
        } else {
            if amountString.count <= 1 { amountString = "0" }
            else { amountString.removeLast() }
            syncAmountFromString()
        }
    }

    private func clearAmount() {
        if editingDestAmount {
            destAmountString = "0"
        } else if selectedSplitItemID != nil {
            splitAmountString = "0"
            syncSplitAmountToItem()
        } else {
            amountString = "0"
            syncAmountFromString()
        }
    }

    private func dismissNumpad() {
        if editingDestAmount {
            destAmount = Decimal(string: destAmountString.replacingOccurrences(of: ",", with: "")) ?? 0
            editingDestAmount = false
            destAmountString = destAmount != 0 ? CurrencyFormatter.decimalFormatter.string(from: destAmount as NSDecimalNumber) ?? "\(destAmount)" : ""
        }
        showNumpad = false
        syncSplitAmountToItem()
        selectedSplitItemID = nil
        splitAmountString = ""
    }

    private func syncAmountFromString() {
        amount = Decimal(string: amountString.replacingOccurrences(of: ",", with: "")) ?? 0
    }

    private func syncSplitAmountToItem() {
        guard let id = selectedSplitItemID, let idx = splitItems.firstIndex(where: { $0.id == id }) else { return }
        splitItems[idx].amount = Decimal(string: splitAmountString.replacingOccurrences(of: ",", with: "")) ?? 0
    }

    private func selectSplitItem(_ item: SplitItemDraft) {
        if selectedSplitItemID == item.id {
            syncSplitAmountToItem()
            selectedSplitItemID = nil
            splitAmountString = ""
            return
        }
        syncSplitAmountToItem()
        selectedSplitItemID = item.id
        let amt = item.amount
        if amt == 0 { splitAmountString = "" }
        else {
            splitAmountString = CurrencyFormatter.decimalFormatter.string(from: amt as NSDecimalNumber) ?? "\(amt)"
        }
        if !showNumpad { withAnimation { showNumpad = true } }
    }

    private func formatSplitItemAmount(_ item: SplitItemDraft) -> String {
        if item.amount == 0 { return "0.00" }
        return splitAmountFormatter.string(from: item.amount as NSDecimalNumber) ?? "0.00"
    }

    private func syncAmountString() {
        if amount == 0 { amountString = "" }
        else {
            amountString = CurrencyFormatter.decimalFormatter.string(from: amount as NSDecimalNumber) ?? "\(amount)"
        }
    }

    private func templateChip(_ template: TransactionTemplate) -> some View {
        Button {
            applyTemplate(template)
        } label: {
            VStack(spacing: 4) {
                Image(systemName: template.category?.iconName ?? template.type.systemIcon)
                    .font(.system(size: 16))
                Text(LocalizedStringKey(template.name))
                    .font(.custom("SpaceGrotesk-Medium", fixedSize: 11))
                    .lineLimit(1)
            }
            .frame(width: 64, height: 56)
            .glassCard(cornerRadius: 12)
            .foregroundStyle(Color.designOnSurface)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func pickerContent(for sheet: PickerSheetType) -> some View {
        switch sheet {
        case .account:
            SearchablePickerView(
                title: accountLabel,
                items: accounts,
                itemLabel: { $0.name },
                itemIcon: { $0.iconName ?? "creditcard" },
                itemColor: { Color(hex: $0.colorHex ?? "#007AFF") },
                recentKey: "recent_account",
                groupLabel: { $0.type.displayName },
                selection: $selectedAccount
            )
        case .toAccount:
            SearchablePickerView(
                title: toAccountLabel,
                items: accounts.filter { $0.id != selectedAccount?.id },
                itemLabel: { $0.name },
                itemIcon: { $0.iconName ?? "creditcard" },
                itemColor: { Color(hex: $0.colorHex ?? "#007AFF") },
                recentKey: "recent_toaccount",
                groupLabel: { $0.type.displayName },
                selection: $selectedToAccount
            )
        case .category:
            SearchablePickerView(
                title: "选择分类",
                items: categories,
                itemLabel: { cat in
                    let cnt = (cat.children?.count ?? 0)
                    return cnt > 0 ? "\(cat.name) · 含\(cnt)项" : cat.name
                },
                itemIcon: { $0.iconName },
                itemColor: { Color(hex: $0.colorHex) },
                recentKey: "recent_category",
                indentLevel: { item in
                    var depth = 0; var p = item.parent; while p != nil { depth += 1; p = p?.parent }
                    return depth
                },
                childrenProvider: { Array($0.children ?? []) },
                selection: $selectedCategory
            )
        case .member:
            SearchablePickerView(
                title: "选择成员",
                items: members,
                itemLabel: { $0.name },
                itemIcon: { $0.avatar },
                recentKey: "recent_member",
                selection: $selectedMember
            )
        case .merchant:
            SearchablePickerView(
                title: "选择商家",
                items: merchants,
                itemLabel: { $0.name },
                itemIcon: { _ in "bag" },
                recentKey: "recent_merchant",
                onCreate: { name in
                    guard let ledger = appContainer.currentLedger else { return nil }
                    let merchant = Merchant(name: name, sortOrder: merchants.count, context: modelContext)
                    do {
                        try appContainer.merchantService.createMerchant(merchant, ledger: ledger, context: modelContext)
                        return merchant
                    } catch {
                        return nil
                    }
                },
                selection: $selectedMerchant
            )
        case .project:
            SearchablePickerView(
                title: "选择项目",
                items: projects,
                itemLabel: { $0.name },
                itemIcon: { _ in "folder" },
                recentKey: "recent_project",
                selection: $selectedProject
            )
        case .template:
            SearchablePickerView(
                title: "选择模板",
                items: templates,
                itemLabel: { $0.name },
                itemIcon: { $0.category?.iconName ?? "doc.text" },
                itemColor: { _ in .blue },
                recentKey: "recent_template",
                selection: Binding<TransactionTemplate?>(
                    get: { nil },
                    set: { if let t = $0 { applyTemplate(t) } }
                )
            )
        }
    }

    private var photoGrid: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(photoDataList.enumerated()), id: \.offset) { index, data in
                    ZStack(alignment: .topTrailing) {
                        Button {
                            selectedPhotoItem = PhotoItem(data: data)
                        } label: {
                            if let uiImage = UIImage(data: data) {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 64, height: 64)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                        }
                        .buttonStyle(.plain)
                        Button {
                            photoDataList.remove(at: index)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(Color.designAccentRed)
                                .background(Circle().fill(Color.designSurfaceContainerLowest))
                        }
                        .offset(x: 6, y: -6)
                    }
                }
            }
        }
    }

    private func pickerRow(label: String, value: String?) -> some View {
        HStack {
            Text(LocalizedStringKey(label))
                .foregroundStyle(Color.designOnSurface)
            Spacer()
            if let value {
                Text(LocalizedStringKey(value))
                    .foregroundStyle(.secondary)
            } else {
                Text(LocalizedStringKey("选择\(label)"))
                    .foregroundStyle(.secondary)
            }
            Image(systemName: "chevron.up.chevron.down")
                .font(.designBodySmall)
                .foregroundStyle(Color.designOnSurfaceVariant.opacity(0.5))
        }
        .contentShape(Rectangle())
    }

    private var canSave: Bool {
        guard amount != 0, selectedAccount != nil else { return false }
        if type == .transfer || type == .lending {
            guard selectedToAccount != nil else { return false }
        }
        if isSplit && type == .expense {
            guard splitTotal == amount else { return false }
        }
        return true
    }

    private func openPicker(_ sheet: PickerSheetType) {
        loadData()
        pickerSheet = sheet
    }

    private func loadData() {
        guard let ledger = appContainer.currentLedger else { return }
        accounts = (try? appContainer.accountService.fetchAccounts(for: ledger, context: modelContext)) ?? []
        loadCategories()
        members = (try? appContainer.memberService.fetchMembers(for: ledger, context: modelContext))?.filter { $0.isActive } ?? []
        merchants = (try? appContainer.merchantService.fetchMerchants(for: ledger, context: modelContext))?.filter { $0.isActive } ?? []
        projects = (try? appContainer.projectService.fetchProjects(for: ledger, context: modelContext))?.filter { $0.isActive } ?? []
        templates = (try? appContainer.templateService.fetchTemplates(for: ledger, context: modelContext)) ?? []
        loadPendingExpenses()
        loadPendingLendingTransactions()
    }

    private func loadCategories() {
        guard let ledger = appContainer.currentLedger else { return }
        categories = (try? appContainer.categoryService.fetchCategories(for: ledger, type: type, context: modelContext)) ?? []
    }

    private func prefillEditing() {
        guard let t = editing else { return }
        type = t.type
        amount = abs(t.amount)
        note = t.note ?? ""
        date = t.date
        selectedAccount = t.account
        selectedToAccount = t.toAccount
        selectedCurrencyCode = t.currencyCode
        if let rate = t.exchangeRateValue { exchangeRate = Decimal(rate) }
        selectedCategory = t.category
        selectedMember = t.member
        selectedMerchant = t.merchant
        selectedProject = t.project
        isReimbursable = t.isReimbursable
        if let d = t.lendingDirection { lendingDirection = d }
        if t.isSplitParent, let children = t.splitChildren {
            isSplit = true
            splitItems = children.map { child in
                SplitItemDraft(
                    amount: abs(child.amount),
                    category: child.category,
                    note: child.note ?? "",
                    member: child.member,
                    merchant: child.merchant,
                    project: child.project
                )
            }
        }
        if let paths = t.photoURLs, !paths.isEmpty {
            photoDataList = PhotoStorage.load(paths: paths)
        }
        syncAmountString()
    }

    private func applyTemplate(_ template: TransactionTemplate) {
        type = template.type
        amount = template.amount
        note = template.note ?? ""
        selectedAccount = template.account
        selectedToAccount = template.toAccount
        selectedCategory = template.category
        selectedMember = template.member
        selectedMerchant = template.merchant
        selectedProject = template.project
        syncAmountString()
    }

    private func save() {
        guard let ledger = appContainer.currentLedger else { return }
        do {
            if let existing = editing {
                try updateExisting(existing, ledger: ledger)
            } else if type == .transfer, let from = selectedAccount, let to = selectedToAccount {
                let dAmount: Decimal? = (from.effectiveCurrencyCode != to.effectiveCurrencyCode) ? destAmount : nil
                _ = try appContainer.transactionService.createTransfer(
                    from: from, to: to, amount: amount, destAmount: dAmount, date: date,
                    note: note.isEmpty ? nil : note, ledger: ledger, context: modelContext
                )
            } else if isSplit && !splitItems.isEmpty && type == .expense {
                let signedAmount: Decimal = -abs(amount)
                let parent = Transaction(
                    type: .expense, amount: signedAmount, note: note.isEmpty ? nil : note,
                    date: date, account: selectedAccount,
                    isSplitParent: true,
                    context: modelContext
                )
                parent.ledger = ledger
                if isReimbursable { parent.reimbursementStatus = ReimbursementStatus.pending }
                if !photoDataList.isEmpty {
                    parent.photoURLs = PhotoStorage.save(photoDataList, transactionId: parent.id)
                }

                applyCurrency(to: parent)
                createSplitChildren(parent: parent, ledger: ledger)
                try modelContext.save()
                NotificationCenter.default.post(name: .transactionDidChange, object: nil)
            } else {
                let signedAmount: Decimal = signingAmount()
                let transaction = Transaction(
                    type: type, amount: signedAmount, note: note.isEmpty ? nil : note,
                    date: date, account: selectedAccount, toAccount: selectedToAccount,
                    category: selectedCategory, member: selectedMember,
                    merchant: selectedMerchant, project: selectedProject,
                    context: modelContext
                )
                if type == .expense, isReimbursable {
                    transaction.reimbursementStatus = ReimbursementStatus.pending
                }
                if type == .lending {
                    transaction.lendingDirection = lendingDirection
                    if lendingDirection == LendingDirection.lendOut || lendingDirection == LendingDirection.borrowIn {
                        transaction.lendingStatus = LendingStatus.pending
                    }
                    if (lendingDirection == LendingDirection.collect || lendingDirection == LendingDirection.repay) && !selectedLendingIDs.isEmpty {
                        try linkSettledLendingTransactions(to: transaction.id)
                    }
                }
                if !photoDataList.isEmpty {
                    transaction.photoURLs = PhotoStorage.save(photoDataList, transactionId: transaction.id)
                }
                if type == .income, !selectedExpenseIDs.isEmpty {
                    try linkReimbursedExpenses(to: transaction.id)
                }
                applyCurrency(to: transaction)
                try appContainer.transactionService.createTransaction(transaction, ledger: ledger, context: modelContext)
            }
            if displayMode {
                isEditing = false
                loadDisplayData()
            } else {
                dismiss()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func createSplitChildren(parent: Transaction, ledger: Ledger) {
        for item in splitItems {
            let child = Transaction(
                type: .expense,
                amount: -abs(item.amount),
                note: item.note.isEmpty ? nil : item.note,
                date: date,
                account: selectedAccount,
                category: item.category,
                member: item.member,
                merchant: item.merchant,
                project: item.project,
                parentTransaction: parent,
                context: modelContext
            )
            child.ledger = ledger
            applyCurrency(to: child)
        }
    }

    private var splitTotal: Decimal {
        splitItems.reduce(Decimal.zero) { $0 + $1.amount }
    }


    private var ledgerCurrencyCode: String {
        appContainer.currentLedger?.defaultCurrencyCode ?? "CNY"
    }

    private var needsExchangeRate: Bool {
        if type == .transfer { return isCrossCurrencyTransfer }
        return selectedCurrencyCode != ledgerCurrencyCode
    }

    private var transferExchangeFrom: String {
        selectedAccount?.effectiveCurrencyCode ?? "CNY"
    }
    private var transferExchangeTo: String {
        selectedToAccount?.effectiveCurrencyCode ?? "CNY"
    }

    private var convertedAmountPreview: Decimal? {
        guard let rate = exchangeRate else { return nil }
        if type == .transfer {
            return abs(amount) * rate
        }
        let signed = signingAmount()
        return signed * rate
    }

    private func fetchExchangeRate() {
        guard let service = appContainer.exchangeRateService else { return }
        isFetchingRate = true
        let from: String
        let to: String
        if type == .transfer,
           let src = selectedAccount, let dst = selectedToAccount {
            from = src.effectiveCurrencyCode
            to = dst.effectiveCurrencyCode
        } else {
            from = selectedCurrencyCode
            to = ledgerCurrencyCode
        }
        Task {
            defer { isFetchingRate = false }
            if let rate = try? await service.fetchRate(from: from, to: to, context: modelContext) {
                exchangeRate = Decimal(string: "\(rate.rate)") ?? 0
            }
        }
    }

    private func applyCurrency(to t: Transaction) {
        appContainer.transactionService.applyCurrency(
            to: t, currencyCode: selectedCurrencyCode,
            exchangeRate: exchangeRate, ledgerCurrencyCode: ledgerCurrencyCode
        )
    }

    private func currencyName(_ code: String) -> String {
        switch code {
        case "CNY": return String(localized: "人民币")
        case "USD": return String(localized: "美元")
        case "EUR": return String(localized: "欧元")
        case "JPY": return String(localized: "日元")
        case "GBP": return String(localized: "英镑")
        case "HKD": return String(localized: "港币")
        case "AUD": return String(localized: "澳元")
        case "CAD": return String(localized: "加元")
        case "KRW": return String(localized: "韩元")
        case "TWD": return String(localized: "新台币")
        case "SGD": return String(localized: "新加坡元")
        case "CHF": return String(localized: "瑞士法郎")
        case "NZD": return String(localized: "新西兰元")
        case "THB": return String(localized: "泰铢")
        case "MYR": return String(localized: "马币")
        case "INR": return String(localized: "印度卢比")
        default: return code
        }
    }

    private func signingAmount() -> Decimal {
        signedAmount(amount: amount, type: type, direction: type == .lending ? lendingDirection : nil)
    }

    private func loadPendingLendingTransactions() {
        guard let ledger = appContainer.currentLedger, type == .lending else {
            pendingLendingTransactions = []
            return
        }
        let all = (try? appContainer.transactionService.fetchTransactions(for: ledger, context: modelContext, filters: nil)) ?? []
        switch lendingDirection {
        case .collect:
            guard let accountID = selectedAccount?.id else {
                pendingLendingTransactions = []
                return
            }
            pendingLendingTransactions = all.filter {
                $0.lendingDirection == LendingDirection.lendOut && $0.lendingStatus == LendingStatus.pending && $0.toAccount?.id == accountID
            }
        case .repay:
            guard let toAccountID = selectedToAccount?.id else {
                pendingLendingTransactions = []
                return
            }
            pendingLendingTransactions = all.filter {
                $0.lendingDirection == LendingDirection.borrowIn && $0.lendingStatus == LendingStatus.pending && $0.account?.id == toAccountID
            }
        default:
            pendingLendingTransactions = []
        }
        selectedLendingIDs = Set(pendingLendingTransactions.map(\.id))
    }

    private func toggleLending(_ id: UUID) {
        if selectedLendingIDs.contains(id) {
            selectedLendingIDs.remove(id)
        } else {
            selectedLendingIDs.insert(id)
        }
    }

    private var selectedLendingTotal: Decimal {
        pendingLendingTransactions
            .filter { selectedLendingIDs.contains($0.id) }
            .reduce(0) { $0 + max(0, abs($1.ledgerAmount) - $1.settledAmountInLedgerCurrency) }
    }

    private func displayLabelForLending(_ t: Transaction) -> String {
        if let note = t.note, !note.isEmpty { return note }
        if let cat = t.category { return NSLocalizedString(cat.name, comment: "") }
        return t.date.formatted(date: .numeric, time: .omitted)
    }

    private func updateExisting(_ original: Transaction, ledger: Ledger) throws {
        let id = original.id
        let fetch = NSFetchRequest<Transaction>(entityName: "Transaction")
        fetch.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        fetch.fetchLimit = 1
        guard let t = try? modelContext.fetch(fetch).first else {
            throw NSError(domain: "TransactionEdit", code: 1, userInfo: [NSLocalizedDescriptionKey: "Transaction not found"])
        }

        // Delete old split children if previously a split parent
        if original.isSplitParent, let oldChildren = original.splitChildren {
            for child in oldChildren {
                modelContext.delete(child)
            }
        }

        t.type = type
        t.amount = signingAmount()
        t.note = note.isEmpty ? nil : note
        t.date = date
        t.account = selectedAccount
        t.toAccount = selectedToAccount
        t.category = selectedCategory
        t.member = selectedMember
        t.merchant = selectedMerchant
        t.project = selectedProject

        applyCurrency(to: t)

        if isSplit && type == .expense {
            t.isSplitParent = true
            createSplitChildren(parent: t, ledger: ledger)
        } else {
            t.isSplitParent = false
        }

        if t.type == .expense {
            t.reimbursementStatus = isReimbursable ? ReimbursementStatus.pending : ReimbursementStatus.none
        }
        if t.type == .lending {
            t.lendingDirection = lendingDirection
            if lendingDirection == LendingDirection.lendOut || lendingDirection == LendingDirection.borrowIn {
                // Preserve settled status — don't reset an already-settled debt back to pending
                if original.lendingStatus != .settled {
                    t.lendingStatus = .pending
                }
            }
            if lendingDirection == LendingDirection.collect || lendingDirection == LendingDirection.repay {
                // Unlink previously settled transactions before re-linking with updated selection
                let unlinkReq = NSFetchRequest<Transaction>(entityName: "Transaction")
                unlinkReq.predicate = NSPredicate(format: "settledByLendingTransactionId == %@", id as CVarArg)
                if let previouslySettled = try? modelContext.fetch(unlinkReq) {
                    for item in previouslySettled {
                        item.settledByLendingTransactionId = nil
                        item.settledAmount = nil
                        item.lendingStatus = .pending
                    }
                }
                if !selectedLendingIDs.isEmpty {
                    try linkSettledLendingTransactions(to: t.id)
                }
            }
        }
        // Unlink previously reimbursed expenses before re-linking
        if t.type == .income {
            let reimbursedReq = NSFetchRequest<Transaction>(entityName: "Transaction")
            reimbursedReq.predicate = NSPredicate(format: "reimbursedById == %@", t.id as CVarArg)
            if let reimbursed = try? modelContext.fetch(reimbursedReq) {
                for exp in reimbursed { exp.reimbursementStatus = .pending; exp.reimbursedById = nil }
            }
            if !selectedExpenseIDs.isEmpty { try linkReimbursedExpenses(to: t.id) }
        }
        if let oldPaths = t.photoURLs, !oldPaths.isEmpty {
            PhotoStorage.delete(paths: oldPaths)
        }
        t.photoURLs = photoDataList.isEmpty ? nil : PhotoStorage.save(photoDataList, transactionId: t.id)
        t.modifiedAt = Date()

        // Update paired transfer record (transfers create two linked records)
        if t.type == .transfer, let gid = t.transferGroupId {
            let pairedReq = NSFetchRequest<Transaction>(entityName: "Transaction")
            pairedReq.predicate = NSPredicate(format: "transferGroupId == %@ AND id != %@", gid as CVarArg, t.id as CVarArg)
            if let paired = try? modelContext.fetch(pairedReq).first {
                paired.amount = abs(t.amount)  // opposite sign: main is negative, paired is positive
                paired.date = date
                paired.note = note.isEmpty ? nil : note
                paired.account = selectedToAccount
                paired.toAccount = selectedAccount
                if let oldPaths = paired.photoURLs, !oldPaths.isEmpty {
                    PhotoStorage.delete(paths: oldPaths)
                }
                paired.photoURLs = photoDataList.isEmpty ? nil : PhotoStorage.save(photoDataList, transactionId: paired.id)
                paired.modifiedAt = Date()
                if let destCurrency = selectedToAccount?.effectiveCurrencyCode {
                    paired.currencyCode = destCurrency
                }
            }
        }

        try modelContext.save()
        NotificationCenter.default.post(name: .transactionDidChange, object: nil)
    }

    private func toggleExpense(_ id: UUID) {
        if selectedExpenseIDs.contains(id) {
            selectedExpenseIDs.remove(id)
        } else {
            selectedExpenseIDs.insert(id)
        }
    }

    private var selectedReimbursementTotal: Decimal {
        pendingExpenses
            .filter { selectedExpenseIDs.contains($0.id) }
            .reduce(0) { $0 + abs($1.ledgerAmount) }
    }

    private func loadPendingExpenses() {
        guard let ledger = appContainer.currentLedger, type == .income else {
            pendingExpenses = []
            return
        }
        let all = (try? appContainer.transactionService.fetchTransactions(for: ledger, context: modelContext, filters: nil)) ?? []
        pendingExpenses = all.filter { $0.type == TransactionType.expense && $0.isReimbursable && $0.reimbursementStatus == ReimbursementStatus.pending }
    }

    private func linkReimbursedExpenses(to incomeId: UUID) throws {
        for expenseID in selectedExpenseIDs {
            let fetch = NSFetchRequest<Transaction>(entityName: "Transaction")
            fetch.predicate = NSPredicate(format: "id == %@", expenseID as CVarArg)
            fetch.fetchLimit = 1
            guard let expense = try? modelContext.fetch(fetch).first else { continue }
            expense.reimbursementStatus = ReimbursementStatus.reimbursed
            expense.reimbursedById = incomeId
        }
        try modelContext.save()
    }

    private func linkSettledLendingTransactions(to settlementId: UUID) throws {
        let settlementAmount = abs(signingAmount())
        var remaining = settlementAmount
        let sortedIDs = pendingLendingTransactions
            .filter { selectedLendingIDs.contains($0.id) }
            .sorted { $0.date < $1.date }
            .map { $0.id }

        for lendingID in sortedIDs {
            guard remaining > 0 else { break }
            let fetch = NSFetchRequest<Transaction>(entityName: "Transaction")
            fetch.predicate = NSPredicate(format: "id == %@", lendingID as CVarArg)
            fetch.fetchLimit = 1
            guard let item = try? modelContext.fetch(fetch).first else { continue }
            let debtAmount = abs(item.amount)
            let alreadyPaid = item.settledAmount ?? 0
            let stillOwed = debtAmount - alreadyPaid
            if remaining >= stillOwed {
                item.settledAmount = debtAmount
                item.lendingStatus = LendingStatus.settled
                remaining -= stillOwed
            } else {
                item.settledAmount = alreadyPaid + remaining
                remaining = 0
            }
            if item.settledByLendingTransactionId == nil {
                item.settledByLendingTransactionId = settlementId
            }
        }
        try modelContext.save()
    }

    private func delete() {
        guard let t = editing else { return }
        if let paths = t.photoURLs, !paths.isEmpty {
            PhotoStorage.delete(paths: paths)
        }
        do {
            try appContainer.transactionService.deleteTransaction(t, context: modelContext)
        } catch {
            errorMessage = String(localized: "删除失败: \(error.localizedDescription)")
            return
        }
        dismiss()
    }

    // MARK: - Display Mode Actions

    private func enterEditMode() {
        withAnimation(.easeInOut(duration: 0.2)) { isEditing = true }
    }

    private func cancelEditing() {
        prefillEditing()
        withAnimation(.easeInOut(duration: 0.2)) { isEditing = false }
    }

    private var canRefund: Bool {
        guard let t = editing else { return false }
        return (t.type == .expense || t.type == .income) && t.refundGroupId == nil
    }

    // MARK: - Display-Only Data Loading

    private func loadDisplayData() {
        guard displayMode, editing != nil else { return }
        loadLinkedRefunds()
        loadSettledExpenses()
        loadSettledLendingTransactions()
    }

    private func loadLinkedRefunds() {
        guard let t = editing else { return }
        let tid = t.id
        let fetch = NSFetchRequest<Transaction>(entityName: "Transaction")
        fetch.predicate = NSPredicate(format: "refundGroupId == %@", tid as CVarArg)
        linkedRefunds = (try? modelContext.fetch(fetch)) ?? []
    }

    private func loadSettledExpenses() {
        guard let t = editing else { return }
        let tid = t.id
        let fetch = NSFetchRequest<Transaction>(entityName: "Transaction")
        fetch.predicate = NSPredicate(format: "reimbursedById == %@", tid as CVarArg)
        settledExpenses = (try? modelContext.fetch(fetch)) ?? []
    }

    private func loadSettledLendingTransactions() {
        guard let t = editing else { return }
        let tid = t.id
        let fetch = NSFetchRequest<Transaction>(entityName: "Transaction")
        fetch.predicate = NSPredicate(format: "settledByLendingTransactionId == %@", tid as CVarArg)
        settledLendingTransactions = (try? modelContext.fetch(fetch)) ?? []
    }
}

// MARK: - FlowLayout

private struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        layout(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(proposal: proposal, subviews: subviews)
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x, y: bounds.minY + result.positions[index].y), proposal: proposal)
        }
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        var positions: [CGPoint] = []

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += lineHeight + spacing
                lineHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }

        return (CGSize(width: maxWidth, height: y + lineHeight), positions)
    }
}
