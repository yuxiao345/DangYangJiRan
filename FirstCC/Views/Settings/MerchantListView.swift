import SwiftUI
import SwiftData

struct MerchantListView: View {
    @EnvironmentObject private var appContainer: AppContainer
    @Environment(\.modelContext) private var modelContext
    @State private var merchants: [Merchant] = []
    @State private var showAddAlert = false
    @State private var newName = ""
    @State private var editingMerchant: Merchant?

    var body: some View {
        List {
            if merchants.isEmpty {
                Text("暂无商家，点击右上角 + 添加")
                    .foregroundStyle(.secondary)
            }
            ForEach(merchants) { merchant in
                HStack {
                    Image(systemName: "storefront")
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading) {
                        Text(LocalizedStringKey(merchant.name))
                        if let cat = merchant.category, !cat.isEmpty {
                            Text(cat)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if !merchant.isActive {
                        Text("已停用").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { editingMerchant = merchant }
                .swipeActions {
                    Button(role: .destructive) {
                        try? appContainer.merchantService.deleteMerchant(merchant, context: modelContext)
                        loadMerchants()
                    } label: { Label("删除", systemImage: "trash") }
                }
            }
        }
        .navigationTitle("商家管理")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showAddAlert = true } label: {
                    Image(systemName: "plus")
                }
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
        .onAppear(perform: loadMerchants)
    }

    private func addMerchant() {
        guard let ledger = appContainer.currentLedger else { return }
        let merchant = Merchant(name: newName, sortOrder: merchants.count)
        try? appContainer.merchantService.createMerchant(merchant, ledger: ledger, context: modelContext)
        loadMerchants()
    }

    private func loadMerchants() {
        guard let ledger = appContainer.currentLedger else { return }
        merchants = (try? appContainer.merchantService.fetchMerchants(for: ledger, context: modelContext)) ?? []
    }
}

struct EditMerchantView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appContainer: AppContainer
    let merchant: Merchant
    @State private var name: String
    @State private var category: String
    @State private var isActive: Bool

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
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("保存") { save() } }
            }
        }
    }

    private func save() {
        merchant.name = name
        merchant.category = category.isEmpty ? nil : category
        merchant.isActive = isActive
        try? appContainer.merchantService.updateMerchant(merchant, context: modelContext)
        dismiss()
    }
}
