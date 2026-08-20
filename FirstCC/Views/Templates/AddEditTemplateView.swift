import SwiftUI
@preconcurrency import CoreData

enum TemplatePickerSheet: Identifiable {
    case account, toAccount, category, member, merchant, project
    var id: Self { self }
}

struct AddEditTemplateView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var modelContext
    @Environment(AppContainer.self) private var appContainer

    let editing: TransactionTemplate?
    let ledger: Ledger?
    private var effectiveLedger: Ledger? { ledger ?? appContainer.currentLedger }

    @State private var name: String = ""
    @State private var type: TransactionType = .expense
    @State private var amount: Decimal = 0
    @State private var note: String = ""
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
    @State private var pickerSheet: TemplatePickerSheet?
    @State private var errorMessage: String?

    init(editing: TransactionTemplate? = nil, ledger: Ledger? = nil) {
        self.editing = editing
        self.ledger = ledger
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("基本信息") {
                    TextField("模板名称", text: $name)
                    Picker("类型", selection: $type) {
                        ForEach([TransactionType.expense, .income, .transfer], id: \.self) { t in
                            Label(t.displayName, systemImage: t.systemIcon).tag(t)
                        }
                    }
                }

                Section("金额") {
                    NumpadAmountField(amount: $amount)
                }

                Section("账户") {
                    Button { openPicker(.account) } label: {
                        pickerRow(label: type == .transfer ? LocalizedStringKey("转出账户") : LocalizedStringKey("账户"), value: selectedAccount?.name)
                    }
                    if type == .transfer {
                        Button { openPicker(.toAccount) } label: {
                            pickerRow(label: "转入账户", value: selectedToAccount?.name)
                        }
                    }
                }

                if type != .transfer {
                    Section("分类") {
                        Button { openPicker(.category) } label: {
                            pickerRow(label: "分类", value: selectedCategory?.name)
                        }
                        if let cat = selectedCategory, (cat.children?.count ?? 0) > 0 {
                            Text("已选择上级分类「\(cat.name)」，可展开选择更具体的子分类")
                                .font(.caption).foregroundStyle(.orange)
                        }
                    }
                }

                if type != .transfer {
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

                Section("备注") {
                    TextField("备注", text: $note)
                }
            }
            .navigationTitle(editing != nil ? "编辑模板" : "新建模板")
            .navigationBarTitleDisplayMode(.inline)
            .errorAlert("保存失败", message: $errorMessage)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }.disabled(name.isEmpty)
                }
            }
            .task { loadData(); prefillEditing() }
            .onChange(of: type) { _, _ in loadCategories() }
            .onChange(of: pickerSheet) { _, newValue in
                if newValue != nil { loadData() }
            }
            .sheet(item: $pickerSheet) { sheet in
                switch sheet {
                case .account:
                    SearchablePickerView(
                        title: type == .transfer ? "转出账户" : "选择账户",
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
                        title: "转入账户",
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
                }
            }
        }
    }

    private func pickerRow(label: LocalizedStringKey, value: String?) -> some View {
        HStack {
            Text(label).foregroundStyle(Color.designOnSurface)
            Spacer()
            if let value {
                Text(LocalizedStringKey(value)).foregroundStyle(.secondary)
            } else {
                Text(LocalizedStringKey("选择\(label)")).foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
    }

    private func openPicker(_ sheet: TemplatePickerSheet) {
        loadData()
        pickerSheet = sheet
    }

    private func loadData() {
        guard let ledger = effectiveLedger else { return }
        accounts = (try? appContainer.accountService.fetchAccounts(for: ledger, context: modelContext)) ?? []
        loadCategories()
        members = (try? appContainer.memberService.fetchMembers(for: ledger, context: modelContext))?.filter { $0.isActive } ?? []
        merchants = (try? appContainer.merchantService.fetchMerchants(for: ledger, context: modelContext))?.filter { $0.isActive } ?? []
        projects = (try? appContainer.projectService.fetchProjects(for: ledger, context: modelContext))?.filter { $0.isActive } ?? []
    }

    private func loadCategories() {
        guard let ledger = effectiveLedger else { return }
        categories = (try? appContainer.categoryService.fetchCategories(for: ledger, type: type, context: modelContext)) ?? []
    }

    private func prefillEditing() {
        guard let t = editing else { return }
        name = t.name
        type = t.type
        amount = t.amount
        note = t.note ?? ""
        selectedAccount = t.account
        selectedToAccount = t.toAccount
        selectedCategory = t.category
        selectedMember = t.member
        selectedMerchant = t.merchant
        selectedProject = t.project
    }

    private func save() {
        guard let ledger = effectiveLedger else { return }
        if let dup = try? appContainer.templateService.findByName(name, ledger: ledger, context: modelContext),
           dup.id != editing?.id {
            errorMessage = String(localized: "同名模板「\(name)」已存在")
            return
        }
        if let t = editing {
            t.name = name
            t.type = type
            t.amount = amount
            t.note = note.isEmpty ? nil : note
            t.account = selectedAccount
            t.toAccount = selectedToAccount
            t.category = selectedCategory
            t.member = selectedMember
            t.merchant = selectedMerchant
            t.project = selectedProject
            try? appContainer.templateService.updateTemplate(t, context: modelContext)
        } else {
            let template = TransactionTemplate(
                name: name,
                type: type,
                amount: amount,
                note: note.isEmpty ? nil : note,
                account: selectedAccount,
                toAccount: selectedToAccount,
                category: selectedCategory,
                member: selectedMember,
                merchant: selectedMerchant,
                project: selectedProject,
                context: modelContext
            )
            try? appContainer.templateService.createTemplate(template, ledger: ledger, context: modelContext)
        }
        dismiss()
    }
}
