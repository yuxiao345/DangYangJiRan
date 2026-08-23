import SwiftUI
@preconcurrency import CoreData

struct MerchantListView: View {
    @Environment(AppContainer.self) private var appContainer
    @Environment(\.managedObjectContext) private var modelContext
    @State private var merchants: [Merchant] = []
    @State private var showAddAlert = false
    @State private var newName = ""
    @State private var editingMerchant: Merchant?
    @State private var listVersion = 0
    @State private var errorMessage: String?

    let ledger: Ledger?
    private var effectiveLedger: Ledger? { ledger ?? appContainer.currentLedger }

    init(ledger: Ledger? = nil) {
        self.ledger = ledger
    }

    var body: some View {
        SearchableList(items: merchants, searchKey: \.name) { filteredMerchants, isSearching in
            merchantListView(filteredMerchants, isSearching: isSearching)
        }
        .onAppear(perform: loadMerchants)
    }

    @ViewBuilder
    private func merchantListView(_ merchants: [Merchant], isSearching: Bool) -> some View {
        List {
            if merchants.isEmpty {
                ContentUnavailableView(
                    isSearching ? "无匹配结果" : "暂无商家",
                    systemImage: "storefront",
                    description: Text("点击右上角 + 添加商家")
                )
            }
            ForEach(merchants) { merchant in
                Button { editingMerchant = merchant } label: {
                    HStack {
                        Image(systemName: "storefront")
                            .foregroundStyle(Color.designSecondary)
                        VStack(alignment: .leading) {
                            Text(LocalizedStringKey(merchant.name))
                            if let cat = merchant.category, !cat.isEmpty {
                                Text(cat)
                                    .font(.designBodySmall)
                                    .foregroundStyle(Color.designOnSurfaceVariant)
                            }
                        }
                        Spacer()
                        if !merchant.isActive {
                            Text("已停用").font(.designBodySmall).foregroundStyle(Color.designOnSurfaceVariant)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .swipeActions {
                    Button(role: .destructive) {
                        do {
                            try appContainer.merchantService.deleteMerchant(merchant, context: modelContext)
                        } catch {
                            NSLog(String(localized: "[MerchantList] 删除商家失败: \(error.localizedDescription)"))
                        }
                        loadMerchants()
                    } label: { Label("删除", systemImage: "trash") }
                }
            }
        }
        .navigationTitle("商家管理")
        .id(listVersion)
        .errorAlert("保存失败", message: $errorMessage)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showAddAlert = true } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel(Text("添加商家"))
            }
        }
        .alert("添加商家", isPresented: $showAddAlert) {
            TextField("商家名称", text: $newName)
            Button("取消", role: .cancel) { newName = "" }
            Button("添加") {
                addMerchant()
                newName = ""
            }.disabled(newName.isEmpty)
        }
        .sheet(item: $editingMerchant) { merchant in
            EditMerchantView(merchant: merchant)
        }
        .onChange(of: editingMerchant) { _, newValue in
            if newValue == nil { listVersion += 1; loadMerchants() }
        }
    }

    private func addMerchant() {
        guard let ledger = effectiveLedger else { return }
        if let dup = try? appContainer.merchantService.findByName(newName, ledger: ledger, context: modelContext) {
            errorMessage = String(localized: "同名商家「\(newName)」已存在")
            return
        }
        let merchant = Merchant(name: newName, sortOrder: merchants.count, context: modelContext)
        do {
            try appContainer.merchantService.createMerchant(merchant, ledger: ledger, context: modelContext)
            loadMerchants()
        } catch {
            NSLog(String(localized: "[MerchantList] 添加商家失败: \(error.localizedDescription)"))
        }
    }

    private func loadMerchants() {
        guard let ledger = effectiveLedger else { return }
        merchants = (try? appContainer.merchantService.fetchMerchants(for: ledger, context: modelContext)) ?? []
    }
}

struct EditMerchantView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var modelContext
    @Environment(AppContainer.self) private var appContainer
    let merchant: Merchant
    @State private var name: String
    @State private var category: String
    @State private var isActive: Bool
    @State private var errorMessage: String?

    init(merchant: Merchant) {
        self.merchant = merchant
        _name = State(initialValue: merchant.name)
        _category = State(initialValue: merchant.category ?? "")
        _isActive = State(initialValue: merchant.isActive)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("名称", text: $name)
                TextField("类别（如 餐饮/购物）", text: $category)
                Toggle("启用", isOn: $isActive)
            }
            .navigationTitle("编辑商家")
            .errorAlert("保存失败", message: $errorMessage)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("保存") { save() } }
            }
        }
    }

    private func save() {
        guard let ledger = merchant.ledger else {
            errorMessage = String(localized: "商家数据异常，缺少关联账本")
            return
        }
        if let dup = try? appContainer.merchantService.findByName(name, ledger: ledger, context: modelContext),
           dup.id != merchant.id {
            errorMessage = String(localized: "同名商家「\(name)」已存在")
            return
        }
        merchant.name = name
        merchant.category = category.isEmpty ? nil : category
        merchant.isActive = isActive
        do {
            try appContainer.merchantService.updateMerchant(merchant, context: modelContext)
            dismiss()
        } catch {
            NSLog(String(localized: "[MerchantList] 编辑商家失败: \(error.localizedDescription)"))
        }
    }
}
