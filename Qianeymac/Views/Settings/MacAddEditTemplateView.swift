import SwiftUI
@preconcurrency import CoreData

struct MacAddEditTemplateView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var modelContext
    @Environment(AppContainer.self) private var appContainer

    var editing: TransactionTemplate? = nil
    let ledger: Ledger?

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
    @State private var accounts: [Account] = []
    @State private var categories: [Category] = []
    @State private var members: [Member] = []
    @State private var merchants: [Merchant] = []
    @State private var projects: [Project] = []
    @State private var errorMessage: String?
    @State private var showErrorAlert: Bool = false

    private var isEditing: Bool { editing != nil }

    /// Flattened category tree with indentation for picker display
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
                .frame(width: 350)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(32)
            .frame(maxWidth: .infinity)
        }
        .designScreen()
        .frame(minWidth: 400, idealWidth: 460, minHeight: 480)
        .navigationTitle(isEditing ? "编辑模板" : "新建模板")
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
        guard let t = editing else { return }
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
    }

    /// 转账模板不使用 分类/成员/商家/项目（见 `TransactionType.allowsTagFields`）。
    /// 模板表单在转账类型下不渲染这四个选择器，但切换类型之前可能已经选过值 —— 落库
    /// 时以类型为准过滤，避免模板本身就带着残留值，再由周期账/模板生成脏交易。
    private func save() {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        guard let l = ledger ?? editing?.ledger ?? appContainer.currentLedger else { return }

        if let dup = try? appContainer.templateService.findByName(name, ledger: l, context: modelContext),
           dup.id != editing?.id {
            errorMessage = String(localized: "同名模板「\(name)」已存在"); showErrorAlert = true; return
        }

        // 写库失败必须让用户看见，不能再用 `try?` 吞掉：那会让 sheet 照常关闭，
        // 用户以为存好了，实际金额/账户从没落库。收尾见 catch 内注释 —— 与 iOS
        // `AddEditTemplateView.save` 同一套。
        var createdTemplate: TransactionTemplate?
        do {
            if let t = editing {
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
            } else {
                let template = TransactionTemplate(
                    name: name,
                    type: type,
                    amount: amount,
                    currencyCode: l.defaultCurrencyCode,
                    note: note.isEmpty ? nil : note,
                    sortOrder: 0,
                    account: selectedAccount,
                    toAccount: selectedToAccount,
                    category: type.allowsTagFields ? selectedCategory : nil,
                    member: type.allowsTagFields ? selectedMember : nil,
                    merchant: type.allowsTagFields ? selectedMerchant : nil,
                    project: type.allowsTagFields ? selectedProject : nil,
                    context: modelContext
                )
                createdTemplate = template
                try appContainer.templateService.createTemplate(template, ledger: l, context: modelContext)
            }
            dismiss()
        } catch {
            // 顺序不能颠倒：① 先删掉本次已落库的模板（新建分支它已 save 过，留着会让用户
            // 重试时撞上"同名"守卫；`isTemporaryID` 说明第 1 步就没成功，交给 ② 丢弃）；
            // ② 再 rollback 丢弃未保存的脏改动，否则它们会被之后任意一次无关的
            // `context.save()` 静默写进库。② 必须在 ① 的 save 之后，rollback 会撤销未保存的删除。
            // ② 的波及范围要知道：`modelContext` 是全应用共用的那一个 viewContext
            // （来自 `@Environment(\.managedObjectContext)`），`rollback()` 丢的是它上面
            // **所有**未保存改动，不止本视图改的这几个字段。当前所有写入路径都是"改完立即 save"，
            // 留不下跨帧的脏数据，所以打不到；将来若有代码在 viewContext 上留下未保存改动，
            // 这里会连它一起丢掉。
            if let created = createdTemplate, !created.objectID.isTemporaryID {
                modelContext.delete(created)
                try? modelContext.save()
            }
            modelContext.rollback()
            DiagnosticLog.log("MacAddEditTemplateView: save FAILED: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
            showErrorAlert = true
        }
    }
}
