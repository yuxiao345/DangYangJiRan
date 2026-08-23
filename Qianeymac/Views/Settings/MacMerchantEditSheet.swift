import SwiftUI
@preconcurrency import CoreData

struct MacMerchantEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var modelContext
    @Environment(AppContainer.self) private var appContainer
    var editing: Merchant? = nil
    let ledger: Ledger?

    @State private var name: String = ""
    @State private var category: String = ""
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
                        Text("类别：")
                        TextField("如 餐饮/购物", text: $category).textFieldStyle(.roundedBorder)
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
        .frame(minWidth: 400, idealWidth: 420, minHeight: 280)
        .navigationTitle(isEditing ? "编辑商家" : "新增商家")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") { save() }.disabled(name.isEmpty)
            }
        }
        .alert("保存失败", isPresented: .constant(errorMessage != nil)) {
            // System default OK button auto-dismisses the alert.
        } message: { Text(errorMessage ?? "") }
        .onAppear {
            if let m = editing {
                name = m.name
                category = m.category ?? ""
                isActive = m.isActive
            }
        }
    }

    private func save() {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else {
            errorMessage = String(localized: "请输入商家名称"); return
        }
        guard let l = ledger ?? editing?.ledger ?? appContainer.currentLedger else { return }

        if let dup = try? appContainer.merchantService.findByName(name, ledger: l, context: modelContext),
           dup.id != editing?.id {
            errorMessage = String(localized: "同名商家「\(name)」已存在")
            return
        }

        if let existing = editing {
            existing.name = name
            existing.category = category.isEmpty ? nil : category
            existing.isActive = isActive
            try? appContainer.merchantService.updateMerchant(existing, context: modelContext)
        } else {
            let merchant = Merchant(
                name: name,
                category: category.isEmpty ? nil : category,
                isActive: isActive,
                sortOrder: 0,
                context: modelContext
            )
            try? appContainer.merchantService.createMerchant(merchant, ledger: l, context: modelContext)
        }
        dismiss()
    }
}
