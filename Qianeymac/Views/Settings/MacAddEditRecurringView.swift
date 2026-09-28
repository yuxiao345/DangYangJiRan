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

    /// 转账周期账不使用 分类/成员/商家/项目（见 `TransactionType.allowsTagFields`）。
    /// 表单在转账类型下不渲染这四个选择器，但切换类型之前可能已经选过值 —— 落库时以类型
    /// 为准过滤，否则模板会带着分类图标出现在模板列表里，而模板表单对转账不渲染它们，
    /// 用户无从改掉。
    private func save() {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        guard let l = ledger ?? editing?.template?.ledger ?? appContainer.currentLedger else { return }

        if let dup = try? appContainer.templateService.findByName(name, ledger: l, context: modelContext),
           dup.id != editing?.template?.id {
            errorMessage = String(localized: "同名周期账「\(name)」已存在"); showErrorAlert = true; return
        }

        let end = hasEndDate ? endDate : nil

        // 写库失败必须让用户看见，不能再用 `try?` 吞掉：那会让 sheet 照常关闭，
        // 用户以为改好了，实际金额从没落库（周期账金额"改完又变回去"就查不出是哪一层丢的）。
        // 失败收尾见 catch 内注释 —— 与 iOS `AddEditRecurringView.save` 同一套。
        //
        // 注意三步保存各自 `context.save()`，不是原子操作：编辑分支若第 2/3 步失败，
        // 第 1 步已落库的字段改动不会被撤销（再点一次保存即可补齐），这一点无法只靠 catch 解决。
        var createdTemplate: TransactionTemplate?
        do {
            if let rule = editing, let t = rule.template {
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
                try appContainer.recurringService.setRecurring(
                    template: t, frequency: frequency, interval: interval,
                    startDate: startDate, endDate: end, context: modelContext
                )
                try appContainer.recurringService.processAndDeduplicate(context: modelContext)
            } else {
                let template = TransactionTemplate(
                    name: name, type: type, amount: amount,
                    currencyCode: l.defaultCurrencyCode,
                    note: note.isEmpty ? nil : note, sortOrder: 0,
                    account: selectedAccount, toAccount: selectedToAccount,
                    category: type.allowsTagFields ? selectedCategory : nil,
                    member: type.allowsTagFields ? selectedMember : nil,
                    merchant: type.allowsTagFields ? selectedMerchant : nil,
                    project: type.allowsTagFields ? selectedProject : nil,
                    context: modelContext
                )
                createdTemplate = template
                try appContainer.templateService.createTemplate(template, ledger: l, context: modelContext)
                try appContainer.recurringService.setRecurring(
                    template: template, frequency: frequency, interval: interval,
                    startDate: startDate, endDate: end, context: modelContext
                )
                try appContainer.recurringService.processAndDeduplicate(context: modelContext)
            }
            dismiss()
        } catch {
            // 收尾顺序不能颠倒：
            // ① 先把"已经落库的半成品"删掉 —— 新建分支里模板是第 1 步就 save 过的，
            //    留着它用户重试时会撞上上面的"同名"守卫（新建分支没有 editing 可排除自己）。
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
            DiagnosticLog.log("MacAddEditRecurringView: save FAILED: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
            showErrorAlert = true
        }
    }
}
