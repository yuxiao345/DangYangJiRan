import SwiftUI
@preconcurrency import CoreData

struct MacAddEditBudgetBookView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var modelContext
    @Environment(AppContainer.self) private var appContainer

    var editing: BudgetBook? = nil
    let ledger: Ledger?
    private var effectiveLedger: Ledger? { ledger ?? appContainer.currentLedger }

    @State private var name: String = ""
    @State private var startDate: Date = Date()
    @State private var endDate: Date = Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date()
    @State private var isActive: Bool = true
    @State private var errorMessage: String?

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
                        Text("状态：")
                        Toggle("启用", isOn: $isActive)
                    }
                }
                .buttonSizing(.flexible)
                .frame(width: 320)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(32)
            .frame(maxWidth: .infinity)
        }
        .designScreen()
        .frame(minWidth: 400, idealWidth: 420, minHeight: 300)
        .navigationTitle(isEditing ? "编辑预算计划" : "新建预算计划")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") { save() }.disabled(name.isEmpty)
            }
        }
        .alert("保存失败", isPresented: .constant(errorMessage != nil)) {
            Button("好") { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
        .onAppear {
            if let b = editing {
                name = b.name
                startDate = b.startDate
                endDate = b.endDate
                isActive = b.isActive
            }
        }
    }

    private func save() {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        guard let l = ledger ?? editing?.ledger ?? appContainer.currentLedger else { return }

        if let dup = try? appContainer.budgetService.findBookByName(name, ledger: l, context: modelContext),
           dup.id != editing?.id {
            errorMessage = String(localized: "同名预算计划「\(name)」已存在")
            return
        }

        if let b = editing {
            b.name = name
            b.startDate = startDate
            b.endDate = endDate
            b.isActive = isActive
            try? appContainer.budgetService.updateBook(b, context: modelContext)
        } else {
            let book = BudgetBook(
                name: name, startDate: startDate, endDate: endDate,
                isActive: isActive, context: modelContext
            )
            try? appContainer.budgetService.createBook(book, ledger: l, context: modelContext)
        }
        dismiss()
    }
}
