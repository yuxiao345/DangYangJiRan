import SwiftUI
import SwiftData

struct ProjectListView: View {
    @EnvironmentObject private var appContainer: AppContainer
    @Environment(\.modelContext) private var modelContext
    @State private var projects: [Project] = []
    @State private var showAddSheet = false
    @State private var editingProject: Project?

    let ledger: Ledger?
    private var effectiveLedger: Ledger? { ledger ?? appContainer.currentLedger }

    init(ledger: Ledger? = nil) {
        self.ledger = ledger
    }

    var body: some View {
        List {
            if projects.isEmpty {
                Text("暂无项目，点击右上角 + 添加")
                    .foregroundStyle(Color.designOnSurfaceVariant)
            }
            ForEach(projects) { project in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "folder")
                            .foregroundStyle(Color.designPrimaryContainer)
                        Text(LocalizedStringKey(project.name))
                            .font(.designBodyMedium)
                        Spacer()
                        if !project.isActive {
                            Text("已结束").font(.designBodySmall).foregroundStyle(Color.designOnSurfaceVariant)
                        }
                    }
                    if let desc = project.desc, !desc.isEmpty {
                        Text(desc)
                            .font(.designBodySmall)
                            .foregroundStyle(Color.designOnSurfaceVariant)
                            .lineLimit(1)
                    }
                    if let budget = project.budget {
                        HStack(spacing: 2) {
                            Text("预算:")
                                .font(.designBodySmall)
                            CurrencyText(amount: budget, currencyCode: ledgerCurrency, size: 11, foregroundColor: .designPrimaryContainer)
                        }
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { editingProject = project }
                .swipeActions {
                    Button(role: .destructive) {
                        try? appContainer.projectService.deleteProject(project, context: modelContext)
                        loadProjects()
                    } label: { Label("删除", systemImage: "trash") }
                }
            }
        }
        .navigationTitle("项目管理")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showAddSheet = true } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showAddSheet, onDismiss: { loadProjects() }) { AddEditProjectView(ledger: effectiveLedger) }
        .sheet(item: $editingProject, onDismiss: { loadProjects() }) { project in
            AddEditProjectView(editing: project, ledger: effectiveLedger)
        }
        .onAppear(perform: loadProjects)
    }

    private var ledgerCurrency: String {
        effectiveLedger?.defaultCurrencyCode ?? "CNY"
    }

    private func loadProjects() {
        guard let ledger = effectiveLedger else { return }
        projects = (try? appContainer.projectService.fetchProjects(for: ledger, context: modelContext)) ?? []
    }
}

struct AddEditProjectView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appContainer: AppContainer
    let editing: Project?
    let ledger: Ledger?
    private var effectiveLedger: Ledger? { ledger ?? appContainer.currentLedger }

    @State private var name: String = ""
    @State private var desc: String = ""
    @State private var startDate: Date = Date()
    @State private var endDate: Date = Date().addingTimeInterval(86400 * 7)
    @State private var budgetText: String = ""
    @State private var isActive: Bool = true

    init(editing: Project? = nil, ledger: Ledger? = nil) {
        self.editing = editing
        self.ledger = ledger
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("基本信息") {
                    TextField("项目名称", text: $name)
                    TextField("描述", text: $desc)
                    Toggle("进行中", isOn: $isActive)
                }
                Section("时间") {
                    DatePicker("开始日期", selection: $startDate, displayedComponents: .date)
                    DatePicker("结束日期", selection: $endDate, displayedComponents: .date)
                }
                Section("预算") {
                    TextField("预算金额", text: $budgetText)
                        .keyboardType(.decimalPad)
                }
            }
            .navigationTitle(editing == nil ? "新建项目" : "编辑项目")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }.disabled(name.isEmpty)
                }
            }
            .onAppear {
                if let p = editing {
                    name = p.name
                    desc = p.desc ?? ""
                    startDate = p.startDate ?? Date()
                    endDate = p.endDate ?? Date()
                    budgetText = p.budget?.description ?? ""
                    isActive = p.isActive
                }
            }
        }
    }

    private func save() {
        guard let ledger = effectiveLedger else { return }
        let budget = Decimal(string: budgetText)
        if let p = editing {
            p.name = name; p.desc = desc.isEmpty ? nil : desc
            p.startDate = startDate; p.endDate = endDate
            p.budget = budget; p.isActive = isActive
            try? appContainer.projectService.updateProject(p, context: modelContext)
        } else {
            let project = Project(
                name: name, desc: desc.isEmpty ? nil : desc,
                startDate: startDate, endDate: endDate,
                budget: budget, isActive: isActive,
                sortOrder: 0
            )
            try? appContainer.projectService.createProject(project, ledger: ledger, context: modelContext)
        }
        dismiss()
    }
}
