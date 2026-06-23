import SwiftUI
@preconcurrency import CoreData

struct MacCategoryEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var modelContext
    @Environment(AppContainer.self) private var appContainer
    var editing: Category? = nil
    let ledger: Ledger?

    @State private var name: String = ""
    @State private var iconName: String = "tag"
    @State private var colorHex: String = "#00D16B"
    @State private var catType: TransactionType = .expense
    @State private var selectedParent: Category? = nil
    @State private var parentOptions: [Category] = []

    private let iconOptions = ["tag", "cart", "fork.knife", "car", "house", "film", "heart",
        "gamecontroller", "book", "iphone", "cross.case", "airplane", "bus", "gift",
        "party.popper", "pawprint", "tshirt", "wrench", "leaf", "flame"]
    private let colorOptions = ["#00D16B", "#FF6B6B", "#FFD93D", "#6BCB77", "#4D96FF",
        "#9B59B6", "#E67E22", "#1ABC9C", "#E74C3C", "#3498DB"]

    private var isEditing: Bool { editing != nil }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Icon grid
                VStack(spacing: 6) {
                    Text("图标").font(.designBodyCaption).foregroundStyle(Color.designOnSurfaceVariant)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 6), spacing: 4) {
                        ForEach(iconOptions, id: \.self) { icon in
                            Button { iconName = icon } label: {
                                Image(systemName: icon)
                                    .font(.system(size: 20))
                                    .frame(width: 40, height: 40)
                                    .background(iconName == icon ? Color.accentColor.opacity(0.15) : Color.clear)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(
                                        iconName == icon ? Color.accentColor.opacity(0.3) : Color.clear, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)

                // Color dots
                VStack(spacing: 6) {
                    Text("颜色").font(.designBodyCaption).foregroundStyle(Color.designOnSurfaceVariant)
                    HStack(spacing: 8) {
                        ForEach(colorOptions, id: \.self) { c in
                            Button { colorHex = c } label: {
                                Circle().fill(Color(hex: c))
                                    .frame(width: 24, height: 24)
                                    .overlay(Circle().stroke(colorHex == c ? Color.white : Color.clear, lineWidth: 2))
                                    .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)

                Divider()

                // Form fields
                VStack(spacing: 10) {
                    LabeledContent("名称：") {
                        TextField("", text: $name).textFieldStyle(.roundedBorder)
                    }
                    LabeledContent("类型：") {
                        Picker("", selection: $catType) {
                            Text("支出").tag(TransactionType.expense)
                            Text("收入").tag(TransactionType.income)
                        }
                        .pickerStyle(.menu).labelsHidden()
                        .onChange(of: catType) { _, _ in loadParents() }
                    }
                    if !parentOptions.isEmpty {
                        LabeledContent("上级：") {
                            Picker("", selection: $selectedParent) {
                                Text("无（顶级分类）").tag(nil as Category?)
                                ForEach(parentOptions.filter { $0.id != editing?.id }, id: \.self) { p in
                                    Text(p.name).tag(p as Category?)
                                }
                            }
                            .pickerStyle(.menu).labelsHidden()
                        }
                    }
                }
                .buttonSizing(.flexible)
                .frame(width: 320)
                .frame(maxWidth: .infinity, alignment: .center)

                Divider()

                HStack {
                    Spacer()
                    Button("取消") { dismiss() }.keyboardShortcut(.escape)
                    Button("保存") { save() }.keyboardShortcut(.return)
                        .buttonStyle(.borderedProminent).tint(Color.designPrimaryContainer)
                        .disabled(name.isEmpty)
                    Spacer()
                }
            }
            .padding(32)
            .frame(maxWidth: .infinity)
        }
        .designScreen()
        .frame(minWidth: 400, idealWidth: 420, minHeight: 370)
        .navigationTitle(isEditing ? "编辑分类" : "新建分类")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") { save() }.disabled(name.isEmpty)
            }
        }
        .onAppear {
            if let cat = editing {
                name = cat.name
                iconName = cat.iconName
                colorHex = cat.colorHex
                catType = cat.type
                selectedParent = cat.parent
            }
            loadParents()
        }
    }

    private func loadParents() {
        guard let l = ledger ?? appContainer.currentLedger else { return }
        parentOptions = (try? appContainer.categoryService.fetchAllCategories(
            for: l, type: catType, context: modelContext))?
            .filter { $0.parent == nil } ?? []
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
        cat.parent = selectedParent
        try? modelContext.save()
        dismiss()
    }
}
