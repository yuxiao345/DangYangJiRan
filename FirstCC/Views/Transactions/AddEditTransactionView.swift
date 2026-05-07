import SwiftUI
import SwiftData
import PhotosUI

enum PickerSheetType: Identifiable {
    case account, toAccount, category, member, merchant, project, template
    var id: Self { self }
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
                                    .font(.caption)
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
                        Text("¥").foregroundStyle(.secondary)
                        TextField("0.00", value: $amount, format: .number)
                            .keyboardType(.decimalPad)
                            .font(.title2)
                    }
                }

                if type == .expense {
                    Section {
                        Toggle("可报销", isOn: $isReimbursable)
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

                if type != .transfer && type != .lending {
                    Section("分类") {
                        Button { openPicker(.category) } label: {
                            pickerRow(label: "分类", value: selectedCategory?.name)
                        }
                    }
                }

                if type != .transfer && type != .lending {
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
                                            .font(.body)
                                        Text(expense.date.formatted(date: .abbreviated, time: .omitted))
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    CurrencyText(amount: abs(expense.amount), currencyCode: expense.currencyCode, font: .body)
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
                                CurrencyText(amount: selectedReimbursementTotal, currencyCode: appContainer.currentLedger?.defaultCurrencyCode ?? "CNY", font: .body, foregroundColor: .secondary)
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
            .onChange(of: type) { _, _ in loadCategories(); loadPendingExpenses() }
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
                    .font(.subheadline)
                Text(LocalizedStringKey(template.name))
                    .font(.caption2)
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
                                .font(.caption)
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
                            .font(.caption2)
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
                .foregroundStyle(.primary)
            Spacer()
            if let value {
                Text(LocalizedStringKey(value))
                    .foregroundStyle(.secondary)
            } else {
                Text(LocalizedStringKey("选择\(label)"))
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
    }

    private var canSave: Bool {
        amount != 0 && selectedAccount != nil && (type != .transfer || selectedToAccount != nil)
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
        selectedCategory = t.category
        selectedMember = t.member
        selectedMerchant = t.merchant
        selectedProject = t.project
        isReimbursable = t.isReimbursable
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
                if !photoDataList.isEmpty {
                    transaction.photoURLs = PhotoStorage.save(photoDataList, transactionId: transaction.id)
                }
                if type == .income, !selectedExpenseIDs.isEmpty {
                    try linkReimbursedExpenses(to: transaction.id)
                }
                try appContainer.transactionService.createTransaction(transaction, ledger: ledger, context: modelContext)
            }
            dismiss()
        } catch {
            print("Save failed: \(error)")
        }
    }

    private func signingAmount() -> Decimal {
        switch type {
        case .expense: return -abs(amount)
        case .lending: return selectedToAccount?.type == .lending ? -abs(amount) : abs(amount)
        default: return abs(amount)
        }
    }

    private func updateExisting(_ original: Transaction, ledger: Ledger) throws {
        let id = original.id
        var descriptor = FetchDescriptor<Transaction>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        guard let t = try? modelContext.fetch(descriptor).first else {
            throw NSError(domain: "TransactionEdit", code: 1, userInfo: [NSLocalizedDescriptionKey: "Transaction not found"])
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

        if t.type == .expense {
            t.reimbursementStatus = isReimbursable ? .pending : .none
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

    private func delete() {
        guard let t = editing else { return }
        if let paths = t.photoURLs, !paths.isEmpty {
            PhotoStorage.delete(paths: paths)
        }
        try? appContainer.transactionService.deleteTransaction(t, context: modelContext)
        dismiss()
    }
}
