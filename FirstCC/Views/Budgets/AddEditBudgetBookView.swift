import SwiftUI
@preconcurrency import CoreData

struct AddEditBudgetBookView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var modelContext
    @Environment(AppContainer.self) private var appContainer

    let editing: BudgetBook?
    let ledger: Ledger?
    private var effectiveLedger: Ledger? { ledger ?? appContainer.currentLedger }

    @State private var name: String = ""
    @State private var startDate: Date = Date()
    @State private var endDate: Date = Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date()
    @State private var isActive: Bool = true
    @State private var errorMessage: String?

    init(editing: BudgetBook? = nil, ledger: Ledger? = nil) {
        self.editing = editing
        self.ledger = ledger
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("基本信息") {
                    TextField("计划名称", text: $name)
                    Toggle("启用", isOn: $isActive)
                }
                Section("预算周期") {
                    DatePickerButton(title: "开始日期", date: $startDate)
                    DatePickerButton(title: "结束日期", date: $endDate)
                }
            }
            .navigationTitle(editing != nil ? "编辑预算计划" : "新建预算计划")
            .errorAlert("保存失败", message: $errorMessage)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(name.isEmpty)
                }
            }
            .onAppear {
                if let b = editing {
                    name = b.name
                    startDate = b.startDate
                    endDate = b.endDate
                    isActive = b.isActive
                }
            }
        }
    }

    private func save() {
        guard let ledger = effectiveLedger else { return }
        if let dup = try? appContainer.budgetService.findBookByName(name, ledger: ledger, context: modelContext),
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
            let book = BudgetBook(name: name, startDate: startDate, endDate: endDate, isActive: isActive, context: modelContext)
            try? appContainer.budgetService.createBook(book, ledger: ledger, context: modelContext)
        }
        dismiss()
    }
}
