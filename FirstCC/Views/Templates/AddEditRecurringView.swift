import SwiftUI
@preconcurrency import CoreData

enum RecurringPickerSheet: Identifiable {
    case account, toAccount, category, member, merchant, project
    var id: Self { self }
}

struct AddEditRecurringView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var modelContext
    @Environment(AppContainer.self) private var appContainer

    let editingRule: RecurringRule?
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
    @State private var frequency: RecurringFrequency = .monthly
    @State private var interval: Int = 1
    @State private var startDate: Date = Date.now
    @State private var hasEndDate: Bool = false
    @State private var endDate: Date = Date.now.addingTimeInterval(86400 * 365)

    @State private var accounts: [Account] = []
    @State private var categories: [Category] = []
    @State private var members: [Member] = []
    @State private var merchants: [Merchant] = []
    @State private var projects: [Project] = []
    @State private var pickerSheet: RecurringPickerSheet?
    @State private var errorMessage: String?

    init(editing: RecurringRule? = nil, ledger: Ledger? = nil) {
        self.editingRule = editing
        self.ledger = ledger
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("基本信息") {
                    TextField("名称", text: $name)
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
                        pickerRow(label: type == .transfer ? LocalizedStringKey("转出账户") : LocalizedStringKey("付款账户"), value: selectedAccount?.name)
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

                Section {
                    Picker("频率", selection: $frequency) {
                        ForEach(RecurringFrequency.allCases, id: \.self) { f in
                            Text(f.displayName).tag(f)
                        }
                    }
                    Stepper("间隔: \(interval)", value: $interval, in: 1...99)
                        .foregroundStyle(interval > 1 ? .primary : .secondary)
                    DatePickerButton(title: "开始日期", date: $startDate)
                    Toggle("结束日期", isOn: $hasEndDate)
                    if hasEndDate {
                        DatePickerButton(title: "截止日期", date: $endDate)
                    }
                } header: {
                    Text("周期")
                } footer: {
                    Text(frequencyDescription)
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
            .navigationTitle(editingRule != nil ? "编辑周期账" : "新建周期账")
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
                        title: type == .transfer ? "转出账户" : "付款账户",
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

    private var frequencyDescription: String {
        let base = frequency.displayName
        var desc = interval > 1 ? String(localized: "每\(String(interval))\(frequency.unitName)") : base
        if hasEndDate {
            desc += String(localized: "，至\(endDate.formatted(date: .abbreviated, time: .omitted))止")
        }
        return desc
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

    private func openPicker(_ sheet: RecurringPickerSheet) {
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
        guard let rule = editingRule, let t = rule.template else { return }
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
        frequency = rule.frequency
        interval = Int(rule.interval)
        startDate = rule.startDate
        if let end = rule.endDate {
            hasEndDate = true
            endDate = end
        }
    }

    /// 转账周期账不使用 分类/成员/商家/项目（见 `TransactionType.allowsTagFields`）。
    /// 表单在转账类型下不渲染这四个选择器，但切换类型之前可能已经选过值 —— 落库时以类型
    /// 为准过滤，否则模板会带着分类图标出现在模板列表里，而模板表单对转账不渲染它们，
    /// 用户无从改掉。
    private func save() {
        guard let ledger = effectiveLedger else { return }
        if let dup = try? appContainer.templateService.findByName(name, ledger: ledger, context: modelContext),
           dup.id != editingRule?.template?.id {
            errorMessage = String(localized: "同名周期账「\(name)」已存在")
            return
        }
        // 写库失败必须让用户看见，所以这里不能再 `try?` 吞掉错误：那会让 sheet 照常关闭，
        // 用户以为改好了，实际上金额从没落库（周期账金额"改完又变回去"就查不出是哪一层丢的）。
        //
        // 失败时 catch 负责收尾（见下方注释）；但要注意三步保存是各自 `context.save()` 的，
        // 不是原子操作：编辑分支若第 2/3 步失败，第 1 步已落库的字段改动不会被撤销
        // （让用户再点一次保存即可补齐），这一点无法只靠 catch 解决。
        var createdTemplate: TransactionTemplate?
        do {
            if let rule = editingRule, let t = rule.template {
                t.name = name
                t.type = type
                t.amount = amount
                t.note = note.isEmpty ? nil : note
                t.account = selectedAccount
                t.toAccount = selectedToAccount
                t.category = type.allowsTagFields ? selectedCategory : nil
                t.member = type.allowsTagFields ? selectedMember : nil
                t.merchant = type.allowsTagFields ? selectedMerchant : nil
                t.project = type.allowsTagFields ? selectedProject : nil
                try appContainer.templateService.updateTemplate(t, context: modelContext)
                let end = hasEndDate ? endDate : nil
                try appContainer.recurringService.setRecurring(
                    template: t,
                    frequency: frequency,
                    interval: interval,
                    startDate: startDate,
                    endDate: end,
                    context: modelContext
                )
                try appContainer.recurringService.processAndDeduplicate(context: modelContext)
            } else {
                let template = TransactionTemplate(
                    name: name,
                    type: type,
                    amount: amount,
                    note: note.isEmpty ? nil : note,
                    account: selectedAccount,
                    toAccount: selectedToAccount,
                    category: type.allowsTagFields ? selectedCategory : nil,
                    member: type.allowsTagFields ? selectedMember : nil,
                    merchant: type.allowsTagFields ? selectedMerchant : nil,
                    project: type.allowsTagFields ? selectedProject : nil,
                    context: modelContext
                )
                createdTemplate = template
                try appContainer.templateService.createTemplate(template, ledger: ledger, context: modelContext)
                let end = hasEndDate ? endDate : nil
                try appContainer.recurringService.setRecurring(
                    template: template,
                    frequency: frequency,
                    interval: interval,
                    startDate: startDate,
                    endDate: end,
                    context: modelContext
                )
                try appContainer.recurringService.processAndDeduplicate(context: modelContext)
            }
            dismiss()
        } catch {
            // 收尾顺序不能颠倒：
            // ① 先把"已经落库的半成品"删掉 —— 新建分支里模板是第 1 步就 save 过的，
            //    留着它用户重试时会撞上上面的"同名"守卫（新建分支没有 editingRule 可排除自己）。
            //    `isTemporaryID` 说明这次插入根本没成功（第 1 步就抛了），那交给 ② 的 rollback 丢弃。
            // ② 再 rollback 丢弃未保存的脏改动 —— 那些赋值改的是共享 viewContext 上的托管对象，
            //    不清掉的话，之后任意一次无关的 `context.save()`（例如远程变化触发的去重）
            //    都会把这次"已报失败"的改动静默写进库。
            // 注意 ② 必须在 ① 的 save 之后：rollback 会撤销尚未保存的删除。
            if let created = createdTemplate, !created.objectID.isTemporaryID {
                // `generatedTransactions` 的删除规则是 Nullify（见 xcdatamodeld 的 contents），
                // 删模板**不会**连带删掉它们：第 3 步 `processDueRecurring` 已经 save 过一笔
                // 生成的交易，只删模板就会把那笔没打算建的流水留在账本里（已落库，② 撤不回）。
                // `recurringRule` 是 Cascade，删模板时自动带走，不需要显式删。
                for tx in created.generatedTransactions ?? [] { modelContext.delete(tx) }
                modelContext.delete(created)
                // 这一步的 save 若也失败，② 的 rollback 会把刚删掉的模板复活（用户重试就会撞上
                // 上面的"同名"守卫）—— 二次失败的边角；即便如此，脏改动仍被 ② 清掉了。
                try? modelContext.save()
            }
            modelContext.rollback()
            DiagnosticLog.log("AddEditRecurringView: save FAILED: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }
    }
}
