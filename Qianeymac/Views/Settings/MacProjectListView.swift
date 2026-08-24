import SwiftUI
@preconcurrency import CoreData

struct MacProjectListView: View {
    @Environment(AppContainer.self) private var appContainer
    @Environment(\.managedObjectContext) private var modelContext
    let ledger: Ledger?
    @State private var projects: [Project] = []
    @State private var showAddSheet = false
    @State private var editingProject: Project?
    @State private var showDeleteAlert = false
    @State private var projectToDelete: Project?
    @State private var refreshTrigger = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("项目管理").font(.designHeadlineMedium).foregroundStyle(Color.designOnSurface)
                Spacer()
                Button { showAddSheet = true } label: {
                    Image(systemName: "plus").fontWeight(.semibold)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(Text("添加项目"))
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 12)

            if projects.isEmpty {
                ContentUnavailableView(
                    "暂无项目",
                    systemImage: "folder.badge.plus",
                    description: Text("点击右上角 + 添加项目")
                )
                .padding(24)
                .frame(maxWidth: .infinity)
            } else {
                List {
                    ForEach(projects) { project in
                        projectRow(project)
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
            }
        }
        .frame(minWidth: 420, maxWidth: 600, minHeight: 400)
        .designScreen()
        .onAppear(perform: load)
        .onChange(of: refreshTrigger) { _, _ in load() }
        .alert("删除项目", isPresented: $showDeleteAlert) {
            Button("取消", role: .cancel) { projectToDelete = nil }
            Button("删除", role: .destructive) { confirmDelete() }
        } message: {
            if let p = projectToDelete {
                Text("确定要删除项目「\(p.name)」吗？此操作不可撤销。")
            }
        }
        .sheet(isPresented: $showAddSheet, onDismiss: { refreshTrigger.toggle() }) {
            MacProjectEditSheet(ledger: effectiveLedger)
        }
        .sheet(item: $editingProject, onDismiss: { refreshTrigger.toggle() }) { project in
            MacProjectEditSheet(editing: project, ledger: effectiveLedger)
        }
    }

    private var effectiveLedger: Ledger? { ledger ?? appContainer.currentLedger }
    private var ledgerCurrency: String { effectiveLedger?.defaultCurrencyCode ?? "CNY" }

    private func projectRow(_ project: Project) -> some View {
        HStack(spacing: 8) {
            Image(systemName: project.isActive ? "folder" : "folder.fill")
                .foregroundStyle(project.isActive ? Color.designPrimaryContainer : Color.designOnSurfaceVariant.opacity(0.4))
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(LocalizedStringKey(project.name))
                        .font(.designBodyMedium)
                        .foregroundStyle(project.isActive ? Color.designOnSurface : Color.designOnSurfaceVariant)
                    if !project.isActive {
                        Text("已结束")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(Color.designOnSurfaceVariant)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Capsule().fill(Color.designOnSurfaceVariant.opacity(0.12)))
                    }
                }
                if let desc = project.desc, !desc.isEmpty {
                    Text(desc)
                        .font(.designBodyCaption)
                        .foregroundStyle(Color.designOnSurfaceVariant)
                        .lineLimit(1)
                }
                if let budget = project.budget {
                    HStack(spacing: 4) {
                        Text("预算:").font(.designBodyCaption)
                        CurrencyText(amount: budget, currencyCode: ledgerCurrency,
                                     size: 11, foregroundColor: .designPrimaryContainer)
                    }
                }
            }
            Spacer()
            Button { editingProject = project } label: {
                Image(systemName: "pencil")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text("编辑项目"))

            Button {
                projectToDelete = project
                showDeleteAlert = true
            } label: {
                Image(systemName: "trash")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text("删除项目"))
        }
        .padding(.vertical, 4)
        .opacity(project.isActive ? 1.0 : 0.55)
    }

    private func load() {
        guard let l = effectiveLedger else { return }
        projects = (try? appContainer.projectService.fetchProjects(for: l, context: modelContext)) ?? []
    }

    private func confirmDelete() {
        guard let project = projectToDelete else { return }
        try? appContainer.projectService.deleteProject(project, context: modelContext)
        projectToDelete = nil
        load()
    }
}
