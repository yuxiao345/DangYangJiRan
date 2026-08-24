import SwiftUI
@preconcurrency import CoreData

struct MacProjectEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var modelContext
    @Environment(AppContainer.self) private var appContainer
    var editing: Project? = nil
    let ledger: Ledger?

    @State private var name: String = ""
    @State private var desc: String = ""
    @State private var startDate: Date = Date.now
    @State private var endDate: Date = Date.now.addingTimeInterval(86400 * 7)
    @State private var budgetText: String = ""
    @State private var isActive: Bool = true

    private var isEditing: Bool { editing != nil }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                    GridRow {
                        Text("名称：")
                            .gridColumnAlignment(.trailing)
                        TextField("", text: $name).textFieldStyle(.roundedBorder)
                    }
                    GridRow {
                        Text("描述：")
                        TextField("", text: $desc).textFieldStyle(.roundedBorder)
                    }
                    GridRow {
                        Text("开始日期：")
                        DatePicker("", selection: $startDate, displayedComponents: .date)
                            .labelsHidden()
                    }
                    GridRow {
                        Text("结束日期：")
                        DatePicker("", selection: $endDate, displayedComponents: .date)
                            .labelsHidden()
                    }
                    GridRow {
                        Text("预算：")
                        TextField("0.00", text: $budgetText)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 120)
                            .multilineTextAlignment(.trailing)
                            .onChange(of: budgetText) { _, v in
                                budgetText = v.filter { "0123456789.".contains($0) }
                            }
                    }
                    GridRow {
                        Text("状态：")
                        Toggle("进行中", isOn: $isActive)
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
        .frame(minWidth: 400, idealWidth: 440, minHeight: 380)
        .navigationTitle(isEditing ? "编辑项目" : "新建项目")
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

    private func save() {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        guard let l = ledger ?? editing?.ledger ?? appContainer.currentLedger else { return }
        let budget = Decimal(string: budgetText)

        if let existing = editing {
            existing.name = name
            existing.desc = desc.isEmpty ? nil : desc
            existing.startDate = startDate
            existing.endDate = endDate
            existing.budget = budget
            existing.isActive = isActive
            try? appContainer.projectService.updateProject(existing, context: modelContext)
        } else {
            let project = Project(
                name: name,
                desc: desc.isEmpty ? nil : desc,
                startDate: startDate,
                endDate: endDate,
                budget: budget,
                isActive: isActive,
                sortOrder: 0,
                context: modelContext
            )
            try? appContainer.projectService.createProject(project, ledger: l, context: modelContext)
        }
        dismiss()
    }
}
