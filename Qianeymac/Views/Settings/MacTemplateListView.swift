import SwiftUI
@preconcurrency import CoreData

struct MacTemplateListView: View {
    @Environment(AppContainer.self) private var appContainer
    @Environment(\.managedObjectContext) private var modelContext
    let ledger: Ledger?
    @State private var templates: [TransactionTemplate] = []
    @State private var showAddSheet = false
    @State private var editingTemplate: TransactionTemplate?
    @State private var showDeleteAlert = false
    @State private var templateToDelete: TransactionTemplate?
    @State private var refreshTrigger = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("模板管理").font(.designHeadlineMedium).foregroundStyle(Color.designOnSurface)
                Spacer()
                Button { showAddSheet = true } label: {
                    Image(systemName: "plus").fontWeight(.semibold)
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 12)

            if templates.isEmpty {
                ContentUnavailableView(
                    "暂无模板",
                    systemImage: "doc.text",
                    description: Text("点击右上角 + 添加模板")
                )
                .padding(24)
                .frame(maxWidth: .infinity)
            } else {
                List {
                    ForEach(templates) { template in
                        templateRow(template)
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
            }
        }
        .frame(minWidth: 460, maxWidth: 650, minHeight: 400)
        .designScreen()
        .onAppear(perform: load)
        .onChange(of: refreshTrigger) { _, _ in load() }
        .alert("删除模板", isPresented: $showDeleteAlert) {
            Button("取消", role: .cancel) { templateToDelete = nil }
            Button("删除", role: .destructive) { confirmDelete() }
        } message: {
            if let t = templateToDelete {
                Text("确定要删除模板「\(t.name)」吗？此操作不可撤销。")
            }
        }
        .sheet(isPresented: $showAddSheet, onDismiss: { refreshTrigger.toggle() }) {
            MacAddEditTemplateView(ledger: effectiveLedger)
        }
        .sheet(item: $editingTemplate, onDismiss: { refreshTrigger.toggle() }) { template in
            MacAddEditTemplateView(editing: template, ledger: effectiveLedger)
        }
    }

    private var effectiveLedger: Ledger? { ledger ?? appContainer.currentLedger }

    private func templateRow(_ t: TransactionTemplate) -> some View {
        HStack(spacing: 10) {
            Image(systemName: t.category?.iconName ?? t.type.systemIcon)
                .foregroundStyle(t.category != nil ? Color(hex: t.category!.colorHex) : Color.designPrimaryContainer)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(t.name)).font(.designBodyMedium)
                if let note = t.note, !note.isEmpty {
                    Text(note)
                        .font(.designBodyCaption)
                        .foregroundStyle(Color.designOnSurfaceVariant)
                        .lineLimit(1)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                CurrencyText(amount: abs(t.amount), currencyCode: t.currencyCode,
                             size: 14, foregroundColor: t.type == .expense ? Color.designAccentRed : Color.designAccentGreen)
                if let account = t.account {
                    Text(LocalizedStringKey(account.name))
                        .font(.designBodyCaption)
                        .foregroundStyle(Color.designOnSurfaceVariant)
                }
            }
            Button { editingTemplate = t } label: {
                Image(systemName: "pencil")
                    .font(.caption).foregroundStyle(.tertiary)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text("编辑模板"))

            Button { templateToDelete = t; showDeleteAlert = true } label: {
                Image(systemName: "trash")
                    .font(.caption).foregroundStyle(.tertiary)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text("删除模板"))
        }
        .padding(.vertical, 4)
    }

    private func load() {
        guard let l = effectiveLedger else { return }
        templates = (try? appContainer.templateService.fetchTemplates(for: l, context: modelContext)) ?? []
    }

    private func confirmDelete() {
        guard let template = templateToDelete else { return }
        try? appContainer.templateService.deleteTemplate(template, context: modelContext)
        templateToDelete = nil
        load()
    }
}
