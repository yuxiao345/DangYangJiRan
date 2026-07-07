import SwiftUI
@preconcurrency import CoreData
import PhotosUI

struct SplitItemDraft: Identifiable {
    var id = UUID(); var amount: Decimal = 0; var category: Category?
    var note: String = ""; var member: Member?; var merchant: Merchant?; var project: Project?
}

struct MacAddTransactionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var modelContext
    @Environment(AppContainer.self) private var appContainer

    let editing: Transaction?
    let displayMode: Bool
    let refundingOriginal: Transaction?

    @State private var isEditing: Bool
    @State private var deleteTarget: Transaction?
    @State private var type: TransactionType
    @State private var amount: Decimal
    @State private var amountString: String
    @State private var note: String
    @State private var date: Date
    @State private var selectedAccount: Account?
    @State private var selectedToAccount: Account?
    @State private var selectedCategory: Category?
    @State private var selectedMember: Member?
    @State private var selectedMerchant: Merchant?
    @State private var selectedProject: Project?
    @State private var accounts: [Account]
    @State private var categories: [Category]
    @State private var members: [Member]
    @State private var merchants: [Merchant]
    @State private var projects: [Project]
    @State private var errorMessage: String?
    @State private var lendingDirection: LendingDirection
    @State private var pendingLendingTransactions: [Transaction]
    @State private var selectedLendingIDs: Set<UUID>
    @State private var templates: [TransactionTemplate]
    @State private var showTemplates: Bool
    @State private var isSplit: Bool
    @State private var splitItems: [SplitItemDraft]
    @State private var isReimbursable: Bool
    @State private var pendingExpenses: [Transaction]
    @State private var selectedExpenseIDs: Set<UUID>
    @State private var selectedCurrencyCode: String
    @State private var exchangeRate: Decimal?
    @State private var convertedAmount: Decimal?
    @State private var selectedPhotos: [PhotosPickerItem]
    @State private var photoDataList: [Data]
    @State private var showRefundSheet: Bool
    @State private var showNumpad: Bool = false
    @State private var numpadText: String = ""
    @State private var destAmount: Decimal = 0
    @State private var destAmountString: String = "0.00"
    @State private var showDestNumpad: Bool = false
    @State private var destNumpadText: String = ""

    init(editing: Transaction? = nil, displayMode: Bool = false, refunding: Transaction? = nil) {
        let initEditing: Transaction?
        let initDisplayMode: Bool
        let initType: TransactionType
        let initAmount: Decimal
        let initAmountString: String
        let initNote: String
        let initDate: Date
        let initAccount: Account?
        let initToAccount: Account?
        let initCategory: Category?
        let initMember: Member?
        let initMerchant: Merchant?
        let initProject: Project?
        let initLendingDirection: LendingDirection
        let initCurrencyCode: String
        let initIsSplit: Bool
        let initSplitItems: [SplitItemDraft]
        let initIsReimbursable: Bool
        let initPhotoDataList: [Data]

        if let t = refunding {
            initEditing = nil; initDisplayMode = false
            initType = t.type; initAmount = abs(t.amount)
            initAmountString = String(describing: abs(t.amount))
            initNote = "退款: \(t.note ?? "")"; initDate = Date()
            initAccount = t.account; initToAccount = nil
            initCategory = t.category; initMember = nil
            initMerchant = nil; initProject = nil
            initLendingDirection = .lendOut
            initCurrencyCode = t.currencyCode ?? "CNY"
            initIsSplit = false; initSplitItems = []
            initIsReimbursable = false; initPhotoDataList = []
        } else if let t = editing {
            initEditing = t; initDisplayMode = displayMode
            initType = t.type; initAmount = abs(t.amount)
            initAmountString = String(describing: abs(t.amount))
            initNote = t.note ?? ""; initDate = t.date
            initAccount = t.account; initToAccount = t.toAccount
            initCategory = t.category; initMember = t.member
            initMerchant = t.merchant; initProject = t.project
            initLendingDirection = t.lendingDirection ?? .lendOut
            initCurrencyCode = t.currencyCode ?? t.account?.currencyCode ?? "CNY"
            initIsSplit = t.isSplitParent
            if t.isSplitParent, let children = t.splitChildren {
                initSplitItems = Array(children).map { child in
                    SplitItemDraft(amount: abs(child.amount), category: child.category,
                                   note: child.note ?? "", member: child.member,
                                   merchant: child.merchant, project: child.project)
                }
            } else { initSplitItems = [] }
            initIsReimbursable = t.isReimbursable
            if let paths = t.photoURLs, !paths.isEmpty {
                initPhotoDataList = PhotoStorage.load(paths: paths)
            } else { initPhotoDataList = [] }
        } else {
            initEditing = nil; initDisplayMode = false
            initType = .expense; initAmount = 0
            initAmountString = ""; initNote = ""; initDate = Date()
            initAccount = nil; initToAccount = nil
            initCategory = nil; initMember = nil
            initMerchant = nil; initProject = nil
            initLendingDirection = .lendOut
            initCurrencyCode = "CNY"
            initIsSplit = false; initSplitItems = []
            initIsReimbursable = false; initPhotoDataList = []
        }

        self.editing = initEditing
        self.displayMode = initDisplayMode
        self.refundingOriginal = refunding
        _type = State(initialValue: initType)
        _amount = State(initialValue: initAmount)
        _amountString = State(initialValue: initAmountString)
        _note = State(initialValue: initNote)
        _date = State(initialValue: initDate)
        _selectedAccount = State(initialValue: initAccount)
        _selectedToAccount = State(initialValue: initToAccount)
        _selectedCategory = State(initialValue: initCategory)
        _selectedMember = State(initialValue: initMember)
        _selectedMerchant = State(initialValue: initMerchant)
        _selectedProject = State(initialValue: initProject)
        _lendingDirection = State(initialValue: initLendingDirection)
        _isEditing = State(initialValue: false)
        _accounts = State(initialValue: [])
        _categories = State(initialValue: [])
        _members = State(initialValue: [])
        _merchants = State(initialValue: [])
        _projects = State(initialValue: [])
        _pendingLendingTransactions = State(initialValue: [])
        _selectedLendingIDs = State(initialValue: [])
        _templates = State(initialValue: [])
        _showTemplates = State(initialValue: false)
        _isSplit = State(initialValue: initIsSplit)
        _splitItems = State(initialValue: initSplitItems)
        _isReimbursable = State(initialValue: initIsReimbursable)
        _pendingExpenses = State(initialValue: [])
        _selectedExpenseIDs = State(initialValue: [])
        _selectedCurrencyCode = State(initialValue: initCurrencyCode)
        _selectedPhotos = State(initialValue: [])
        _photoDataList = State(initialValue: initPhotoDataList)
        _showRefundSheet = State(initialValue: false)
    }

    private var isViewing: Bool { displayMode && !isEditing }
    private var isCrossCurrencyTransfer: Bool {
        guard type == .transfer,
              let src = selectedAccount, let dst = selectedToAccount else { return false }
        return src.effectiveCurrencyCode != dst.effectiveCurrencyCode
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            typeSelector
            Divider()
            contentScroll
            bottomBar
        }
        .macSheetFrame()
        .toolbar { toolbarContent }
        .task { loadData() }
        .onChange(of: type) { _, _ in loadCategories(); loadPendingReimbursement(); destAmount = 0; destAmountString = "0.00" }
        .onChange(of: lendingDirection) { _, _ in loadPendingLendingTx() }
        .onChange(of: selectedAccount) { _, _ in
            loadPendingLendingTx()
            if editing == nil {
                selectedCurrencyCode = selectedAccount?.currencyCode ?? ledgerCurrencyCode
            }
            exchangeRate = nil
            convertedAmount = nil
            if activeCurrency != ledgerCurrencyCode { fetchExchangeRate() }
        }
        .onChange(of: selectedToAccount) { _, _ in loadPendingLendingTx(); destAmount = 0; destAmountString = "0.00" }
        .onChange(of: selectedPhotos) { _, _ in loadPhotoData() }
        .modifier(DeleteConfirmationModifier(deleteTarget: $deleteTarget, onDelete: { deleteTx($0) }))
        .sheet(isPresented: $showRefundSheet) {
            if let t = editing { MacAddTransactionSheet(refunding: t) }
        }
        .alert(errorMessage ?? "保存失败", isPresented: .constant(errorMessage != nil)) {
            Button("好") { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    private var contentScroll: some View {
        let showTemplateDivider = editing == nil && !templates.isEmpty

        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // ── Layer 1: Templates (new transactions only) ──
                templateRow

                // ── Layer 2: Amount (core input) ──
                if showTemplateDivider {
                    Divider().padding(.horizontal, 24)
                }
                amountSection

                // ── Layer 3: Detail fields ──
                Divider().padding(.horizontal, 24)
                detailRows

                // ── Layer 4: Metadata ──
                Divider().padding(.horizontal, 24)
                dateNoteRow

                if isViewing, let t = editing {
                    displayOnlySections(for: t)
                }
            }
        }
        .disabled(isViewing)
        .designScreen()
    }

    // MARK: - Display-Only Sections

    @ViewBuilder
    private func displayOnlySections(for t: Transaction) -> some View {
        // Split children
        if t.isSplitParent, let children = t.splitChildren, !children.isEmpty {
            Divider().padding(.horizontal, 24)
            VStack(alignment: .leading, spacing: 8) {
                Text("拆分明细").font(.designLabel).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ForEach(Array(children), id: \.objectID) { child in
                    HStack {
                        if let cat = child.category {
                            Image(systemName: cat.iconName)
                                .foregroundStyle(Color(hex: cat.colorHex ?? "#999999"))
                                .frame(width: 20)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(child.category?.name ?? "未分类").font(.designBodyMedium)
                            if let m = child.member { Text(m.name).font(.designBodyCaption).foregroundStyle(.secondary) }
                        }
                        Spacer()
                        CurrencyText(amount: abs(child.amount), currencyCode: t.currencyCode, size: 13, foregroundColor: .secondary)
                    }
                }
            }
            .padding(.horizontal, 24).padding(.vertical, 10)
        }

        // Refund linking
        if t.refundGroupId != nil {
            Divider().padding(.horizontal, 24)
            HStack {
                Image(systemName: "arrow.uturn.backward").foregroundStyle(.orange)
                Text("已关联退款").font(.designBodyMedium).foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 24).padding(.vertical, 10)
        }

        // Reimbursement status
        if t.isReimbursable {
            Divider().padding(.horizontal, 24)
            HStack {
                Image(systemName: t.reimbursementStatus == .reimbursed ? "checkmark.shield.fill" : "hourglass")
                    .foregroundStyle(t.reimbursementStatus == .reimbursed ? .green : .orange)
                Text(t.reimbursementStatus == .reimbursed ? "已报销" : "待报销").font(.designBodyMedium)
                Spacer()
            }
            .padding(.horizontal, 24).padding(.vertical, 10)
        }

        // Lending status
        if let dir = t.lendingDirection {
            Divider().padding(.horizontal, 24)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "arrow.left.arrow.right").foregroundStyle(.orange)
                    Text("借贷: \(dir.displayName)").font(.designBodyMedium)
                    Spacer()
                    let status = t.lendingStatus
                    if status != .none {
                        Text(status.displayName).font(.designBodyCaption)
                            .foregroundStyle(status == .settled ? .green : .orange)
                    }
                }
            }
            .padding(.horizontal, 24).padding(.vertical, 10)
        }

        // Photos
        if !photoDataList.isEmpty {
            Divider().padding(.horizontal, 24)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(photoDataList.enumerated()), id: \.offset) { _, data in
                        if let nsImg = NSImage(data: data) {
                            Image(nsImage: nsImg).resizable().scaledToFit()
                                .frame(height: 120).clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
                .padding(.horizontal, 24)
            }
            .padding(.vertical, 10)
        }
    }

    @ViewBuilder
    private var bottomBar: some View {
        if !isViewing && editing == nil {
            Divider()
            saveButton.padding(.horizontal, 24).padding(.vertical, 12)
        }
    }

    // MARK: - Type Selector

    private var typeSelector: some View {
        HStack(spacing: 20) {
            ForEach([TransactionType.expense, .income, .transfer, .lending], id: \.self) { t in
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { type = t }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: t.systemIcon)
                            .font(.system(size: 18, weight: type == t ? .bold : .regular))
                        Text(t.displayName)
                            .font(.designBodyCaption.weight(type == t ? .semibold : .regular))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .foregroundStyle(type == t ? Color.designPrimaryContainer : Color.designOnSurfaceVariant)
                    .background(type == t ? Color.designPrimaryContainer.opacity(0.1) : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .disabled(editing != nil)
            }
        }
        .padding(.horizontal, 24).padding(.vertical, 10)
    }

    // MARK: - Amount

    private var amountSection: some View {
        let currencies = ["CNY", "USD", "EUR", "JPY", "GBP", "HKD", "AUD", "CAD", "KRW", "TWD", "SGD", "CHF", "NZD", "THB", "MYR", "INR"]
        return VStack(spacing: 4) {
            // Amount display
            Button {
                numpadText = amount != 0 ? amountString : ""
                withAnimation(.easeInOut(duration: 0.2)) { showNumpad.toggle() }
            } label: {
                HStack(spacing: 4) {
                    Text(CurrencyFormatter.currencySymbol(for: selectedCurrencyCode.isEmpty ? ledgerCurrencyCode : selectedCurrencyCode))
                        .font(.custom("JetBrainsMono-Medium", fixedSize: 28))
                        .foregroundStyle(Color.designPrimaryFixedDim)
                    if showNumpad {
                        Text(numpadText.isEmpty ? "0.00" : numpadText)
                            .font(.custom("JetBrainsMono-Medium", fixedSize: 36))
                            .foregroundStyle(.secondary)
                    } else {
                        Text(amount == 0 ? "0.00" : CurrencyFormatter.formatDecimal(amount: amount, fractionDigits: 2))
                            .font(.custom("JetBrainsMono-Medium", fixedSize: 36))
                            .foregroundStyle(amount == 0 ? .secondary : .primary)
                    }
                }
                .padding(.vertical, 8).padding(.horizontal, 12)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.designSurfaceContainer.opacity(showNumpad ? 0.3 : 0)))
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)

            // Currency picker - below amount
            Picker("", selection: $selectedCurrencyCode) {
                ForEach(currencies, id: \.self) { code in
                    Text("\(code) \(currencyName(code))").tag(code)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .disabled(selectedAccount != nil)
            .onChange(of: selectedCurrencyCode) { _, _ in fetchExchangeRate() }

            // Numpad
            if showNumpad {
                macNumpadPopover(text: $numpadText, amount: $amount, amountString: $amountString, show: $showNumpad)
            }

            if let rate = exchangeRate, activeCurrency != ledgerCurrencyCode {
                HStack(spacing: 8) {
                    Text("1 \(ledgerCurrencyCode) = \(NSDecimalNumber(decimal: rate).stringValue) \(activeCurrency)")
                        .font(.designBodyCaption).foregroundStyle(.secondary)
                    if let converted = convertedAmount {
                        Text("≈ \(CurrencyFormatter.currencySymbol(for: ledgerCurrencyCode))\(CurrencyFormatter.formatDecimal(amount: converted, fractionDigits: 2))")
                            .font(.designBodyCaption).foregroundStyle(Color.designPrimaryFixedDim)
                    }
                }
            }

            // Toggles (expense only)
            if type == .expense {
                toggleSection
                if isSplit { splitDetailSection }
            }

            // Cross-currency transfer: dest amount + exchange rate
            if isCrossCurrencyTransfer {
                VStack(spacing: 4) {
                    if amount != 0, destAmount != 0 {
                        let srcCode = selectedAccount?.currencyCode ?? "CNY"
                        let dstCode = selectedToAccount?.currencyCode ?? "CNY"
                        let rate = destAmount / amount
                        HStack(spacing: 8) {
                            Text("1 \(srcCode) ≈ \(NSDecimalNumber(decimal: rate).stringValue) \(dstCode)")
                                .font(.designBodyCaption).foregroundStyle(.secondary)
                        }
                    }

                    Button {
                        destNumpadText = destAmount != 0 ? destAmountString : ""
                        withAnimation(.easeInOut(duration: 0.2)) { showDestNumpad.toggle() }
                    } label: {
                        HStack(spacing: 4) {
                            Text(CurrencyFormatter.currencySymbol(for: selectedToAccount?.currencyCode ?? "CNY"))
                                .font(.custom("JetBrainsMono-Medium", fixedSize: 28))
                                .foregroundStyle(Color.designPrimaryFixedDim)
                            if showDestNumpad {
                                Text(destNumpadText.isEmpty ? "0.00" : destNumpadText)
                                    .font(.custom("JetBrainsMono-Medium", fixedSize: 36))
                                    .foregroundStyle(.secondary)
                            } else {
                                Text(destAmount == 0 ? "0.00" : CurrencyFormatter.formatDecimal(amount: destAmount, fractionDigits: 2))
                                    .font(.custom("JetBrainsMono-Medium", fixedSize: 36))
                                    .foregroundStyle(destAmount == 0 ? .secondary : .primary)
                            }
                        }
                        .padding(.vertical, 8).padding(.horizontal, 12)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.designSurfaceContainer.opacity(showDestNumpad ? 0.3 : 0)))
                    }
                    .buttonStyle(.plain)

                    if showDestNumpad {
                        macNumpadPopover(text: $destNumpadText, amount: $destAmount, amountString: $destAmountString, show: $showDestNumpad)
                    }
                }
            }
        }
        .padding(.horizontal, 24).padding(.vertical, 16)
    }

    // MARK: - Row groups (extracted to keep body type-check fast)

    @ViewBuilder
    private var templateRow: some View {
        if editing == nil && !templates.isEmpty {
            templateSection
        }
    }

    @ViewBuilder
    private var lendingRow: some View {
        if type == .lending {
            lendingSection
        }
    }

    @ViewBuilder
    private var accountRows: some View {
        Group {
            formPicker(label: (type == .transfer || type == .lending) ? "转出账户" : "账户",
                       selection: $selectedAccount, items: accounts,
                       icon: { $0.iconName ?? "creditcard" }, name: { $0.name },
                       color: { Color(hex: $0.colorHex ?? "#007AFF") }, recentKey: "recent_account")
            if type == .transfer || type == .lending {
                formPicker(label: "转入账户", selection: $selectedToAccount,
                           items: accounts.filter { $0.id != selectedAccount?.id },
                           icon: { $0.iconName ?? "creditcard" }, name: { $0.name },
                           color: { Color(hex: $0.colorHex ?? "#007AFF") }, recentKey: "recent_toaccount")
            }
        }
    }

    @ViewBuilder
    private var categoryAndExtrasRows: some View {
        Group {
            if type != .transfer && type != .lending {
                formPicker(label: "分类", selection: $selectedCategory,
                           items: categories, icon: { $0.iconName }, name: { $0.name },
                           color: { Color(hex: $0.colorHex) },
                           indent: { var d = 0; var p = $0.parent; while p != nil { d += 1; p = p?.parent }; return d },
                           parentId: { $0.parent?.id },
                           recentKey: "recent_category")
                if let cat = selectedCategory, (cat.children?.count ?? 0) > 0 {
                    Text("已选择上级分类「\(cat.name)」，可展开选择更具体的子分类")
                        .font(.caption).foregroundStyle(.orange)
                        .padding(.horizontal, 24)
                }
                formPicker(label: "成员", selection: $selectedMember,
                           items: members, icon: { $0.avatar }, name: { $0.name }, recentKey: "recent_member")
                formPicker(label: "商家", selection: $selectedMerchant,
                           items: merchants, icon: { _ in "bag" }, name: { $0.name }, recentKey: "recent_merchant")
                formPicker(label: "项目", selection: $selectedProject,
                           items: projects, icon: { _ in "folder" }, name: { $0.name }, recentKey: "recent_project")
            }
        }
    }

    @ViewBuilder
    private var toggleAndSplitRows: some View {
        Group {
            if type == .expense {
                toggleSection
                if isSplit { splitDetailSection }
            }
        }
    }

    @ViewBuilder
    private var reimbursementAndLendingRows: some View {
        Group {
            if type == .income && !pendingExpenses.isEmpty {
                reimbursementSection
            }
            if type == .lending && (lendingDirection == .collect || lendingDirection == .repay) && !pendingLendingTransactions.isEmpty {
                lendingSettleSection
            }
        }
    }

    @ViewBuilder
    private var detailRows: some View {
        lendingRow
        accountRows
        categoryAndExtrasRows
        reimbursementAndLendingRows
    }

    @ViewBuilder
    private var dateNoteRow: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Text("日期").font(.designBodyMedium).foregroundStyle(.secondary)
                    .frame(width: 60, alignment: .trailing)
                DatePicker("", selection: $date, displayedComponents: [.date, .hourAndMinute]).labelsHidden()
                Spacer()
                if editing == nil || isEditing { photoSection }
            }
            HStack(spacing: 12) {
                Text("备注").font(.designBodyMedium).foregroundStyle(.secondary)
                    .frame(width: 60, alignment: .trailing)
                TextField("添加备注", text: $note).textFieldStyle(.roundedBorder)
                Spacer()
            }
        }
        .padding(.horizontal, 24).padding(.vertical, 12)
    }

    // MARK: - Form Picker (Mac-native Menu style, with optional recent-item tracking)

    private func formPicker<T: Identifiable & Hashable>(
        label: String, selection: Binding<T?>, items: [T],
        icon: @escaping (T) -> String, name: @escaping (T) -> String,
        color: @escaping (T) -> Color = { _ in .secondary }, indent: ((T) -> Int)? = nil,
        parentId: ((T) -> T.ID?)? = nil, recentKey: String? = nil
    ) -> some View {
        return HStack(spacing: 12) {
            Text(label)
                .font(.designBodyMedium)
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .trailing)
            MacPopupPicker(
                selection: selection,
                items: items,
                icon: icon,
                name: name,
                color: color,
                indent: indent,
                parentId: parentId,
                recentKey: recentKey,
                onSelect: { item in
                    if let key = recentKey {
                        recordRecent(item, key: key)
                    }
                }
            )
            .frame(width: 250)
        }
        .padding(.horizontal, 24).padding(.vertical, 8)
    }

    private func recordRecent<T: Identifiable>(_ item: T, key: String) {
        var ids = UserDefaults.standard.stringArray(forKey: key) ?? []
        let idStr = String(describing: item.id)
        ids.removeAll { $0 == idStr }
        ids.insert(idStr, at: 0)
        UserDefaults.standard.set(Array(ids.prefix(4)), forKey: key)
    }

    // MARK: - Template Section

    private let templateMaxVisible = 3

    private var templateSection: some View {
        let visible = Array(templates.prefix(templateMaxVisible))
        let overflow = templates.count > templateMaxVisible

        return HStack(spacing: 12) {
            Text("模板").font(.designBodyMedium).foregroundStyle(.secondary)
                .frame(width: 60, alignment: .trailing)
            HStack(spacing: 8) {
                ForEach(visible) { tpl in
                    Button { applyTemplate(tpl) } label: {
                        Text(tpl.name).font(.designBodyCaption)
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(Capsule().fill(Color.designSurfaceContainer.opacity(0.5)))
                            .overlay(Capsule().stroke(Color.designOutlineVariant, lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                }
                if overflow {
                    Menu {
                        ForEach(Array(templates.dropFirst(templateMaxVisible))) { tpl in
                            Button { applyTemplate(tpl) } label: {
                                if let cat = tpl.category {
                                    Label(tpl.name, systemImage: cat.iconName)
                                } else {
                                    Text(tpl.name)
                                }
                            }
                        }
                    } label: {
                        Text("+\(templates.count - templateMaxVisible)")
                            .font(.designBodyCaption)
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(Capsule().fill(Color.designAccentGreen.opacity(0.15)))
                            .overlay(Capsule().stroke(Color.designAccentGreen, lineWidth: 0.5))
                            .foregroundStyle(Color.designAccentGreen)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 24).padding(.vertical, 8)
    }

    // MARK: - Toggle Section

    private var toggleSection: some View {
        HStack(spacing: 24) {
            Toggle("拆分记账", isOn: $isSplit)
            Toggle("可报销", isOn: $isReimbursable)
        }
        .font(.designBodySmall)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }

    // MARK: - Split Detail

    @State private var editingSplitIndex: Int?

    private var splitDetailSection: some View {
        VStack(spacing: 8) {
            HStack {
                Text("拆分明细").font(.designLabel).foregroundStyle(.secondary)
                Spacer()
                Text("合计: \(CurrencyFormatter.formatDecimal(amount: splitTotal, fractionDigits: 2))")
                    .font(.designBodySmall)
                    .foregroundStyle(splitTotal == amount ? Color.designPrimaryFixedDim : .red)
                Button { splitItems.append(SplitItemDraft(amount: amount - splitTotal)) } label: {
                    Image(systemName: "plus.circle.fill").foregroundStyle(Color.designAccentGreen)
                }.buttonStyle(.plain)
            }
            ForEach(Array(splitItems.enumerated()), id: \.offset) { i, item in
                VStack(spacing: 4) {
                    HStack(spacing: 8) {
                        Button { splitItems.remove(at: i) } label: {
                            Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                        }.buttonStyle(.plain)
                        // Numpad-triggered amount button
                        Button {
                            if editingSplitIndex == i { editingSplitIndex = nil }
                            else { editingSplitIndex = i }
                        } label: {
                            Text(item.amount == 0 ? "金额" : CurrencyFormatter.formatDecimal(amount: item.amount, fractionDigits: 2))
                                .font(.designBodySmall.weight(.medium))
                                .foregroundStyle(item.amount == 0 ? .secondary : Color.designOnSurface)
                                .frame(width: 80)
                        }.buttonStyle(.plain)
                        Picker("分类", selection: Binding(get: { item.category }, set: { splitItems[i].category = $0 })) {
                            Text("无").tag(nil as Category?)
                            ForEach(categories.filter { ($0.children?.count ?? 0) == 0 }) { c in
                                Text(c.name).tag(c as Category?)
                            }
                        }.frame(width: 100)
                        Picker("成员", selection: Binding(get: { item.member }, set: { splitItems[i].member = $0 })) {
                            Text("无").tag(nil as Member?)
                            ForEach(members) { m in Text(m.name).tag(m as Member?) }
                        }.frame(width: 80)
                        Picker("商家", selection: Binding(get: { item.merchant }, set: { splitItems[i].merchant = $0 })) {
                            Text("无").tag(nil as Merchant?)
                            ForEach(merchants) { m in Text(m.name).tag(m as Merchant?) }
                        }.frame(width: 80)
                        Picker("项目", selection: Binding(get: { item.project }, set: { splitItems[i].project = $0 })) {
                            Text("无").tag(nil as Project?)
                            ForEach(projects) { p in Text(p.name).tag(p as Project?) }
                        }.frame(width: 80)
                    }
                    // Note field + numpad inline
                    HStack(spacing: 8) {
                        Image(systemName: "text.justify").foregroundStyle(.secondary).font(.system(size: 10))
                        TextField("备注", text: Binding(get: { item.note }, set: { splitItems[i].note = $0 }))
                            .textFieldStyle(.roundedBorder).font(.designBodySmall)
                    }
                    .padding(.leading, 28)

                    if editingSplitIndex == i {
                        macNumpadPopover(
                            text: Binding(
                                get: { item.amount == 0 ? "" : String(describing: item.amount) },
                                set: {
                                    if let d = Decimal(string: $0) { splitItems[i].amount = d }
                                }
                            ),
                            amount: Binding(get: { item.amount }, set: { splitItems[i].amount = $0 }),
                            amountString: Binding(
                                get: { item.amount == 0 ? "" : CurrencyFormatter.formatDecimal(amount: item.amount, fractionDigits: 2) },
                                set: { _ in }
                            ),
                            show: Binding(get: { editingSplitIndex == i }, set: { if !$0 { editingSplitIndex = nil } })
                        )
                    }
                }
            }
        }
        .padding(.horizontal, 24).padding(.vertical, 8)
    }

    private var splitTotal: Decimal { splitItems.reduce(0) { $0 + $1.amount } }

    // MARK: - Reimbursement

    private var reimbursementSection: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("待报销")
                .font(.designBodyMedium)
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .trailing)
            VStack(spacing: 8) {
                ForEach(pendingExpenses) { exp in
                    Button {
                        if selectedExpenseIDs.contains(exp.id) { selectedExpenseIDs.remove(exp.id) }
                        else { selectedExpenseIDs.insert(exp.id) }
                    } label: {
                        HStack {
                            Image(systemName: selectedExpenseIDs.contains(exp.id) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selectedExpenseIDs.contains(exp.id) ? Color.designPrimaryFixedDim : .secondary)
                            Text(exp.category?.name ?? "未分类").font(.designBodySmall)
                            Spacer()
                            Text(CurrencyFormatter.formatDecimal(amount: abs(exp.amount), fractionDigits: 0))
                                .font(.designBodySmall).foregroundStyle(.secondary)
                        }
                    }.buttonStyle(.plain)
                }
                if !selectedExpenseIDs.isEmpty {
                    HStack { Spacer(); Text("合计: \(CurrencyFormatter.formatDecimal(amount: pendingExpenses.filter { selectedExpenseIDs.contains($0.id) }.reduce(0) { $0 + abs($1.amount) }, fractionDigits: 2))").font(.designBodySmall).foregroundStyle(Color.designPrimaryFixedDim) }
                }
            }
        }
        .padding(.horizontal, 24).padding(.vertical, 8)
    }

    // MARK: - Lending

    private var lendingSection: some View {
        HStack(spacing: 16) {
            Text("借贷方向").font(.designBodyMedium).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                ForEach([LendingDirection.lendOut, .borrowIn, .collect, .repay], id: \.self) { d in
                    Button {
                        withAnimation(.easeOut(duration: 0.15)) { lendingDirection = d }
                    } label: {
                        Text(d.displayName)
                            .font(.designBodySmall.weight(lendingDirection == d ? .semibold : .regular))
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(lendingDirection == d ? Color.orange.opacity(0.15) : Color.clear)
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(lendingDirection == d ? Color.orange.opacity(0.4) : Color.clear, lineWidth: 1))
                            .foregroundStyle(lendingDirection == d ? .orange : .secondary)
                    }.buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 24).padding(.vertical, 8)
    }

    private var lendingSettleSection: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(lendingDirection == .collect ? "关联待收" : "关联待还")
                .font(.designBodyMedium)
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .trailing)
            VStack(spacing: 8) {
                ForEach(pendingLendingTransactions) { item in
                    Button {
                        if selectedLendingIDs.contains(item.id) { selectedLendingIDs.remove(item.id) }
                        else { selectedLendingIDs.insert(item.id) }
                    } label: {
                        HStack {
                            Image(systemName: selectedLendingIDs.contains(item.id) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selectedLendingIDs.contains(item.id) ? Color.designPrimaryFixedDim : .secondary)
                            VStack(alignment: .leading) {
                                Text(item.lendingDirection?.displayName ?? "").font(.designBodySmall)
                                Text(item.date.formatted(date: .abbreviated, time: .omitted)).font(.designBodyCaption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            CurrencyText(amount: abs(item.amount), currencyCode: item.currencyCode, size: 13, foregroundColor: .secondary)
                        }
                    }.buttonStyle(.plain)
                }
                if !selectedLendingIDs.isEmpty {
                    HStack { Spacer(); Text("已选: \(CurrencyFormatter.formatDecimal(amount: pendingLendingTransactions.filter { selectedLendingIDs.contains($0.id) }.reduce(0) { $0 + abs($1.amount) }, fractionDigits: 2))").font(.designBodySmall).foregroundStyle(Color.designPrimaryFixedDim) }
                }
            }
        }
        .padding(.horizontal, 24).padding(.vertical, 8)
    }

    // MARK: - Photos

    private var photoSection: some View {
        HStack(spacing: 6) {
            PhotosPicker(selection: $selectedPhotos, maxSelectionCount: 5, matching: .images) {
                Label("附件", systemImage: "camera").font(.designBodySmall)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(Array(photoDataList.enumerated()), id: \.offset) { i, data in
                        if let nsImg = NSImage(data: data) {
                            Image(nsImage: nsImg).resizable().scaledToFill()
                                .frame(width: 32, height: 32).clipShape(RoundedRectangle(cornerRadius: 4))
                                .overlay(alignment: .topTrailing) {
                                    Button { photoDataList.remove(at: i) } label: {
                                        Image(systemName: "xmark.circle.fill").font(.system(size: 10)).foregroundStyle(.red)
                                    }.buttonStyle(.plain)
                                }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Save Button

    private var saveButton: some View {
        let canSave = amount != 0 && selectedAccount != nil
        let needsToAcct = (type == .transfer || type == .lending)
        let reallyCanSave = canSave && (!needsToAcct || selectedToAccount != nil)
        return Button { save() } label: {
            Label(editing != nil ? "更新" : "保存账单", systemImage: "checkmark")
                .font(.designBodyMedium.weight(.semibold))
                .frame(width: 160, height: 36)
                .background(Capsule().fill(Color.designPrimaryContainer.opacity(0.85)))
                .foregroundStyle(Color.designOnPrimaryContainer)
        }
        .buttonStyle(.plain)
        .disabled(!reallyCanSave)
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    // MARK: - Template Apply

    private func applyTemplate(_ tpl: TransactionTemplate) {
        type = tpl.type; amount = abs(tpl.amount)
        amountString = CurrencyFormatter.formatDecimal(amount: abs(tpl.amount), fractionDigits: 2)
        note = tpl.note ?? ""; selectedAccount = tpl.account; selectedToAccount = tpl.toAccount
        selectedCategory = tpl.category; selectedMember = tpl.member
        selectedMerchant = tpl.merchant; selectedProject = tpl.project
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if displayMode {
            if isEditing {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { cancelEditing() } }
                ToolbarItem(placement: .confirmationAction) { Button("保存") { save() }.disabled(amount == 0 || selectedAccount == nil) }
            } else {
                ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } }
                if let t = editing, canRefund(t) { ToolbarItem(placement: .primaryAction) { Button("退款") { showRefundSheet = true } } }
                ToolbarItem(placement: .primaryAction) { Button("编辑") { enterEditMode() } }
                ToolbarItem(placement: .destructiveAction) { Button("删除", role: .destructive) { deleteTarget = editing } }
            }
        }
    }

    private func enterEditMode() { withAnimation(.easeInOut(duration: 0.2)) { isEditing = true } }
    private func cancelEditing() {
        if let t = editing {
            type = t.type; amount = abs(t.amount); amountString = String(describing: abs(t.amount))
            note = t.note ?? ""; date = t.date; selectedAccount = t.account; selectedToAccount = t.toAccount
            selectedCategory = t.category; selectedMember = t.member; selectedMerchant = t.merchant
            selectedProject = t.project; lendingDirection = t.lendingDirection ?? .lendOut
            selectedCurrencyCode = t.currencyCode ?? t.account?.currencyCode ?? ledgerCurrencyCode
            isReimbursable = t.isReimbursable
            isSplit = t.isSplitParent
            if t.isSplitParent, let children = t.splitChildren {
                splitItems = Array(children).map { child in
                    SplitItemDraft(amount: abs(child.amount), category: child.category,
                                   note: child.note ?? "", member: child.member,
                                   merchant: child.merchant, project: child.project)
                }
            } else { splitItems = [] }
            if let paths = t.photoURLs, !paths.isEmpty {
                photoDataList = PhotoStorage.load(paths: paths)
            } else { photoDataList = [] }
        }
        withAnimation(.easeInOut(duration: 0.2)) { isEditing = false }
    }

    private func canRefund(_ t: Transaction) -> Bool {
        (t.type == .expense || t.type == .income) && t.refundGroupId == nil
    }

    // MARK: - Shared Numpad Popover

    /// Reusable Mac numpad popover. Use this for all amount inputs on Mac sheets.
    /// - Parameters:
    ///   - text: raw editing buffer
    ///   - amount: parsed Decimal, written on confirm
    ///   - amountString: formatted display string, written on confirm
    ///   - show: binding controlling popover visibility
    @ViewBuilder
    private func macNumpadPopover(
        text: Binding<String>,
        amount: Binding<Decimal>,
        amountString: Binding<String>,
        show: Binding<Bool>
    ) -> some View {
        VStack(spacing: 8) {
            NumpadGrid(
                onDigit: { d in
                    if let dotIdx = text.wrappedValue.firstIndex(of: ".") {
                        let decimals = text.wrappedValue[dotIdx...].dropFirst()
                        guard decimals.count < 2 else { return }
                    }
                    text.wrappedValue += "\(d)"
                },
                onDot: {
                    if !text.wrappedValue.contains(".") { text.wrappedValue += text.wrappedValue.isEmpty ? "0." : "." }
                },
                onDelete: {
                    if !text.wrappedValue.isEmpty { text.wrappedValue.removeLast() }
                },
                onClear: { text.wrappedValue = "" }
            )
            .frame(width: 220)

            Button("确认") {
                if let d = Decimal(string: text.wrappedValue), d != 0 {
                    amount.wrappedValue = d
                    amountString.wrappedValue = CurrencyFormatter.formatDecimal(amount: d, fractionDigits: 2)
                }
                withAnimation(.easeInOut(duration: 0.2)) { show.wrappedValue = false }
            }
            .font(.designBodyMedium.weight(.semibold))
            .frame(width: 220, height: 40)
            .background(Capsule().fill(Color.designPrimaryContainer.opacity(0.85)))
            .foregroundStyle(Color.designOnPrimaryContainer)
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
        }
        .padding(.top, 8)
    }

    private func deleteTx(_ t: Transaction) {
        if let paths = t.photoURLs, !paths.isEmpty { PhotoStorage.delete(paths: paths) }
        do { try appContainer.transactionService.deleteTransaction(t, context: modelContext); dismiss() }
        catch { errorMessage = error.localizedDescription }
    }

    // MARK: - Data

    private func loadPhotoData() {
        Task {
            var datas: [Data] = []
            for item in selectedPhotos { if let data = try? await item.loadTransferable(type: Data.self) { datas.append(data) } }
            photoDataList = datas
        }
    }

    private var ledgerCurrencyCode: String { appContainer.currentLedger?.defaultCurrencyCode ?? "CNY" }
    private var activeCurrency: String { selectedCurrencyCode.isEmpty ? ledgerCurrencyCode : selectedCurrencyCode }

    private func fetchExchangeRate() {
        guard activeCurrency != ledgerCurrencyCode, let svc = appContainer.exchangeRateService else { return }
        Task {
            if let er = try? await svc.fetchRate(from: ledgerCurrencyCode, to: activeCurrency, context: modelContext) {
                exchangeRate = Decimal(er.rate); convertedAmount = amount * Decimal(er.rate)
            }
        }
    }

    private func currencyName(_ code: String) -> String {
        switch code {
        case "CNY": "人民币"; case "USD": "美元"; case "EUR": "欧元"; case "JPY": "日元"
        case "GBP": "英镑"; case "HKD": "港币"; case "AUD": "澳元"; case "CAD": "加元"
        case "KRW": "韩元"; case "TWD": "新台币"; case "SGD": "新加坡元"; case "CHF": "瑞士法郎"
        case "NZD": "新西兰元"; case "THB": "泰铢"; case "MYR": "马币"; case "INR": "印度卢比"
        default: code
        }
    }

    private func loadData() {
        guard let ledger = appContainer.currentLedger else { return }
        accounts = (try? appContainer.accountService.fetchAccounts(for: ledger, context: modelContext)) ?? []
        loadCategories()
        members = (try? appContainer.memberService.fetchMembers(for: ledger, context: modelContext))?.filter(\.isActive) ?? []
        merchants = (try? appContainer.merchantService.fetchMerchants(for: ledger, context: modelContext))?.filter(\.isActive) ?? []
        projects = (try? appContainer.projectService.fetchProjects(for: ledger, context: modelContext))?.filter(\.isActive) ?? []
        templates = (try? appContainer.templateService.fetchTemplates(for: ledger, context: modelContext)) ?? []
        if type == .income {
            let all = (try? appContainer.transactionService.fetchTransactions(for: ledger, context: modelContext, filters: nil)) ?? []
            pendingExpenses = all.filter { $0.type == .expense && $0.isReimbursable && $0.reimbursementStatus == .pending }
        }
    }

    private func loadCategories() {
        guard let ledger = appContainer.currentLedger else { return }
        categories = (try? appContainer.categoryService.fetchCategories(for: ledger, type: type, context: modelContext)) ?? []
    }

    private func loadPendingReimbursement() {
        guard type == .income, let ledger = appContainer.currentLedger else { pendingExpenses = []; return }
        let all = (try? appContainer.transactionService.fetchTransactions(for: ledger, context: modelContext, filters: nil)) ?? []
        pendingExpenses = all.filter { $0.type == .expense && $0.isReimbursable && $0.reimbursementStatus == .pending }
    }

    // MARK: - Save

    private func signingAmount() -> Decimal { signedAmount(amount: amount, type: type, direction: type == .lending ? lendingDirection : nil) }

    private func save() {
        guard let ledger = appContainer.currentLedger, amount != 0 else { return }
        if isSplit { guard splitTotal == amount else { errorMessage = "拆分合计与总额不一致"; return } }
        if let existing = editing {
            // Re-fetch to ensure we're working within the correct context
            let req = NSFetchRequest<Transaction>(entityName: "Transaction")
            req.predicate = NSPredicate(format: "id == %@", existing.id as CVarArg)
            req.fetchLimit = 1
            guard let t = (try? modelContext.fetch(req))?.first else { errorMessage = String(localized: "交易未找到"); return }

            // Basic fields
            t.type = type; t.amount = signingAmount(); t.note = note.isEmpty ? nil : note
            t.date = date; t.account = selectedAccount; t.toAccount = selectedToAccount
            t.category = selectedCategory; t.member = selectedMember; t.merchant = selectedMerchant
            t.project = selectedProject; t.modifiedAt = Date()

            // Currency + exchange rate
            t.currencyCode = activeCurrency
            if activeCurrency != ledgerCurrencyCode, let rate = exchangeRate {
                t.exchangeRate = NSDecimalNumber(decimal: rate).doubleValue
                t.convertedAmount = convertedAmount
            } else { t.exchangeRate = 0; t.convertedAmount = nil }

            // Split: delete old children, recreate
            if type == .expense {
                if let oldChildren = t.splitChildren {
                    for child in Array(oldChildren) { modelContext.delete(child) }
                }
                t.isSplitParent = isSplit
                if isSplit {
                    for item in splitItems {
                        let child = Transaction(type: .expense, amount: -abs(item.amount),
                            note: item.note.isEmpty ? nil : item.note, date: date, account: selectedAccount,
                            category: item.category, member: item.member, merchant: item.merchant,
                            project: item.project, parentTransaction: t, context: modelContext)
                        child.ledger = t.ledger
                    }
                }
                t.reimbursementStatus = isReimbursable ? .pending : .none
            }

            // Lending: unlink old settled, relink new
            if type == .lending {
                t.lendingDirection = lendingDirection
                // Unlink previously settled lending
                let settledReq = NSFetchRequest<Transaction>(entityName: "Transaction")
                settledReq.predicate = NSPredicate(format: "settledByLendingTransactionId == %@", t.id as CVarArg)
                if let settled = try? modelContext.fetch(settledReq) {
                    for s in settled {
                        s.settledByLendingTransactionId = nil
                        s.settledAmount = 0; s.lendingStatus = .pending
                    }
                }
                if (lendingDirection == .collect || lendingDirection == .repay) && !selectedLendingIDs.isEmpty {
                    try? linkSettled(txID: t.id)
                }
            }

            // Income: unlink old reimbursed, relink new
            if type == .income {
                let reimbursedReq = NSFetchRequest<Transaction>(entityName: "Transaction")
                reimbursedReq.predicate = NSPredicate(format: "reimbursedById == %@", t.id as CVarArg)
                if let reimbursed = try? modelContext.fetch(reimbursedReq) {
                    for exp in reimbursed { exp.reimbursementStatus = .pending; exp.reimbursedById = nil }
                }
                if !selectedExpenseIDs.isEmpty { try? linkReimbursed(txID: t.id) }
            }

            // Photos: delete old, save new
            if let oldPaths = t.photoURLs, !oldPaths.isEmpty {
                PhotoStorage.delete(paths: oldPaths)
            }
            t.photoURLs = photoDataList.isEmpty ? nil : PhotoStorage.save(photoDataList, transactionId: t.id)

            do { try modelContext.save(); isEditing = false }
            catch { errorMessage = error.localizedDescription }
        } else if let refundOriginal = refundingOriginal {
            // Refund: use the dedicated service method
            do {
                _ = try appContainer.transactionService.createRefund(for: refundOriginal, amount: amount, context: modelContext)
                dismiss()
            } catch { errorMessage = error.localizedDescription }
        } else {
            let signed = signingAmount()
            if isSplit {
                let parent = Transaction(type: .expense, amount: signed, note: note.isEmpty ? nil : note,
                    date: date, account: selectedAccount, isSplitParent: true, context: modelContext)
                if isReimbursable { parent.reimbursementStatus = .pending }; parent.ledger = ledger
                if !photoDataList.isEmpty { parent.photoURLs = PhotoStorage.save(photoDataList, transactionId: parent.id) }
                for item in splitItems {
                    let child = Transaction(type: .expense, amount: -abs(item.amount), note: item.note.isEmpty ? nil : item.note,
                        date: date, account: selectedAccount, category: item.category, member: item.member,
                        merchant: item.merchant, project: item.project, parentTransaction: parent, context: modelContext)
                    child.ledger = ledger
                }
                try? modelContext.save()
                NotificationCenter.default.post(name: .transactionDidChange, object: nil)
                dismiss()
            } else if type == .transfer, let from = selectedAccount, let to = selectedToAccount {
                let dAmount: Decimal? = isCrossCurrencyTransfer ? destAmount : nil
                do {
                    _ = try appContainer.transactionService.createTransfer(
                        from: from, to: to, amount: abs(amount), destAmount: dAmount,
                        date: date, note: note.isEmpty ? nil : note, ledger: ledger, context: modelContext
                    )
                    dismiss()
                } catch { errorMessage = error.localizedDescription }
            } else {
                let tx = Transaction(type: type, amount: signed, currencyCode: activeCurrency, note: note.isEmpty ? nil : note,
                    date: date, account: selectedAccount, toAccount: selectedToAccount,
                    category: selectedCategory, member: selectedMember, merchant: selectedMerchant, project: selectedProject, context: modelContext)
                if activeCurrency != ledgerCurrencyCode, let rate = exchangeRate { tx.exchangeRate = NSDecimalNumber(decimal: rate).doubleValue; tx.convertedAmount = convertedAmount }
                if type == .expense && isReimbursable { tx.reimbursementStatus = .pending }
                if type == .lending { tx.lendingDirection = lendingDirection; if lendingDirection == .lendOut || lendingDirection == .borrowIn { tx.lendingStatus = .pending } }
                if !photoDataList.isEmpty { tx.photoURLs = PhotoStorage.save(photoDataList, transactionId: tx.id) }
                do {
                    try appContainer.transactionService.createTransaction(tx, ledger: ledger, context: modelContext)
                    if type == .lending && (lendingDirection == .collect || lendingDirection == .repay) && !selectedLendingIDs.isEmpty { try linkSettled(txID: tx.id) }
                    if type == .income && !selectedExpenseIDs.isEmpty { try linkReimbursed(txID: tx.id) }
                    dismiss()
                } catch { errorMessage = error.localizedDescription }
            }
        }
    }

    private func linkReimbursed(txID: UUID) throws {
        for exp in pendingExpenses.filter({ selectedExpenseIDs.contains($0.id) }) { exp.reimbursementStatus = .reimbursed; exp.reimbursedById = txID }
        try modelContext.save()
    }

    private func loadPendingLendingTx() {
        guard type == .lending, let ledger = appContainer.currentLedger else { return }
        let all = (try? appContainer.transactionService.fetchTransactions(for: ledger, context: modelContext, filters: nil)) ?? []
        switch lendingDirection {
        case .collect: pendingLendingTransactions = all.filter { $0.lendingDirection == .lendOut && $0.lendingStatus == .pending && $0.toAccount?.id == selectedAccount?.id }
        case .repay: pendingLendingTransactions = all.filter { $0.lendingDirection == .borrowIn && $0.lendingStatus == .pending && $0.account?.id == selectedToAccount?.id }
        default: pendingLendingTransactions = []
        }
        selectedLendingIDs = Set(pendingLendingTransactions.map(\.id))
    }

    private func linkSettled(txID: UUID) throws {
        var remaining = abs(signingAmount())
        for item in pendingLendingTransactions.filter({ selectedLendingIDs.contains($0.id) }).sorted(by: { $0.date < $1.date }) {
            guard remaining > 0 else { break }
            let debt = abs(item.amount); let paid = item.settledAmount ?? 0; let owed = debt - paid
            if remaining >= owed { item.settledAmount = debt; item.lendingStatus = .settled; remaining -= owed }
            else { item.settledAmount = paid + remaining; remaining = 0 }
            if item.settledByLendingTransactionId == nil { item.settledByLendingTransactionId = txID }
        }
        try modelContext.save()
    }
}

// MARK: - Mac Sheet Frame

extension View {
    func macSheetFrame() -> some View {
        self.frame(minWidth: 440, idealWidth: 460, minHeight: 440)
    }
}

// MARK: - macOS 27 兼容桥接

struct DeleteConfirmationModifier: ViewModifier {
    @Binding var deleteTarget: Transaction?
    let onDelete: (Transaction) -> Void

    func body(content: Content) -> some View {
        if #available(macOS 27, *) {
            content.confirmationDialog("确认删除", isPresented: Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } })) {
                Button("删除", role: .destructive) { if let t = deleteTarget { onDelete(t) }; deleteTarget = nil }
            } message: { Text("此操作不可撤销") }
        } else {
            content.alert("确认删除", isPresented: Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } })) {
                Button("取消", role: .cancel) { deleteTarget = nil }
                Button("删除", role: .destructive) { if let t = deleteTarget { onDelete(t) }; deleteTarget = nil }
            } message: { Text("此操作不可撤销") }
        }
    }
}
