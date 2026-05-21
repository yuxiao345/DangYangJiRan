import SwiftUI
import SwiftData

struct AddEditCategoryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appContainer: AppContainer

    let editing: Category?
    let ledger: Ledger?
    private var effectiveLedger: Ledger? { ledger ?? appContainer.currentLedger }

    @State private var name: String = ""
    @State private var iconName: String = "questionmark"
    @State private var colorHex: String = "#666666"
    @State private var type: TransactionType = .expense
    @State private var selectedParent: Category?
    @State private var availableParents: [Category] = []
    @State private var errorMessage: String?

    init(editing: Category? = nil, ledger: Ledger? = nil) {
        self.editing = editing
        self.ledger = ledger
    }

    private let iconOptions = [
        "fork.knife", "car.fill", "bag.fill", "house.fill", "tv.fill",
        "book.fill", "cross.case.fill", "gift.fill", "yensign.circle",
        "pawprint", "ellipsis", "dollarsign.circle", "laptopcomputer",
        "chart.line.uptrend.xyaxis", "arrow.uturn.backward",
        "fuelpump", "bus", "wifi", "phone", "pills", "stethoscope",
        "graduationcap", "gamecontroller", "film", "airplane",
        "tshirt", "desktopcomputer", "basket", "creditcard", "banknote"
    ]

    private let colorOptions = [
        "#FF6B35", "#607D8B", "#E91E63", "#795548", "#673AB7",
        "#2196F3", "#4CAF50", "#00BCD4", "#FF9800", "#9E9E9E",
        "#3F51B5", "#8D6E63", "#757575", "#8BC34A", "#009688",
        "#FF5722", "#FFC107", "#03A9F4", "#CDDC39", "#FF4081"
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("基本信息") {
                    TextField("名称", text: $name)
                    Picker("类型", selection: $type) {
                        Text("支出").tag(TransactionType.expense)
                        Text("收入").tag(TransactionType.income)
                    }
                    .pickerStyle(.segmented)
                }

                Section("图标") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 8) {
                        ForEach(iconOptions, id: \.self) { icon in
                            Image(systemName: icon)
                                .font(.title3)
                                .frame(width: 44, height: 44)
                                .background(icon == iconName ? Color.blue.opacity(0.2) : .clear)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .onTapGesture { iconName = icon }
                        }
                    }
                }

                Section("颜色") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 8) {
                        ForEach(colorOptions, id: \.self) { color in
                            Circle()
                                .fill(Color(hex: color))
                                .frame(width: 32, height: 32)
                                .overlay(
                                    Circle()
                                        .stroke(color == colorHex ? Color.primary : .clear, lineWidth: 2)
                                )
                                .padding(4)
                                .onTapGesture { colorHex = color }
                        }
                    }
                }

                Section("上级分类") {
                    Picker("父分类", selection: $selectedParent) {
                        Text("无（作为一级分类）").tag(nil as Category?)
                        ForEach(availableParents) { c in
                            Label(c.name, systemImage: c.iconName).tag(c as Category?)
                        }
                    }
                }
            }
            .navigationTitle(editing == nil ? "新建分类" : "编辑分类")
            .navigationBarTitleDisplayMode(.inline)
            .alert("保存失败", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("好") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(name.isEmpty)
                }
            }
            .onAppear { setup() }
        }
    }

    private func setup() {
        if let cat = editing {
            name = cat.name
            iconName = cat.iconName
            colorHex = cat.colorHex
            type = cat.type
            selectedParent = cat.parent
        }
        loadParents()
    }

    private func loadParents() {
        guard let ledger = effectiveLedger else { return }
        let all = (try? appContainer.categoryService.fetchCategories(for: ledger, type: type, context: modelContext)) ?? []
        availableParents = all.filter { $0.parent == nil && $0.id != editing?.id }
    }

    private func save() {
        guard let ledger = effectiveLedger else { return }
        do {
            if let cat = editing {
                cat.name = name
                cat.iconName = iconName
                cat.colorHex = colorHex
                cat.typeRaw = type.rawValue
                cat.parent = selectedParent
                try appContainer.categoryService.updateCategory(cat, context: modelContext)
            } else {
                let category = Category(
                    name: name,
                    iconName: iconName,
                    colorHex: colorHex,
                    type: type,
                    isSystem: false,
                    sortOrder: 999,
                    parent: selectedParent
                )
                try appContainer.categoryService.createCategory(category, ledger: ledger, context: modelContext)
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
