import SwiftUI
@preconcurrency import CoreData

struct ProjectListView: View {
    @Environment(AppContainer.self) private var appContainer
    @Environment(\.managedObjectContext) private var modelContext
    @State private var projects: [Project] = []
    @State private var showAddSheet = false
    @State private var editingProject: Project?
    @State private var listVersion = 0

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
                            Text("\(String(localized: "预算")):")
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
        .id(listVersion)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showAddSheet = true } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showAddSheet) { AddEditProjectView(ledger: effectiveLedger) }
        .onChange(of: showAddSheet) { _, newValue in
            if !newValue { listVersion += 1; loadProjects() }
        }
        .sheet(item: $editingProject) { project in
            AddEditProjectView(editing: project, ledger: effectiveLedger)
        }
        .onChange(of: editingProject) { _, newValue in
            if newValue == nil { listVersion += 1; loadProjects() }
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
    @Environment(\.managedObjectContext) private var modelContext
    @Environment(AppContainer.self) private var appContainer
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
                    DatePickerButton(title: "开始日期", date: $startDate)
                    DatePickerButton(title: "结束日期", date: $endDate)
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
                sortOrder: 0, context: modelContext
            )
            try? appContainer.projectService.createProject(project, ledger: ledger, context: modelContext)
        }
        dismiss()
    }
}
