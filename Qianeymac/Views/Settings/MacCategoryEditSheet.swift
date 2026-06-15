import SwiftUI
@preconcurrency import CoreData

struct MacCategoryEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var modelContext
    @Environment(AppContainer.self) private var appContainer
    var editing: Category?
    let ledger: Ledger?

    @State private var name: String = ""
    @State private var iconName: String = "tag"
    @State private var colorHex: String = "#00D16B"
    @State private var catType: TransactionType = .expense
    @State private var selectedParent: Category?
    @State private var parentOptions: [Category] = []

    private let iconOptions = ["tag", "cart", "fork.knife", "car", "house", "film", "heart", "gamecontroller", "book", "iphone", "cross.case", "airplane", "bus", "gift", "party.popper", "pawprint", "tshirt", "wrench", "leaf", "flame"]
    private let colorOptions = ["#00D16B", "#FF6B6B", "#FFD93D", "#6BCB77", "#4D96FF", "#9B59B6", "#E67E22", "#1ABC9C", "#E74C3C", "#3498DB"]

    var body: some View {
        VStack(spacing: 16) {
            Text(editing != nil ? "编辑分类" : "新建分类")
                .font(.title2.weight(.semibold))
            Form {
                TextField("名称", text: $name)
                Picker("类型", selection: $catType) {
                    Text("支出").tag(TransactionType.expense)
                    Text("收入").tag(TransactionType.income)
                }
                Picker("图标", selection: $iconName) {
                    ForEach(iconOptions, id: \.self) { icon in
                        Label(icon, systemImage: icon).tag(icon)
                    }
                }
                Picker("颜色", selection: $colorHex) {
                    ForEach(colorOptions, id: \.self) { c in
                        HStack {
                            Circle().fill(Color(hex: c)).frame(width: 16, height: 16)
                            Text(c)
                        }.tag(c)
                    }
                }
            }
            .formStyle(.grouped)
            HStack(spacing: 12) {
                Button("取消") { dismiss() }.keyboardShortcut(.escape)
                Button("保存") { save() }.keyboardShortcut(.return).disabled(name.isEmpty)
            }
        }
        .padding(24).frame(width: 380, height: 420)
        .onAppear {
            if let cat = editing {
                name = cat.name
                iconName = cat.iconName
                colorHex = cat.colorHex
                catType = cat.type
            }
            if let l = ledger ?? appContainer.currentLedger {
                parentOptions = (try? appContainer.categoryService.fetchAllCategories(for: l, type: catType, context: modelContext))?.filter { $0.parent == nil } ?? []
            }
        }
    }

    private func save() {
        let cat = editing ?? Category(context: modelContext)
        if editing == nil {
            cat.id = UUID()
            cat.sortOrder = 999
            if let l = ledger ?? appContainer.currentLedger {
                cat.ledger = l
            }
        }
        cat.name = name
        cat.iconName = iconName
        cat.colorHex = colorHex
        cat.type = catType
        try? modelContext.save()
        dismiss()
    }
}

