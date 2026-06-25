import SwiftUI
@preconcurrency import CoreData
import PhotosUI

struct SplitItemDraft: Identifiable {
    var id = UUID(); var amount: Decimal = 0; var category: Category?
    var note: String = ""; var member: Member?; var merchant: Merchant?; var project: Project?
}

enum MacSheetPicker: Identifiable {
    case account, toAccount, category, member, merchant, project, template
    var id: Self { self }
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
    @State private var pickerSheet: MacSheetPicker?
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

    init(editing: Transaction? = nil, displayMode: Bool = false, refunding: Transaction? = nil) {
        // Resolve initial values for all @State vars outside conditionals
        // (Xcode 27 @State macro forbids default + init override on same var)
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
        // Remaining @State: use default values (always the same regardless of path)
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
        _selectedCurrencyCode = State(initialValue: "")
        _selectedPhotos = State(initialValue: [])
        _photoDataList = State(initialValue: [])
        _showRefundSheet = State(initialValue: false)
    }

    private var isViewing: Bool { displayMode && !isEditing }

    @ViewBuilder
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    // 模板（仅新建时，对齐iOS）
                    if editing == nil && !templates.isEmpty { templateSection }
                    // 类型切换
                    typeRow
                    // 借贷方向
                    if type == .lending { lendingSection }
                    // 金额
                    amountSection
                    // 条件区块
                    conditionalSections
                    // 账户
                    accountSection
                    // 分类
                    if type != .transfer && type != .lending { categorySection }
                    // 成员/商家/项目
                    if type != .transfer && type != .lending { extrasSection }
                    // 备注 + 日期 + 保存
                    bottomSection
                }
                .padding(20)
            }
            .disabled(isViewing)
            .designScreen()
            .navigationTitle(editing != nil ? (isEditing ? "编辑交易" : "交易详情") : "记一笔")
            .toolbar { toolbarContent }
            .task { loadData() }
            .onChange(of: type) { _, _ in loadCategories(); loadPendingReimbursement() }
            .onChange(of: pickerSheet) { _, v in if v != nil { loadData() } }
            .onChange(of: lendingDirection) { _, _ in loadPendingLendingTx() }
            .onChange(of: selectedAccount) { _, _ in loadPendingLendingTx() }
            .onChange(of: selectedToAccount) { _, _ in loadPendingLendingTx() }
            .popover(item: $pickerSheet) { pickerContent(for: $0) }
            // @available(macOS 27, *) — 旧系统回退到 .alert
            .modifier(DeleteConfirmationModifier(deleteTarget: $deleteTarget, onDelete: { deleteTx($0) }))
            .sheet(isPresented: $showRefundSheet) {
                if let t = editing { MacAddTransactionSheet(refunding: t) }
            }
            .alert("保存失败", isPresented: .constant(errorMessage != nil)) {
                Button("好") { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
        }
        .frame(minWidth: 460, minHeight: 500)
    }

    private var accountSection: some View {
        Group {
            recentPickerRow(label: (type == .transfer || type == .lending) ? "转出账户" : "账户",
                items: accounts, icon: { $0.iconName ?? "creditcard" }, name: { $0.name },
                key: "mac_account", selected: selectedAccount,
                onSelect: { selectedAccount = $0; saveRecentMac("\($0.id)", "mac_account") },
                onMore: { pickerSheet = .account })
            if type == .transfer || type == .lending {
                recentPickerRow(label: "转入账户",
                    items: accounts.filter { $0.id != selectedAccount?.id },
                    icon: { $0.iconName ?? "creditcard" }, name: { $0.name },
                    key: "mac_toAccount", selected: selectedToAccount,
                    onSelect: { selectedToAccount = $0; saveRecentMac("\($0.id)", "mac_toAccount") },
                    onMore: { pickerSheet = .toAccount })
            }
        }
    }

    private var categorySection: some View {
        recentPickerRow(label: "分类", items: categories, icon: { $0.iconName }, name: { $0.name },
            key: "mac_category", selected: selectedCategory,
            onSelect: { selectedCategory = $0; saveRecentMac("\($0.id)", "mac_category") },
            onMore: { pickerSheet = .category })
    }

    private var extrasSection: some View {
        Group {
            recentPickerRow(label: "成员", items: members, icon: { $0.avatar }, name: { $0.name },
                key: "mac_member", selected: selectedMember,
                onSelect: { selectedMember = $0; saveRecentMac("\($0.id)", "mac_member") }, onMore: { pickerSheet = .member })
            recentPickerRow(label: "商家", items: merchants, icon: { _ in "bag" }, name: { $0.name },
                key: "mac_merchant", selected: selectedMerchant,
                onSelect: { selectedMerchant = $0; saveRecentMac("\($0.id)", "mac_merchant") }, onMore: { pickerSheet = .merchant })
            recentPickerRow(label: "项目", items: projects, icon: { _ in "folder" }, name: { $0.name },
                key: "mac_project", selected: selectedProject,
                onSelect: { selectedProject = $0; saveRecentMac("\($0.id)", "mac_project") }, onMore: { pickerSheet = .project })
        }
    }

    @ViewBuilder
    private var bottomSection: some View {
        TextField("备注", text: $note).font(.designBodyMedium).padding(12).glassCard(cornerRadius: 14)

        // 照片附件
        if editing == nil || isEditing {
            HStack {
                PhotosPicker(selection: $selectedPhotos, maxSelectionCount: 5, matching: .images) {
                    Label("附件", systemImage: "camera").font(.designBodySmall)
                }
                if !photoDataList.isEmpty {
                    ScrollView(.horizontal) {
                        HStack(spacing: 6) {
                            ForEach(Array(photoDataList.enumerated()), id: \.offset) { i, data in
                                if let nsImg = NSImage(data: data) {
                                    Image(nsImage: nsImg).resizable().scaledToFill()
                                        .frame(width: 40, height: 40).clipShape(RoundedRectangle(cornerRadius: 6))
                                        .overlay(alignment: .topTrailing) {
                                            Button { photoDataList.remove(at: i) } label: {
                                                Image(systemName: "xmark.circle.fill").font(.designBodyCaption).foregroundStyle(.red)
                                            }.buttonStyle(.plain)
                                        }
                                }
                            }
                        }
                    }
                }
            }.padding(12).glassCard(cornerRadius: 14)
            .onChange(of: selectedPhotos) { _, _ in loadPhotoData() }
        }

        DatePicker("", selection: $date, displayedComponents: [.date, .hourAndMinute])
            .labelsHidden().padding(10).glassCard(cornerRadius: 14)
        saveButton
    }

    private func loadPhotoData() {
        Task {
            var datas: [Data] = []
            for item in selectedPhotos {
                if let data = try? await item.loadTransferable(type: Data.self) { datas.append(data) }
            }
            photoDataList = datas
        }
    }

    private var saveButton: some View {
        let canSave = amount != 0 && selectedAccount != nil
        let needsToAcct = (type == .transfer || type == .lending)
        let reallyCanSave = canSave && (!needsToAcct || selectedToAccount != nil)
        return Button { save() } label: {
            Label(isEditing ? "更新账单" : "保存账单", systemImage: "send").font(.designBodyMedium.weight(.bold))
                .frame(maxWidth: .infinity).frame(height: 48)
                .background(Capsule().fill(Color.designPrimaryContainer.opacity(0.85)))
                .foregroundStyle(Color.designOnPrimaryContainer)
        }
        .buttonStyle(.plain).opacity(reallyCanSave ? 1 : 0.4).disabled(!reallyCanSave)
    }

    @ViewBuilder
    private var conditionalSections: some View {
        if type == .expense && editing == nil { splitReimbToggle }
        if isSplit { splitSection }
        if type == .income && !pendingExpenses.isEmpty { reimbursementSection }
    }

    private var splitReimbToggle: some View {
        HStack(spacing: 12) {
            Toggle("拆分记账", isOn: $isSplit).font(.designBodySmall)
            Toggle("可报销", isOn: $isReimbursable).font(.designBodySmall)
        }.padding(10).glassCard(cornerRadius: 10)
    }

    // MARK: - Split

    private var splitSection: some View {
        VStack(spacing: 8) {
            HStack {
                Text("拆分明细").font(.designLabel).foregroundStyle(Color.designPrimary.opacity(0.8))
                Spacer()
                Text("合计: \(CurrencyFormatter.formatDecimal(amount: splitTotal, fractionDigits: 2))")
                    .font(.designBodySmall).foregroundStyle(splitTotal == amount ? Color.designPrimaryFixedDim : Color.designAccentRed)
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
        }.padding(12).glassCard(cornerRadius: 14)
    }

    private var splitTotal: Decimal { splitItems.reduce(0) { $0 + $1.amount } }

    // MARK: - Reimbursement

    private var reimbursementSection: some View {
        VStack(spacing: 8) {
            Text("关联待报销").font(.designLabel).foregroundStyle(Color.designPrimary.opacity(0.8)).frame(maxWidth: .infinity, alignment: .leading)
            let total = pendingExpenses.filter { selectedExpenseIDs.contains($0.id) }.reduce(Decimal.zero) { $0 + abs($1.amount) }
            ForEach(pendingExpenses) { exp in
                Button {
                    if selectedExpenseIDs.contains(exp.id) { selectedExpenseIDs.remove(exp.id) } else { selectedExpenseIDs.insert(exp.id) }
                } label: {
                    HStack {
                        Image(systemName: selectedExpenseIDs.contains(exp.id) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(selectedExpenseIDs.contains(exp.id) ? Color.designPrimaryFixedDim : Color.designOnSurfaceVariant)
                        Text(exp.category?.name ?? "未分类").font(.designBodySmall)
                        Spacer()
                        Text(CurrencyFormatter.formatDecimal(amount: abs(exp.amount), fractionDigits: 0)).font(.designBodySmall).foregroundStyle(.secondary)
                    }.padding(8)
                }.buttonStyle(.plain)
            }
            if !selectedExpenseIDs.isEmpty {
                HStack { Spacer(); Text("合计: \(CurrencyFormatter.formatDecimal(amount: total, fractionDigits: 2))").font(.designBodySmall).foregroundStyle(Color.designPrimaryFixedDim) }
            }
        }.padding(12).glassCard(cornerRadius: 14)
    }

    // MARK: - Templates

    private var templateSection: some View {
        let recent = topRecentMac(templates, key: "mac_template", selected: nil)
        return VStack(spacing: 8) {
            HStack {
                Text("模板").font(.designLabel).foregroundStyle(Color.designPrimary.opacity(0.8))
                Spacer()
                Button { pickerSheet = .template } label: {
                    HStack(spacing: 2) { Text("更多").font(.designLabel); Image(systemName: "chevron.right") }
                        .font(.designLabel).foregroundStyle(Color.designAccentGreen)
                }.buttonStyle(.plain)
            }
            HStack(spacing: 8) {
                ForEach(Array(recent.prefix(4).enumerated()), id: \.offset) { _, tpl in
                    Button { applyTemplate(tpl) } label: {
                        Text(tpl.name).font(.designBodyCaption).lineLimit(1)
                            .padding(.horizontal, 8).padding(.vertical, 6)
                            .glassCard(cornerRadius: 8)
                    }.buttonStyle(.plain)
                }
            }
        }.padding(12).glassCard(cornerRadius: 14)
    }

    private func applyTemplate(_ tpl: TransactionTemplate) {
        type = tpl.type
        amount = abs(tpl.amount); amountString = String(describing: abs(tpl.amount))
        note = tpl.note ?? ""
        selectedAccount = tpl.account; selectedToAccount = tpl.toAccount
        selectedCategory = tpl.category; selectedMember = tpl.member
        selectedMerchant = tpl.merchant; selectedProject = tpl.project
        saveRecentMac("\(tpl.id)", "mac_template")
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
                ToolbarItem(placement: .destructiveAction) { Button("删除") { deleteTarget = editing }.foregroundStyle(.red) }
            }
        } else {
            ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
        }
    }

    private func enterEditMode() { withAnimation(.easeInOut(duration: 0.2)) { isEditing = true } }
    private func cancelEditing() {
        if let t = editing {
            type = t.type; amount = abs(t.amount)
            amountString = String(describing: abs(t.amount)); note = t.note ?? ""; date = t.date
            selectedAccount = t.account; selectedToAccount = t.toAccount; selectedCategory = t.category
            selectedMember = t.member; selectedMerchant = t.merchant; selectedProject = t.project
            lendingDirection = t.lendingDirection ?? .lendOut
        }
        withAnimation(.easeInOut(duration: 0.2)) { isEditing = false }
    }

    private func canRefund(_ t: Transaction) -> Bool {
        (t.type == .expense || t.type == .income) && t.refundGroupId == nil
    }

    private func deleteTx(_ t: Transaction) {
        do {
            try appContainer.transactionService.deleteTransaction(t, context: modelContext)
            dismiss()
        } catch { errorMessage = error.localizedDescription }
    }

    private var typeRow: some View {
        HStack(spacing: 8) {
            typeButton(.expense); typeButton(.income)
            typeButton(.transfer); typeButton(.lending)
        }.padding(12).glassCard(cornerRadius: 14)
    }

    private var amountSection: some View {
        let currencies = ["CNY", "USD", "EUR", "JPY", "GBP", "HKD", "AUD", "CAD", "KRW", "TWD", "SGD", "CHF", "NZD", "THB", "MYR", "INR"]
        return VStack(spacing: 8) {
            HStack {
                Text(CurrencyFormatter.currencySymbol(for: selectedCurrencyCode.isEmpty ? currencyCode() : selectedCurrencyCode))
                    .font(.custom("JetBrainsMono-Medium", fixedSize: 24))
                    .foregroundStyle(Color.designPrimaryFixedDim)
                TextField("0.00", text: $amountString)
                    .font(.custom("JetBrainsMono-Medium", fixedSize: 28))
                    .multilineTextAlignment(.trailing)
                    .onChange(of: amountString) { _, v in
                        amountString = v.filter { "0123456789.".contains($0) }
                        amount = Decimal(string: amountString) ?? 0
                    }
                Menu {
                    ForEach(currencies, id: \.self) { code in
                        Button { selectedCurrencyCode = code; fetchExchangeRate() } label: {
                            if code == activeCurrency { Label("\(code) \(currencyName(code))", systemImage: "checkmark") }
                            else { Text("\(code) \(currencyName(code))") }
                        }
                    }
                } label: {
                    Text(activeCurrency).font(.designBodySmall)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Capsule().fill(Color.designSurfaceContainer))
                }
            }
            if let rate = exchangeRate, activeCurrency != currencyCode() {
                HStack {
                    Text("1 \(currencyCode()) = \(NSDecimalNumber(decimal: rate).stringValue) \(activeCurrency)")
                        .font(.designBodyCaption).foregroundStyle(Color.designOnSurfaceVariant)
                    Spacer()
                    if let converted = convertedAmount {
                        Text("≈ \(CurrencyFormatter.currencySymbol(for: currencyCode()))\(CurrencyFormatter.formatDecimal(amount: converted, fractionDigits: 2))")
                            .font(.designBodyCaption).foregroundStyle(Color.designPrimaryFixedDim)
                    }
                }
            }
        }.padding(14).glassCard(cornerRadius: 14)
    }

    private var activeCurrency: String { selectedCurrencyCode.isEmpty ? currencyCode() : selectedCurrencyCode }

    private func fetchExchangeRate() {
        guard activeCurrency != currencyCode(), let svc = appContainer.exchangeRateService else { return }
        Task {
            if let er = try? await svc.fetchRate(from: currencyCode(), to: activeCurrency, context: modelContext) {
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

    // MARK: - Type Buttons

    private func typeButton(_ t: TransactionType) -> some View {
        let sel = type == t
        return Button { type = t } label: {
            Label(t.displayName, systemImage: t.systemIcon)
                .font(.designBodySmall.weight(sel ? .bold : .regular))
                .frame(maxWidth: .infinity).frame(height: 40)
                .background(sel ? Color.designPrimaryContainer.opacity(0.2) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10)
                    .stroke(sel ? Color.designPrimaryContainer.opacity(0.4) : Color.clear, lineWidth: 1))
                .foregroundStyle(sel ? Color.designPrimaryContainer : Color.designOnSurfaceVariant)
        }.buttonStyle(.plain)
        .disabled(editing != nil)
    }

    // MARK: - Lending Section

    private var lendingSection: some View {
        Group {
            VStack(spacing: 8) {
                Text("借贷方向").font(.designLabel).foregroundStyle(Color.designPrimary.opacity(0.8))
                    .frame(maxWidth: .infinity, alignment: .leading)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    directionBtn(.lendOut); directionBtn(.borrowIn)
                    directionBtn(.collect); directionBtn(.repay)
                }
            }.padding(12).glassCard(cornerRadius: 14)

            if (lendingDirection == .collect || lendingDirection == .repay) && !pendingLendingTransactions.isEmpty {
                VStack(spacing: 8) {
                    Text(lendingDirection == .collect ? "关联待收" : "关联待还")
                        .font(.designLabel).foregroundStyle(Color.designPrimary.opacity(0.8))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    ForEach(pendingLendingTransactions) { item in
                        Button {
                            if selectedLendingIDs.contains(item.id) { selectedLendingIDs.remove(item.id) }
                            else { selectedLendingIDs.insert(item.id) }
                        } label: {
                            HStack {
                                Image(systemName: selectedLendingIDs.contains(item.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selectedLendingIDs.contains(item.id) ? Color.designPrimaryFixedDim : Color.designOnSurfaceVariant)
                                VStack(alignment: .leading) {
                                    Text(item.lendingDirection?.displayName ?? "").font(.designBodySmall)
                                    Text(item.date.formatted(date: .abbreviated, time: .omitted)).font(.designBodyCaption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                CurrencyText(amount: abs(item.amount), currencyCode: item.currencyCode, size: 13, foregroundColor: .secondary)
                            }.padding(8)
                        }.buttonStyle(.plain)
                    }
                    let selectedTotal = pendingLendingTransactions.filter { selectedLendingIDs.contains($0.id) }.reduce(Decimal.zero) { $0 + abs($1.amount) }
                    if !selectedLendingIDs.isEmpty {
                        HStack { Spacer(); Text("已选合计: \(CurrencyFormatter.formatDecimal(amount: selectedTotal, fractionDigits: 2))").font(.designBodySmall).foregroundStyle(Color.designPrimaryFixedDim) }
                    }
                }.padding(12).glassCard(cornerRadius: 14)
            }
        }
    }

    private func directionBtn(_ d: LendingDirection) -> some View {
        let sel = lendingDirection == d
        return Button { lendingDirection = d } label: {
            Label(d.displayName, systemImage: d.systemIcon)
                .font(.designBodySmall.weight(sel ? .bold : .regular))
                .frame(maxWidth: .infinity).frame(height: 36)
                .background(sel ? Color.orange.opacity(0.15) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8)
                    .stroke(sel ? Color.orange.opacity(0.4) : Color.clear, lineWidth: 1))
                .foregroundStyle(sel ? .orange : Color.designOnSurfaceVariant)
        }.buttonStyle(.plain)
        .disabled(editing != nil)
    }

    // MARK: - Recent Picker Row

    private func saveRecentMac(_ id: String, _ key: String) {
        var ids = UserDefaults.standard.stringArray(forKey: key) ?? []
        ids.removeAll { $0 == id }; ids.insert(id, at: 0)
        UserDefaults.standard.set(Array(ids.prefix(8)), forKey: key)
    }

    private func topRecentMac<T: Identifiable>(_ items: [T], key: String, selected: T?) -> [T] {
        let ids = UserDefaults.standard.stringArray(forKey: key) ?? []
        var result: [T] = []
        if let s = selected { result.append(s) }
        for idStr in ids {
            guard result.count < 5 else { break }
            if let item = items.first(where: { "\($0.id)" == idStr }),
               (selected as? any Identifiable)?.id as? AnyHashable != item.id as? AnyHashable {
                result.append(item)
            }
        }
        return result
    }

    private func recentPickerRow<T: Identifiable>(
        label: String, items: [T], icon: @escaping (T) -> String, name: @escaping (T) -> String,
        key: String, selected: T?, onSelect: @escaping (T) -> Void, onMore: @escaping () -> Void
    ) -> some View {
        let recents = topRecentMac(items, key: key, selected: selected)
        return VStack(spacing: 8) {
            HStack {
                Text(label).font(.designLabel).foregroundStyle(Color.designPrimary.opacity(0.8))
                Spacer()
                Button { onMore() } label: {
                    HStack(spacing: 2) { Text("更多").font(.designLabel); Image(systemName: "chevron.right") }
                        .font(.designLabel).foregroundStyle(Color.designAccentGreen)
                }.buttonStyle(.plain)
            }
            HStack(spacing: 8) {
                ForEach(Array(recents.prefix(5).enumerated()), id: \.offset) { _, item in
                    let isSel = (selected as? any Identifiable)?.id as? AnyHashable == item.id as? AnyHashable
                    Button { onSelect(item) } label: {
                        VStack(spacing: 4) {
                            Image(systemName: icon(item)).font(.system(size: 14))
                                .foregroundStyle(isSel ? Color.designPrimaryContainer : Color.designOnSurfaceVariant)
                            Text(name(item)).font(.designBodyCaption).lineLimit(1)
                                .foregroundStyle(isSel ? Color.designPrimaryContainer : Color.designOnSurfaceVariant)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 8)
                        .glassCard(cornerRadius: 10)
                        .opacity(isSel ? 1 : 0.5)
                    }.buttonStyle(.plain)
                }
            }
        }.padding(12).glassCard(cornerRadius: 14)
    }

    // MARK: - Picker Sheet

    @ViewBuilder
    private func pickerContent(for sheet: MacSheetPicker) -> some View {
        switch sheet {
        case .account:
            MacPickerList(title: "选择账户", items: accounts, icon: { $0.iconName ?? "creditcard" }, label: { $0.name }, color: { Color(hex: $0.colorHex ?? "#007AFF") }, key: "mac_account", selection: $selectedAccount)
        case .toAccount:
            MacPickerList(title: "转入账户", items: accounts.filter { $0.id != selectedAccount?.id }, icon: { $0.iconName ?? "creditcard" }, label: { $0.name }, color: { Color(hex: $0.colorHex ?? "#007AFF") }, key: "mac_toAccount", selection: $selectedToAccount)
        case .category:
            MacPickerList(title: "选择分类", items: categories, icon: { $0.iconName }, label: { ($0.children?.count ?? 0) > 0 ? "\($0.name) · 含\($0.children?.count ?? 0)项" : $0.name }, color: { Color(hex: $0.colorHex) }, key: "mac_category", selection: $selectedCategory, indent: { var d = 0; var p = $0.parent; while p != nil { d += 1; p = p?.parent }; return d })
        case .member:
            MacPickerList(title: "选择成员", items: members, icon: { $0.avatar }, label: { $0.name }, color: { _ in .secondary }, key: "mac_member", selection: $selectedMember)
        case .merchant:
            MacPickerList(title: "选择商家", items: merchants, icon: { _ in "bag" }, label: { $0.name }, color: { _ in .secondary }, key: "mac_merchant", selection: $selectedMerchant)
        case .project:
            MacPickerList(title: "选择项目", items: projects, icon: { _ in "folder" }, label: { $0.name }, color: { _ in .secondary }, key: "mac_project", selection: $selectedProject)
        case .template:
            MacPickerList(title: "选择模板", items: templates, icon: { _ in "doc.text" }, label: { $0.name }, color: { _ in .secondary }, key: "mac_template", selection: Binding(get: { nil }, set: { if let t = $0 { applyTemplate(t) } }))
        case .template:
            SearchablePickerView(title: "选择模板", items: templates, itemLabel: { $0.name }, itemIcon: { _ in "doc.text" }, recentKey: "mac_template", selection: Binding(get: { nil }, set: { if let t = $0 { applyTemplate(t) } }))
        }
    }

    // MARK: - Data

    private func currencyCode() -> String { appContainer.currentLedger?.defaultCurrencyCode ?? "CNY" }

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

    private func signingAmount() -> Decimal {
        signedAmount(amount: amount, type: type, direction: type == .lending ? lendingDirection : nil)
    }

    private func save() {
        guard let ledger = appContainer.currentLedger, amount != 0 else { return }
        if isSplit { guard splitTotal == amount else { errorMessage = "拆分合计与总额不一致"; return } }
        if let existing = editing {
            existing.type = type
            existing.amount = signingAmount()
            existing.note = note.isEmpty ? nil : note
            existing.date = date
            existing.account = selectedAccount
            existing.toAccount = selectedToAccount
            existing.category = selectedCategory
            existing.member = selectedMember
            existing.merchant = selectedMerchant
            existing.project = selectedProject
            if type == .lending { existing.lendingDirection = lendingDirection }
            do { try appContainer.transactionService.updateTransaction(existing, context: modelContext); isEditing = false }
            catch { errorMessage = error.localizedDescription }
        } else {
            let signed = signingAmount()
            if isSplit {
                let parent = Transaction(type: .expense, amount: signed, note: note.isEmpty ? nil : note,
                    date: date, account: selectedAccount, isSplitParent: true, context: modelContext)
                if isReimbursable { parent.reimbursementStatus = .pending }
                parent.ledger = ledger
                for item in splitItems {
                    let child = Transaction(type: .expense, amount: -abs(item.amount), note: item.note.isEmpty ? nil : item.note,
                        date: date, account: selectedAccount, category: item.category, member: item.member,
                        merchant: item.merchant, project: item.project, parentTransaction: parent, context: modelContext)
                    child.ledger = ledger
                }
                try? modelContext.save()
                NotificationCenter.default.post(name: .transactionDidChange, object: nil)
                dismiss()
            } else {
                let tx = Transaction(type: type, amount: signed, currencyCode: activeCurrency, note: note.isEmpty ? nil : note,
                    date: date, account: selectedAccount, toAccount: selectedToAccount,
                    category: selectedCategory, member: selectedMember,
                    merchant: selectedMerchant, project: selectedProject, context: modelContext)
                if activeCurrency != currencyCode(), let rate = exchangeRate { tx.exchangeRate = NSDecimalNumber(decimal: rate).doubleValue; tx.convertedAmount = convertedAmount }
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
        for exp in pendingExpenses.filter({ selectedExpenseIDs.contains($0.id) }) {
            exp.reimbursementStatus = .reimbursed; exp.reimbursedById = txID
        }
        try modelContext.save()
    }

    private func loadPendingLendingTx() {
        guard type == .lending, let ledger = appContainer.currentLedger else { return }
        let all = (try? appContainer.transactionService.fetchTransactions(for: ledger, context: modelContext, filters: nil)) ?? []
        switch lendingDirection {
        case .collect:
            pendingLendingTransactions = all.filter { $0.lendingDirection == .lendOut && $0.lendingStatus == .pending && $0.toAccount?.id == selectedAccount?.id }
        case .repay:
            pendingLendingTransactions = all.filter { $0.lendingDirection == .borrowIn && $0.lendingStatus == .pending && $0.account?.id == selectedToAccount?.id }
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

// MARK: - macOS 27 兼容桥接

/// `.confirmationDialog(item:)` 需要 macOS 27，旧系统回退 `.alert`
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

// MARK: - macOS 原生 popover 选择器

struct MacPickerList<T: Identifiable & Hashable>: View {
    let title: String; let items: [T]; let icon: (T) -> String; let label: (T) -> String
    let color: (T) -> Color; let key: String; @Binding var selection: T?; var indent: ((T) -> Int)? = nil
    @State private var searchText = ""; @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            Text(title).font(.designHeadlineMedium).padding(.top, 12).padding(.bottom, 8)
            List {
                Button { selection = nil; dismiss() } label: {
                    Label("清除选择", systemImage: "xmark.circle").foregroundStyle(.secondary)
                }
                ForEach(filteredItems, id: \.self) { item in
                    Button {
                        selection = item
                        var ids = UserDefaults.standard.stringArray(forKey: key) ?? []
                        ids.removeAll { $0 == "\(item.id)" }; ids.insert("\(item.id)", at: 0)
                        UserDefaults.standard.set(Array(ids.prefix(8)), forKey: key)
                        dismiss()
                    } label: {
                        HStack {
                            Image(systemName: icon(item)).foregroundStyle(color(item)).frame(width: 24)
                            Text(label(item)); Spacer()
                            if selection?.hashValue == item.hashValue {
                                Image(systemName: "checkmark").foregroundStyle(Color.designPrimaryContainer)
                            }
                        }.padding(.leading, CGFloat(indent?(item) ?? 0) * 20)
                    }.buttonStyle(.plain)
                }
            }.searchable(text: $searchText, prompt: "搜索")
        }.frame(width: 320, height: 420)
    }

    private var filteredItems: [T] {
        searchText.isEmpty ? items : items.filter { label($0).localizedCaseInsensitiveContains(searchText) }
    }
}
