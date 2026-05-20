import SwiftUI
import SwiftData
import PhotosUI

enum PickerSheetType: Identifiable {
    case account, toAccount, category, member, merchant, project, template
    var id: Self { self }
}

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
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appContainer: AppContainer

    let editing: Transaction?

    @State private var type: TransactionType = .expense
    @State private var amount: Decimal = 0
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
    @State private var pickerSheet: PickerSheetType?
    @State private var selectedPickerItems: [PhotosPickerItem] = []
    @State private var photoDataList: [Data] = []
    @State private var selectedPhotoItem: PhotoItem?

    // Reimbursement
    @State private var isReimbursable: Bool = false
    @State private var pendingExpenses: [Transaction] = []
    @State private var selectedExpenseIDs: Set<UUID> = []
    @State private var showReimbursementSection: Bool = false

    // Lending
    @State private var lendingDirection: LendingDirection = .lendOut
    @State private var pendingLendingTransactions: [Transaction] = []
    @State private var selectedLendingIDs: Set<UUID> = []
    @State private var showLendingSettlementSection: Bool = false

    // Split
    @State private var isSplit = false
    @State private var splitItems: [SplitItemDraft] = []

    // Exchange rate
    @State private var exchangeRate: Decimal?
    @State private var isFetchingRate = false
    @State private var selectedCurrencyCode: String = "CNY"

    private let currencies: [String] = ["CNY", "USD", "EUR", "JPY", "GBP", "HKD", "AUD", "CAD", "KRW", "TWD", "SGD", "CHF", "NZD", "THB", "MYR", "INR"]

    init(editing: Transaction? = nil, prefillType: TransactionType? = nil, prefillExpenseIDs: [UUID] = []) {
        self.editing = editing
        if let t = prefillType {
            _type = State(initialValue: t)
        }
        if !prefillExpenseIDs.isEmpty {
            _selectedExpenseIDs = State(initialValue: Set(prefillExpenseIDs))
            _showReimbursementSection = State(initialValue: true)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                // Template quick-pick at top
                if !templates.isEmpty {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("模板")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .textCase(.uppercase)
                                Spacer()
                                Button { openPicker(.template) } label: {
                                    HStack(spacing: 2) {
                                        Text("全部")
                                        Image(systemName: "chevron.right")
                                    }
                                    .font(.designBodySmall)
                                }
                            }
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(templates.prefix(5)) { template in
                                        templateChip(template)
                                    }
                                }
                            }
                        }
                    }
                }

                Section {
                    Picker("类型", selection: $type) {
                        ForEach([TransactionType.expense, .income, .transfer, .lending, .adjustment], id: \.self) { t in
                            Label(t.displayName, systemImage: t.systemIcon).tag(t)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("金额") {
                    HStack {
                        Text(CurrencyFormatter.currencySymbol(for: selectedCurrencyCode))
                            .foregroundStyle(.secondary)
                        TextField("0.00", value: $amount, format: .number)
                            .keyboardType(.decimalPad)
                            .font(.title2)
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
                            Text(selectedCurrencyCode)
                                .font(.designBodySmall)
                                .foregroundStyle(Color.designPrimaryContainer)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.blue.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    }
                    if type == .expense {
                        Toggle("拆分记账", isOn: $isSplit)
                    }
                }

                Section("账户") {
                    if accounts.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("暂无账户").foregroundStyle(.secondary)
                            NavigationLink("去添加账户") {
                                AddEditAccountView()
                            }
                        }
                    } else {
                        Button { openPicker(.account) } label: {
                            pickerRow(
                                label: (type == .transfer || type == .lending) ? "转出账户" : "账户",
                                value: selectedAccount?.name
                            )
                        }
                        if type == .transfer || type == .lending {
                            Button { openPicker(.toAccount) } label: {
                                pickerRow(label: "转入账户", value: selectedToAccount?.name)
                            }
                        }
                    }
                }

                if needsExchangeRate {
                    Section {
                        HStack {
                            Text("汇率")
                            Spacer()
                            if isFetchingRate {
                                ProgressView()
                            } else if let rate = exchangeRate {
                                Text("1 \(selectedCurrencyCode) = \(rate.formatted(.number.precision(.fractionLength(4)))) \(ledgerCurrencyCode)")
                                    .foregroundStyle(.secondary)
                            } else {
                                Button("获取汇率") { fetchExchangeRate() }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                            }
                        }
                        if let converted = convertedAmountPreview {
                            HStack {
                                Text("换算金额")
                                Spacer()
                                CurrencyText(amount: converted, currencyCode: ledgerCurrencyCode, size: 17, foregroundColor: .blue)
                            }
                        }
                    } header: {
                        Text("跨币种换算")
                    } footer: {
                        Text("账户币种(\(selectedCurrencyCode))与账本默认币种(\(ledgerCurrencyCode))不同，将按汇率换算")
                    }
                }

                if isSplit && type == .expense {
                    Section("拆分明细") {
                        ForEach(splitItems) { item in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("¥").foregroundStyle(.secondary)
                                    TextField("0.00", value: splitAmountBinding(for: item.id), format: .number)
                                        .keyboardType(.decimalPad)
                                        .font(.designBodyMedium)
                                    Spacer()
                                    Button {
                                        splitItems.removeAll { $0.id == item.id }
                                    } label: {
                                        Image(systemName: "minus.circle.fill")
                                            .foregroundStyle(.red)
                                    }
                                }
                                Menu {
                                    ForEach(categories) { cat in
                                        Button {
                                            if let idx = splitItems.firstIndex(where: { $0.id == item.id }) {
                                                splitItems[idx].category = cat
                                            }
                                        } label: {
                                            Label(cat.name, systemImage: cat.iconName)
                                        }
                                    }
                                } label: {
                                    pickerRow(label: "分类", value: item.category?.name)
                                }
                                Menu {
                                    ForEach(members) { m in
                                        Button {
                                            if let idx = splitItems.firstIndex(where: { $0.id == item.id }) {
                                                splitItems[idx].member = m
                                            }
                                        } label: {
                                            Label(m.name, systemImage: m.avatar)
                                        }
                                    }
                                } label: {
                                    pickerRow(label: "成员", value: item.member?.name)
                                }
                                Menu {
                                    ForEach(merchants) { m in
                                        Button {
                                            if let idx = splitItems.firstIndex(where: { $0.id == item.id }) {
                                                splitItems[idx].merchant = m
                                            }
                                        } label: {
                                            Label(m.name, systemImage: "bag")
                                        }
                                    }
                                } label: {
                                    pickerRow(label: "商家", value: item.merchant?.name)
                                }
                                Menu {
                                    ForEach(projects) { p in
                                        Button {
                                            if let idx = splitItems.firstIndex(where: { $0.id == item.id }) {
                                                splitItems[idx].project = p
                                            }
                                        } label: {
                                            Label(p.name, systemImage: "folder")
                                        }
                                    }
                                } label: {
                                    pickerRow(label: "项目", value: item.project?.name)
                                }
                            }
                        }
                        Button {
                            let remaining = amount - splitTotal
                            splitItems.append(SplitItemDraft(amount: remaining > 0 ? remaining : 0))
                        } label: {
                            Label("添加子项", systemImage: "plus").font(.designBodySmall)
                        }
                        HStack {
                            Spacer()
                            Text(splitTotalText)
                                .font(.designBodySmall)
                                .foregroundStyle(splitTotal == amount ? .green : .red)
                                .fontWeight(.medium)
                        }
                    }
                }

                if type == .lending {
                    Section("借贷方向") {
                        Picker("方向", selection: $lendingDirection) {
                            ForEach(LendingDirection.allCases, id: \.self) { d in
                                Label(d.displayName, systemImage: d.systemIcon).tag(d)
                            }
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: lendingDirection) { _, _ in
                            loadPendingLendingTransactions()
                        }
                    }
                }

                if type == .expense {
                    Section {
                        Toggle("可报销", isOn: $isReimbursable)
                    }
                }

                if !isSplit && type != .transfer && type != .lending {
                    Section("分类") {
                        Button { openPicker(.category) } label: {
                            pickerRow(label: "分类", value: selectedCategory?.name)
                        }
                    }
                }

                if !isSplit && type != .transfer && type != .lending {
                    Section("更多信息") {
                        Button { openPicker(.member) } label: {
                            pickerRow(label: "成员", value: selectedMember?.name)
                        }
                        Button { openPicker(.merchant) } label: {
                            pickerRow(label: "商家", value: selectedMerchant?.name)
                        }
                        Button { openPicker(.project) } label: {
                            pickerRow(label: "项目", value: selectedProject?.name)
                        }
                    }
                }

                if (lendingDirection == .collect || lendingDirection == .repay) && !pendingLendingTransactions.isEmpty {
                    Section {
                        DisclosureGroup(isExpanded: $showLendingSettlementSection) {
                            ForEach(pendingLendingTransactions) { item in
                                HStack {
                                    Image(systemName: selectedLendingIDs.contains(item.id)
                                          ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(selectedLendingIDs.contains(item.id) ? .blue : .secondary)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(LocalizedStringKey(item.account?.name ?? ""))
                                            .font(.designBodyMedium)
                                        Text(displayLabelForLending(item))
                                            .font(.designBodySmall)
                                            .foregroundStyle(.secondary)
                                        Text(item.date.formatted(date: .abbreviated, time: .omitted))
                                            .font(.designBodySmall)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    CurrencyText(amount: abs(item.amount), currencyCode: item.currencyCode, size: 17)
                                }
                                .contentShape(Rectangle())
                                .onTapGesture { toggleLending(item.id) }
                            }
                        } label: {
                            HStack {
                                Text(lendingDirection == .collect ? "关联待收款" : "关联待付款")
                                Spacer()
                                if !selectedLendingIDs.isEmpty {
                                    Text("\(selectedLendingIDs.count)笔")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }

                    if !selectedLendingIDs.isEmpty {
                        Section {
                            HStack {
                                Text("已选合计")
                                Spacer()
                                CurrencyText(amount: selectedLendingTotal, currencyCode: appContainer.currentLedger?.defaultCurrencyCode ?? "CNY", size: 17, foregroundColor: .secondary)
                            }
                        }
                    }
                }

                if type == .income && !pendingExpenses.isEmpty {
                    Section {
                        DisclosureGroup(isExpanded: $showReimbursementSection) {
                            ForEach(pendingExpenses) { expense in
                                HStack {
                                    Image(systemName: selectedExpenseIDs.contains(expense.id)
                                          ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(selectedExpenseIDs.contains(expense.id) ? .blue : .secondary)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(LocalizedStringKey(expense.category?.name ?? ""))
                                            .font(.designBodyMedium)
                                        Text(expense.date.formatted(date: .abbreviated, time: .omitted))
                                            .font(.designBodySmall)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    CurrencyText(amount: abs(expense.amount), currencyCode: expense.currencyCode, size: 17)
                                }
                                .contentShape(Rectangle())
                                .onTapGesture { toggleExpense(expense.id) }
                            }
                        } label: {
                            HStack {
                                Text("关联待报销")
                                Spacer()
                                if !selectedExpenseIDs.isEmpty {
                                    Text("\(selectedExpenseIDs.count)笔")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }

                    if !selectedExpenseIDs.isEmpty {
                        Section {
                            HStack {
                                Text("已选合计")
                                Spacer()
                                CurrencyText(amount: selectedReimbursementTotal, currencyCode: appContainer.currentLedger?.defaultCurrencyCode ?? "CNY", size: 17, foregroundColor: .secondary)
                            }
                        }
                    }
                }

                Section("详情") {
                    TextField("备注", text: $note)
                    DatePicker("日期", selection: $date, displayedComponents: [.date, .hourAndMinute])
                }

                Section("照片附件") {
                    photoGrid
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

                if editing != nil {
                    Section {
                        Button(role: .destructive) {
                            showDeleteAlert = true
                        } label: {
                            Label("删除此交易", systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle(editing != nil ? "编辑交易" : "记一笔")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(!canSave)
                }
            }
            .task { loadData(); prefillEditing() }
            .onChange(of: pickerSheet) { _, newValue in
                if newValue != nil { loadData() }
            }
            .onChange(of: type) { _, _ in loadCategories(); loadPendingExpenses(); loadPendingLendingTransactions() }
            .onChange(of: selectedAccount) { _, _ in
                selectedLendingIDs = []
                loadPendingLendingTransactions()
                if editing == nil {
                    selectedCurrencyCode = selectedAccount?.currencyCode ?? "CNY"
                }
                exchangeRate = nil
                if needsExchangeRate { fetchExchangeRate() }
            }
            .onChange(of: selectedToAccount) { _, _ in selectedLendingIDs = []; loadPendingLendingTransactions() }
            .onChange(of: selectedExpenseIDs) { _, _ in
                guard !selectedExpenseIDs.isEmpty, editing == nil else { return }
                amount = selectedReimbursementTotal
            }
            .alert("确认删除", isPresented: $showDeleteAlert) {
                Button("取消", role: .cancel) {}
                Button("删除", role: .destructive) { delete() }
            } message: {
                Text("此操作不可撤销，确定要删除此交易吗？")
            }
            .sheet(item: $pickerSheet) { sheet in
                pickerContent(for: sheet)
            }
            .sheet(item: $selectedPhotoItem) { item in
                FullScreenPhotoView(data: item.data)
            }
        }
    }

    private func templateChip(_ template: TransactionTemplate) -> some View {
        Button {
            applyTemplate(template)
        } label: {
            VStack(spacing: 2) {
                Image(systemName: template.category?.iconName ?? template.type.systemIcon)
                    .font(.designBodyMedium)
                Text(LocalizedStringKey(template.name))
                    .font(.designBodySmall)
                    .lineLimit(1)
            }
            .frame(width: 56, height: 52)
            .background(.background.secondary)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func pickerContent(for sheet: PickerSheetType) -> some View {
        switch sheet {
        case .account:
            SearchablePickerView(
                title: type == .transfer ? "转出账户" : "选择账户",
                items: accounts,
                itemLabel: { $0.name },
                itemIcon: { $0.iconName ?? "creditcard" },
                itemColor: { Color(hex: $0.colorHex ?? "#007AFF") },
                recentKey: "recent_account",
                selection: $selectedAccount
            )
        case .toAccount:
            SearchablePickerView(
                title: "转入账户",
                items: accounts.filter { $0.id != selectedAccount?.id },
                itemLabel: { $0.name },
                itemIcon: { $0.iconName ?? "creditcard" },
                itemColor: { Color(hex: $0.colorHex ?? "#007AFF") },
                recentKey: "recent_toaccount",
                selection: $selectedToAccount
            )
        case .category:
            SearchablePickerView(
                title: "选择分类",
                items: categories,
                itemLabel: { $0.name },
                itemIcon: { $0.iconName },
                itemColor: { Color(hex: $0.colorHex) },
                recentKey: "recent_category",
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
                                    .frame(width: 72, height: 72)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                        .buttonStyle(.plain)
                        Button {
                            photoDataList.remove(at: index)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.designBodySmall)
                                .foregroundStyle(.white)
                                .background(Circle().fill(.black.opacity(0.6)))
                        }
                        .offset(x: 6, y: -6)
                    }
                }
                PhotosPicker(selection: $selectedPickerItems, maxSelectionCount: 5, matching: .images) {
                    VStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.title2)
                        Text("添加")
                            .font(.designBodySmall)
                    }
                    .frame(width: 72, height: 72)
                    .background(.background.tertiary)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .disabled(photoDataList.count >= 5)
            }
        }
    }

    private func pickerRow(label: String, value: String?) -> some View {
        HStack {
            Text(label)
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
        members = (try? appContainer.memberService.fetchMembers(for: ledger, context: modelContext)) ?? []
        merchants = (try? appContainer.merchantService.fetchMerchants(for: ledger, context: modelContext)) ?? []
        projects = (try? appContainer.projectService.fetchProjects(for: ledger, context: modelContext)) ?? []
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
    }

    private func save() {
        guard let ledger = appContainer.currentLedger else { return }
        do {
            if let existing = editing {
                try updateExisting(existing, ledger: ledger)
            } else if type == .transfer, let from = selectedAccount, let to = selectedToAccount {
                _ = try appContainer.transactionService.createTransfer(
                    from: from, to: to, amount: amount, date: date,
                    note: note.isEmpty ? nil : note, ledger: ledger, context: modelContext
                )
            } else if isSplit && !splitItems.isEmpty && type == .expense {
                let signedAmount: Decimal = -abs(amount)
                let parent = Transaction(
                    type: .expense, amount: signedAmount, note: note.isEmpty ? nil : note,
                    date: date, account: selectedAccount,
                    isSplitParent: true
                )
                parent.ledger = ledger
                if isReimbursable { parent.reimbursementStatus = .pending }
                if !photoDataList.isEmpty {
                    parent.photoURLs = PhotoStorage.save(photoDataList, transactionId: parent.id)
                }
                modelContext.insert(parent)

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
                    merchant: selectedMerchant, project: selectedProject
                )
                if type == .expense, isReimbursable {
                    transaction.reimbursementStatus = .pending
                }
                if type == .lending {
                    transaction.lendingDirection = lendingDirection
                    if lendingDirection == .lendOut || lendingDirection == .borrowIn {
                        transaction.lendingStatus = .pending
                    }
                    if (lendingDirection == .collect || lendingDirection == .repay) && !selectedLendingIDs.isEmpty {
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
            dismiss()
        } catch {
            print("Save failed: \(error)")
        }
    }

    private func splitAmountBinding(for itemID: UUID) -> Binding<Decimal> {
        Binding(
            get: { splitItems.first(where: { $0.id == itemID })?.amount ?? 0 },
            set: { newValue in
                if let i = splitItems.firstIndex(where: { $0.id == itemID }) {
                    splitItems[i].amount = newValue
                }
            }
        )
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
                parentTransaction: parent
            )
            child.ledger = ledger
            modelContext.insert(child)
        }
    }

    private var splitTotal: Decimal {
        splitItems.reduce(Decimal.zero) { $0 + $1.amount }
    }

    private var splitTotalText: String {
        "合计 ¥\(splitTotal.formatted(.number.precision(.fractionLength(2)))) / ¥\(amount.formatted(.number.precision(.fractionLength(2))))"
    }

    private var ledgerCurrencyCode: String {
        appContainer.currentLedger?.defaultCurrencyCode ?? "CNY"
    }

    private var needsExchangeRate: Bool {
        selectedCurrencyCode != ledgerCurrencyCode
    }

    private var convertedAmountPreview: Decimal? {
        guard let rate = exchangeRate else { return nil }
        let signed = signingAmount()
        return signed * rate
    }

    private func fetchExchangeRate() {
        guard let service = appContainer.exchangeRateService else { return }
        isFetchingRate = true
        Task {
            defer { isFetchingRate = false }
            if let rate = try? await service.fetchRate(from: selectedCurrencyCode, to: ledgerCurrencyCode) {
                exchangeRate = rate.rate
            }
        }
    }

    private func applyCurrency(to t: Transaction) {
        t.currencyCode = selectedCurrencyCode
        if selectedCurrencyCode != ledgerCurrencyCode, let rate = exchangeRate {
            t.exchangeRate = rate
            t.convertedAmount = t.amount * rate
        }
    }

    private func currencyName(_ code: String) -> String {
        switch code {
        case "CNY": return "人民币"
        case "USD": return "美元"
        case "EUR": return "欧元"
        case "JPY": return "日元"
        case "GBP": return "英镑"
        case "HKD": return "港币"
        case "AUD": return "澳元"
        case "CAD": return "加元"
        case "KRW": return "韩元"
        case "TWD": return "新台币"
        case "SGD": return "新加坡元"
        case "CHF": return "瑞士法郎"
        case "NZD": return "新西兰元"
        case "THB": return "泰铢"
        case "MYR": return "马币"
        case "INR": return "印度卢比"
        default: return code
        }
    }

    private func signingAmount() -> Decimal {
        switch type {
        case .expense: return -abs(amount)
        case .lending: return lendingSign
        default: return abs(amount)
        }
    }

    private var lendingSign: Decimal {
        switch lendingDirection {
        case .lendOut, .repay: return -abs(amount)
        case .borrowIn, .collect: return abs(amount)
        }
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
                $0.lendingDirection == .lendOut && $0.lendingStatus == .pending && $0.toAccount?.id == accountID
            }
        case .repay:
            guard let toAccountID = selectedToAccount?.id else {
                pendingLendingTransactions = []
                return
            }
            pendingLendingTransactions = all.filter {
                $0.lendingDirection == .borrowIn && $0.lendingStatus == .pending && $0.account?.id == toAccountID
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
            .reduce(0) { $0 + abs($1.amount) }
    }

    private func displayLabelForLending(_ t: Transaction) -> String {
        if let note = t.note, !note.isEmpty { return note }
        if let cat = t.category { return NSLocalizedString(cat.name, comment: "") }
        return t.date.formatted(date: .numeric, time: .omitted)
    }

    private func updateExisting(_ original: Transaction, ledger: Ledger) throws {
        let id = original.id
        var descriptor = FetchDescriptor<Transaction>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        guard let t = try? modelContext.fetch(descriptor).first else {
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

        if isSplit && type == .expense {
            t.isSplitParent = true
            createSplitChildren(parent: t, ledger: ledger)
        } else {
            t.isSplitParent = false
        }

        if t.type == .expense {
            t.reimbursementStatus = isReimbursable ? .pending : .none
        }
        if t.type == .lending {
            t.lendingDirection = lendingDirection
            if lendingDirection == .lendOut || lendingDirection == .borrowIn {
                t.lendingStatus = .pending
            }
            if (lendingDirection == .collect || lendingDirection == .repay) && !selectedLendingIDs.isEmpty {
                try linkSettledLendingTransactions(to: t.id)
            }
        }
        if t.type == .income, !selectedExpenseIDs.isEmpty {
            try linkReimbursedExpenses(to: t.id)
        }
        if let oldPaths = t.photoURLs, !oldPaths.isEmpty {
            PhotoStorage.delete(paths: oldPaths)
        }
        t.photoURLs = photoDataList.isEmpty ? nil : PhotoStorage.save(photoDataList, transactionId: t.id)
        t.modifiedAt = Date()
        try modelContext.save()
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
            .reduce(0) { $0 + abs($1.amount) }
    }

    private func loadPendingExpenses() {
        guard let ledger = appContainer.currentLedger, type == .income else {
            pendingExpenses = []
            return
        }
        let all = (try? appContainer.transactionService.fetchTransactions(for: ledger, context: modelContext, filters: nil)) ?? []
        pendingExpenses = all.filter { $0.type == .expense && $0.reimbursementStatus == .pending }
    }

    private func linkReimbursedExpenses(to incomeId: UUID) throws {
        for expenseID in selectedExpenseIDs {
            var descriptor = FetchDescriptor<Transaction>(predicate: #Predicate { $0.id == expenseID })
            descriptor.fetchLimit = 1
            guard let expense = try? modelContext.fetch(descriptor).first else { continue }
            expense.reimbursementStatus = .reimbursed
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
            var descriptor = FetchDescriptor<Transaction>(predicate: #Predicate { $0.id == lendingID })
            descriptor.fetchLimit = 1
            guard let item = try? modelContext.fetch(descriptor).first else { continue }
            let debtAmount = abs(item.amount)
            let alreadyPaid = item.settledAmount ?? 0
            let stillOwed = debtAmount - alreadyPaid
            if remaining >= stillOwed {
                item.settledAmount = debtAmount
                item.lendingStatus = .settled
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
        try? appContainer.transactionService.deleteTransaction(t, context: modelContext)
        dismiss()
    }
}
