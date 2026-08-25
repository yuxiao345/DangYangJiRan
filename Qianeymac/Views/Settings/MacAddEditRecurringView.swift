import SwiftUI
@preconcurrency import CoreData

struct MacAddEditRecurringView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var modelContext
    @Environment(AppContainer.self) private var appContainer

    var editing: RecurringRule? = nil
    let ledger: Ledger?

    // Template fields
    @State private var name: String = ""
    @State private var type: TransactionType = .expense
    @State private var amountText: String = ""
    @State private var amount: Decimal = 0
    @State private var note: String = ""
    @State private var selectedAccount: Account?
    @State private var selectedToAccount: Account?
    @State private var selectedCategory: Category?
    @State private var selectedMember: Member?
    @State private var selectedMerchant: Merchant?
    @State private var selectedProject: Project?

    // Recurring fields
    @State private var frequency: RecurringFrequency = .monthly
    @State private var interval: Int = 1
    @State private var startDate: Date = Date.now
    @State private var hasEndDate: Bool = false
    @State private var endDate: Date = Date.now.addingTimeInterval(86400 * 365)

    // Data
    @State private var accounts: [Account] = []
    @State private var categories: [Category] = []
    @State private var members: [Member] = []
    @State private var merchants: [Merchant] = []
    @State private var projects: [Project] = []
    @State private var errorMessage: String?
    @State private var showErrorAlert: Bool = false

    private var isEditing: Bool { editing != nil }

    private var flatCategories: [(Category, String)] {
        let roots = categories.filter { $0.parent == nil }.sorted { $0.sortOrder < $1.sortOrder }
        var result: [(Category, String)] = []
        for root in roots {
            result.append((root, root.name))
            for child in (root.children as? Set<Category> ?? []).sorted(by: { $0.sortOrder < $1.sortOrder }) {
                result.append((child, "    \(child.name)"))
            }
        }
        return result
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                    // Template fields
                    GridRow {
                        Text("名称：").gridColumnAlignment(.trailing)
                        TextField("", text: $name).textFieldStyle(.roundedBorder)
                    }
                    GridRow {
                        Text("类型：")
                        Picker("", selection: $type) {
                            ForEach([TransactionType.expense, .income, .transfer], id: \.self) { t in
                                Text(t.displayName).tag(t)
                            }
                        }
                        .pickerStyle(.menu).labelsHidden()
                        .onChange(of: type) { _, _ in loadCategories() }
                    }
                    GridRow {
                        Text("金额：")
                        TextField("0.00", text: $amountText)
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                            .onChange(of: amountText) { _, v in
                                amountText = v.filter { "0123456789.".contains($0) }
                                amount = Decimal(string: amountText) ?? 0
                            }
                    }
                    GridRow {
                        Text(type == .transfer ? "转出账户：" : "账户：")
                        Picker("", selection: $selectedAccount) {
                            Text("未选择").tag(nil as Account?)
                            ForEach(accounts) { a in Text(a.name).tag(a as Account?) }
                        }
                        .pickerStyle(.menu).labelsHidden()
                    }
                    if type == .transfer {
                        GridRow {
                            Text("转入账户：")
                            Picker("", selection: $selectedToAccount) {
                                Text("未选择").tag(nil as Account?)
                                ForEach(accounts.filter { $0.id != selectedAccount?.id }) { a in
                                    Text(a.name).tag(a as Account?)
                                }
                            }
                            .pickerStyle(.menu).labelsHidden()
                        }
                    }
                    if type != .transfer {
                        GridRow {
                            Text("分类：")
                            Picker("", selection: $selectedCategory) {
                                Text("未选择").tag(nil as Category?)
                                ForEach(flatCategories, id: \.0.id) { cat, label in
                                    Text(label).tag(cat as Category?)
                                }
                            }
                            .pickerStyle(.menu).labelsHidden()
                        }
                    }

                    // Recurring fields
                    GridRow {
                        Text("频率：")
                        Picker("", selection: $frequency) {
                            ForEach(RecurringFrequency.allCases, id: \.self) { f in
                                Text(f.displayName).tag(f)
                            }
                        }
                        .pickerStyle(.menu).labelsHidden()
                    }
                    GridRow {
                        Text("间隔：")
                        HStack(spacing: 8) {
                            Stepper("\(interval)", value: $interval, in: 1...99)
                                .labelsHidden()
                            Text(frequencyDescription)
                                .font(.designBodyCaption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    GridRow {
                        Text("开始日期：")
                        DatePicker("", selection: $startDate, displayedComponents: .date)
                            .labelsHidden()
                    }
                    GridRow {
                        Text("结束日期：")
                        Toggle("截止日期", isOn: $hasEndDate)
                    }
                    if hasEndDate {
                        GridRow {
                            Text("")
                            DatePicker("", selection: $endDate, displayedComponents: .date)
                                .labelsHidden()
                        }
                    }

                    if type != .transfer {
                        GridRow {
                            Text("成员：")
                            Picker("", selection: $selectedMember) {
                                Text("未选择").tag(nil as Member?)
                                ForEach(members) { m in Text(m.name).tag(m as Member?) }
                            }
                            .pickerStyle(.menu).labelsHidden()
                        }
                        GridRow {
                            Text("商家：")
                            Picker("", selection: $selectedMerchant) {
                                Text("未选择").tag(nil as Merchant?)
                                ForEach(merchants) { m in Text(m.name).tag(m as Merchant?) }
                            }
                            .pickerStyle(.menu).labelsHidden()
                        }
                        GridRow {
                            Text("项目：")
                            Picker("", selection: $selectedProject) {
                                Text("未选择").tag(nil as Project?)
                                ForEach(projects) { p in Text(p.name).tag(p as Project?) }
                            }
                            .pickerStyle(.menu).labelsHidden()
                        }
                    }
                    GridRow {
                        Text("备注：")
                        TextField("", text: $note).textFieldStyle(.roundedBorder)
                    }
                }
                .buttonSizing(.flexible)
                .frame(width: 380)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(32)
            .frame(maxWidth: .infinity)
        }
        .designScreen()
        .frame(minWidth: 420, idealWidth: 480, minHeight: 560)
        .navigationTitle(isEditing ? "编辑周期账" : "新建周期账")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") { save() }.disabled(name.isEmpty)
            }
        }
        .alert("保存失败", isPresented: $showErrorAlert) {
        } message: { Text(errorMessage ?? "") }
        .onAppear { loadData(); prefillEditing() }
    }

    private var frequencyDescription: String {
        let base = frequency.displayName
        return interval > 1 ? String(localized: "每\(String(interval))\(frequency.unitName)") : base
    }

    private func loadData() {
        guard let l = ledger ?? appContainer.currentLedger else { return }
        accounts = (try? appContainer.accountService.fetchAccounts(for: l, context: modelContext)) ?? []
        loadCategories()
        members = (try? appContainer.memberService.fetchMembers(for: l, context: modelContext))?.filter(\.isActive) ?? []
        merchants = (try? appContainer.merchantService.fetchMerchants(for: l, context: modelContext))?.filter(\.isActive) ?? []
        projects = (try? appContainer.projectService.fetchProjects(for: l, context: modelContext))?.filter(\.isActive) ?? []
    }

    private func loadCategories() {
        guard let l = ledger ?? appContainer.currentLedger else { return }
        categories = (try? appContainer.categoryService.fetchAllCategories(for: l, type: type, context: modelContext)) ?? []
    }

    private func prefillEditing() {
        guard let rule = editing, let t = rule.template else { return }
        name = t.name
        type = t.type
        amount = t.amount
        amountText = t.amount == 0 ? "" : String(describing: t.amount)
        note = t.note ?? ""
        selectedAccount = t.account
        selectedToAccount = t.toAccount
        selectedCategory = t.category
        selectedMember = t.member
        selectedMerchant = t.merchant
        selectedProject = t.project
        frequency = rule.frequency
        interval = Int(rule.interval)
        startDate = rule.startDate
        if let end = rule.endDate {
            hasEndDate = true
            endDate = end
        }
    }

    private func save() {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        guard let l = ledger ?? editing?.template?.ledger ?? appContainer.currentLedger else { return }

        if let dup = try? appContainer.templateService.findByName(name, ledger: l, context: modelContext),
           dup.id != editing?.template?.id {
            errorMessage = String(localized: "同名周期账「\(name)」已存在"); showErrorAlert = true; return
        }

        let end = hasEndDate ? endDate : nil

        if let rule = editing, let t = rule.template {
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
            try? appContainer.recurringService.setRecurring(
                template: t, frequency: frequency, interval: interval,
                startDate: startDate, endDate: end, context: modelContext
            )
            try? appContainer.recurringService.processAndDeduplicate(context: modelContext)
        } else {
            let template = TransactionTemplate(
                name: name, type: type, amount: amount,
                currencyCode: l.defaultCurrencyCode,
                note: note.isEmpty ? nil : note, sortOrder: 0,
                account: selectedAccount, toAccount: selectedToAccount,
                category: selectedCategory, member: selectedMember,
                merchant: selectedMerchant, project: selectedProject,
                context: modelContext
            )
            try? appContainer.templateService.createTemplate(template, ledger: l, context: modelContext)
            try? appContainer.recurringService.setRecurring(
                template: template, frequency: frequency, interval: interval,
                startDate: startDate, endDate: end, context: modelContext
            )
            try? appContainer.recurringService.processAndDeduplicate(context: modelContext)
        }
        dismiss()
    }
}
