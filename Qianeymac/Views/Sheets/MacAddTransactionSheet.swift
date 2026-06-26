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

        if let t = refunding {
            initEditing = nil; initDisplayMode = false
            initType = t.type; initAmount = abs(t.amount)
            initAmountString = String(describing: abs(t.amount))
            initNote = "退款: \(t.note ?? "")"; initDate = Date()
            initAccount = t.account; initToAccount = nil
            initCategory = t.category; initMember = nil
            initMerchant = nil; initProject = nil
            initLendingDirection = .lendOut
        } else if let t = editing {
            initEditing = t; initDisplayMode = displayMode
            initType = t.type; initAmount = abs(t.amount)
            initAmountString = String(describing: abs(t.amount))
            initNote = t.note ?? ""; initDate = t.date
            initAccount = t.account; initToAccount = t.toAccount
            initCategory = t.category; initMember = t.member
            initMerchant = t.merchant; initProject = t.project
            initLendingDirection = t.lendingDirection ?? .lendOut
        } else {
            initEditing = nil; initDisplayMode = false
            initType = .expense; initAmount = 0
            initAmountString = ""; initNote = ""; initDate = Date()
            initAccount = nil; initToAccount = nil
            initCategory = nil; initMember = nil
            initMerchant = nil; initProject = nil
            initLendingDirection = .lendOut
        }

        self.editing = initEditing
        self.displayMode = initDisplayMode
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
        _isSplit = State(initialValue: false)
        _splitItems = State(initialValue: [])
        _isReimbursable = State(initialValue: false)
        _pendingExpenses = State(initialValue: [])
        _selectedExpenseIDs = State(initialValue: [])
        _selectedCurrencyCode = State(initialValue: "CNY")
        _selectedPhotos = State(initialValue: [])
        _photoDataList = State(initialValue: [])
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
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                amountSection
                Divider().padding(.horizontal, 24)
                toggleAndSplitRows
                templateRow
                lendingRow
                accountRows
                categoryAndExtrasRows
                reimbursementAndLendingRows
                dateNoteRow
            }
        }
        .disabled(isViewing)
        .designScreen()
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
            ZStack {
                // Centered amount
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

                // Currency picker - absolutely left
                HStack {
                    Picker("", selection: $selectedCurrencyCode) {
                        ForEach(currencies, id: \.self) { code in
                            Text("\(code) \(currencyName(code))").tag(code)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .disabled(selectedAccount != nil)
                    .onChange(of: selectedCurrencyCode) { _, _ in fetchExchangeRate() }
                    Spacer()
                }
            }
            .frame(maxWidth: .infinity)

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
            Divider().padding(.horizontal, 24)
        }
    }

    @ViewBuilder
    private var lendingRow: some View {
        if type == .lending {
            lendingSection
            Divider().padding(.horizontal, 24)
        }
    }

    @ViewBuilder
    private var accountRows: some View {
        Group {
            formPicker(label: (type == .transfer || type == .lending) ? "转出账户" : "账户",
                       selection: $selectedAccount, items: accounts,
                       icon: { $0.iconName ?? "creditcard" }, name: { $0.name },
                       color: { Color(hex: $0.colorHex ?? "#007AFF") })
            if type == .transfer || type == .lending {
                formPicker(label: "转入账户", selection: $selectedToAccount,
                           items: accounts.filter { $0.id != selectedAccount?.id },
                           icon: { $0.iconName ?? "creditcard" }, name: { $0.name },
                           color: { Color(hex: $0.colorHex ?? "#007AFF") })
            }
            Divider().padding(.horizontal, 24)
        }
    }

    @ViewBuilder
    private var categoryAndExtrasRows: some View {
        Group {
            if type != .transfer && type != .lending {
                formPicker(label: "分类", selection: $selectedCategory,
                           items: categories, icon: { $0.iconName }, name: { $0.name },
                           color: { Color(hex: $0.colorHex) },
                           indent: { var d = 0; var p = $0.parent; while p != nil { d += 1; p = p?.parent }; return d })
                formPicker(label: "成员", selection: $selectedMember,
                           items: members, icon: { $0.avatar }, name: { $0.name })
                formPicker(label: "商家", selection: $selectedMerchant,
                           items: merchants, icon: { _ in "bag" }, name: { $0.name })
                formPicker(label: "项目", selection: $selectedProject,
                           items: projects, icon: { _ in "folder" }, name: { $0.name })
                Divider().padding(.horizontal, 24)
            }
        }
    }

    @ViewBuilder
    private var toggleAndSplitRows: some View {
        Group {
            if type == .expense && editing == nil {
                toggleSection
                if isSplit { splitDetailSection }
                Divider().padding(.horizontal, 24)
            }
        }
    }

    @ViewBuilder
    private var reimbursementAndLendingRows: some View {
        Group {
            if type == .income && !pendingExpenses.isEmpty {
                reimbursementSection
                Divider().padding(.horizontal, 24)
            }
            if type == .lending && (lendingDirection == .collect || lendingDirection == .repay) && !pendingLendingTransactions.isEmpty {
                lendingSettleSection
                Divider().padding(.horizontal, 24)
            }
        }
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

    // MARK: - Form Picker (Mac-native Menu style)

    private func formPicker<T: Identifiable & Hashable>(
        label: String, selection: Binding<T?>, items: [T],
        icon: @escaping (T) -> String, name: @escaping (T) -> String,
        color: @escaping (T) -> Color = { _ in .secondary }, indent: ((T) -> Int)? = nil
    ) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.designBodyMedium)
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .trailing)
            Picker("", selection: selection) {
                Text("无").tag(nil as T?)
                ForEach(items, id: \.self) { item in
                    HStack {
                        Image(systemName: icon(item)).foregroundStyle(color(item))
                        Text(name(item))
                    }
                    .padding(.leading, CGFloat(indent?(item) ?? 0) * 16)
                    .tag(item as T?)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(minWidth: 220, maxWidth: 220, alignment: .leading)
        }
        .padding(.horizontal, 24).padding(.vertical, 8)
    }

    // MARK: - Template Section

    private var templateSection: some View {
        HStack(spacing: 12) {
            Text("模板").font(.designBodyMedium).foregroundStyle(.secondary)
                .frame(width: 60, alignment: .trailing)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(templates) { tpl in
                        Button { applyTemplate(tpl) } label: {
                            Text(tpl.name).font(.designBodyCaption)
                                .padding(.horizontal, 10).padding(.vertical, 4)
                                .background(Capsule().fill(Color.designSurfaceContainer.opacity(0.5)))
                                .overlay(Capsule().stroke(Color.designOutlineVariant, lineWidth: 0.5))
                        }
                        .buttonStyle(.plain)
                    }
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
                HStack(spacing: 8) {
                    Button { splitItems.remove(at: i) } label: {
                        Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                    }.buttonStyle(.plain)
                    TextField("金额", text: Binding(
                        get: { item.amount == 0 ? "" : String(describing: item.amount) },
                        set: { splitItems[i].amount = Decimal(string: $0) ?? 0 }
                    )).frame(width: 80)
                    Picker("分类", selection: Binding(get: { item.category }, set: { splitItems[i].category = $0 })) {
                        Text("无").tag(nil as Category?)
                        ForEach(categories.filter { ($0.children?.count ?? 0) == 0 }) { c in
                            Text(c.name).tag(c as Category?)
                        }
                    }.frame(width: 120)
                    Picker("成员", selection: Binding(get: { item.member }, set: { splitItems[i].member = $0 })) {
                        Text("无").tag(nil as Member?)
                        ForEach(members) { m in Text(m.name).tag(m as Member?) }
                    }.frame(width: 100)
                    Picker("商家", selection: Binding(get: { item.merchant }, set: { splitItems[i].merchant = $0 })) {
                        Text("无").tag(nil as Merchant?)
                        ForEach(merchants) { m in Text(m.name).tag(m as Merchant?) }
                    }.frame(width: 100)
                }
            }
        }
        .padding(.horizontal, 24).padding(.vertical, 8)
    }

    private var splitTotal: Decimal { splitItems.reduce(0) { $0 + $1.amount } }

    // MARK: - Reimbursement

    private var reimbursementSection: some View {
        VStack(spacing: 8) {
            Text("关联待报销").font(.designLabel).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
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
        VStack(spacing: 8) {
            Text(lendingDirection == .collect ? "关联待收" : "关联待还")
                .font(.designLabel).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
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
            existing.type = type; existing.amount = signingAmount(); existing.note = note.isEmpty ? nil : note
            existing.date = date; existing.account = selectedAccount; existing.toAccount = selectedToAccount
            existing.category = selectedCategory; existing.member = selectedMember; existing.merchant = selectedMerchant
            existing.project = selectedProject
            if type == .lending { existing.lendingDirection = lendingDirection }
            do { try appContainer.transactionService.updateTransaction(existing, context: modelContext); isEditing = false }
            catch { errorMessage = error.localizedDescription }
        } else {
            let signed = signingAmount()
            if isSplit {
                let parent = Transaction(type: .expense, amount: signed, note: note.isEmpty ? nil : note,
                    date: date, account: selectedAccount, isSplitParent: true, context: modelContext)
                if isReimbursable { parent.reimbursementStatus = .pending }; parent.ledger = ledger
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
