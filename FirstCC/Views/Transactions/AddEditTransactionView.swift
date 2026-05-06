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
    @State private var isLendOut: Bool = true
    @State private var counterparty: String = ""
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

    init(editing: Transaction? = nil) {
        self.editing = editing
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
                                Button { pickerSheet = .template } label: {
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

                if type == .lending {
                    Section {
                        Picker("借贷方向", selection: $isLendOut) {
                            Label("我借出", systemImage: "arrow.up.right").tag(true)
                            Label("我收回/借入", systemImage: "arrow.down.left").tag(false)
                        }
                        TextField("对方（姓名/公司）", text: $counterparty)
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
                        Button { pickerSheet = .account } label: {
                            pickerRow(
                                label: type == .transfer ? "转出账户" : "账户",
                                value: selectedAccount?.name
                            )
                        }
                        if type == .transfer {
                            Button { pickerSheet = .toAccount } label: {
                                pickerRow(label: "转入账户", value: selectedToAccount?.name)
                            }
                        }
                    }
                }

                if type != .transfer && type != .lending {
                    Section("分类") {
                        Button { pickerSheet = .category } label: {
                            pickerRow(label: "分类", value: selectedCategory?.name)
                        }
                    }
                }

                if type != .transfer && type != .lending {
                    Section("更多信息") {
                        Button { pickerSheet = .member } label: {
                            pickerRow(label: "成员", value: selectedMember?.name)
                        }
                        Button { pickerSheet = .merchant } label: {
                            pickerRow(label: "商家", value: selectedMerchant?.name)
                        }
                        Button { pickerSheet = .project } label: {
                            pickerRow(label: "项目", value: selectedProject?.name)
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
            .onAppear { loadData(); prefillEditing() }
            .onChange(of: type) { _, _ in loadCategories() }
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

    private func loadData() {
        guard let ledger = appContainer.currentLedger else { return }
        accounts = (try? appContainer.accountService.fetchAccounts(for: ledger, context: modelContext)) ?? []
        loadCategories()
        members = (try? appContainer.memberService.fetchMembers(for: ledger, context: modelContext)) ?? []
        merchants = (try? appContainer.merchantService.fetchMerchants(for: ledger, context: modelContext)) ?? []
        projects = (try? appContainer.projectService.fetchProjects(for: ledger, context: modelContext)) ?? []
        templates = (try? appContainer.templateService.fetchTemplates(for: ledger, context: modelContext)) ?? []
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
        counterparty = t.counterparty ?? ""
        isLendOut = t.amount < 0
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
        if type == .lending {
            isLendOut = true
        }
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
                if type == .lending {
                    transaction.counterparty = counterparty.isEmpty ? nil : counterparty
                }
                if !photoDataList.isEmpty {
                    transaction.photoURLs = PhotoStorage.save(photoDataList, transactionId: transaction.id)
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
        case .lending: return isLendOut ? -abs(amount) : abs(amount)
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
        t.counterparty = counterparty.isEmpty ? nil : counterparty
        if let oldPaths = t.photoURLs, !oldPaths.isEmpty {
            PhotoStorage.delete(paths: oldPaths)
        }
        t.photoURLs = photoDataList.isEmpty ? nil : PhotoStorage.save(photoDataList, transactionId: t.id)
        t.modifiedAt = Date()
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
