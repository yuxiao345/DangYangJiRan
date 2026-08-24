import SwiftUI
@preconcurrency import CoreData

struct MacMerchantListView: View {
    @Environment(AppContainer.self) private var appContainer
    @Environment(\.managedObjectContext) private var modelContext
    let ledger: Ledger?
    @State private var merchants: [Merchant] = []
    @State private var showAddSheet = false
    @State private var editingMerchant: Merchant?
    @State private var showDeleteAlert = false
    @State private var merchantToDelete: Merchant?
    @State private var refreshTrigger = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("商家管理").font(.designHeadlineMedium).foregroundStyle(Color.designOnSurface)
                Spacer()
                Button { showAddSheet = true } label: {
                    Image(systemName: "plus").fontWeight(.semibold)
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 12)

            if merchants.isEmpty {
                ContentUnavailableView(
                    "暂无商家",
                    systemImage: "storefront",
                    description: Text("点击右上角 + 添加商家")
                )
                .padding(24)
                .frame(maxWidth: .infinity)
            } else {
                List {
                    ForEach(merchants) { merchant in
                        merchantRow(merchant)
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
        .alert("删除商家", isPresented: $showDeleteAlert) {
            Button("取消", role: .cancel) { merchantToDelete = nil }
            Button("删除", role: .destructive) { confirmDelete() }
        } message: {
            if let m = merchantToDelete {
                Text("确定要删除商家「\(m.name)」吗？此操作不可撤销。")
            }
        }
        .errorAlert("操作失败", message: $errorMessage)
        .sheet(isPresented: $showAddSheet, onDismiss: { refreshTrigger.toggle() }) {
            MacMerchantEditSheet(ledger: effectiveLedger)
        }
        .sheet(item: $editingMerchant, onDismiss: { refreshTrigger.toggle() }) { merchant in
            MacMerchantEditSheet(editing: merchant, ledger: effectiveLedger)
        }
    }

    private var effectiveLedger: Ledger? { ledger ?? appContainer.currentLedger }

    private func merchantRow(_ merchant: Merchant) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "storefront")
                .foregroundStyle(Color.designSecondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(merchant.name)).font(.designBodyMedium)
                if let cat = merchant.category, !cat.isEmpty {
                    Text(cat)
                        .font(.designBodyCaption)
                        .foregroundStyle(Color.designOnSurfaceVariant)
                }
            }
            if !merchant.isActive {
                Text("已停用")
                    .font(.designBodyCaption)
                    .foregroundStyle(Color.designOnSurfaceVariant.opacity(0.6))
            }
            Spacer()
            Button { editingMerchant = merchant } label: {
                Image(systemName: "pencil")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text("编辑商家"))

            Button {
                merchantToDelete = merchant
                showDeleteAlert = true
            } label: {
                Image(systemName: "trash")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text("删除商家"))
        }
        .padding(.vertical, 4)
    }

    private func load() {
        guard let l = effectiveLedger else { return }
        merchants = (try? appContainer.merchantService.fetchMerchants(for: l, context: modelContext)) ?? []
    }

    private func confirmDelete() {
        guard let merchant = merchantToDelete else { return }
        do {
            try appContainer.merchantService.deleteMerchant(merchant, context: modelContext)
        } catch {
            errorMessage = String(localized: "删除商家失败: \(error.localizedDescription)")
        }
        merchantToDelete = nil
        load()
    }
}
