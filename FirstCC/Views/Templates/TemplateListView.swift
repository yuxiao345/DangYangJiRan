import SwiftUI
@preconcurrency import CoreData

struct TemplateListView: View {
    @EnvironmentObject private var appContainer: AppContainer
    @Environment(\.managedObjectContext) private var modelContext
    @State private var templates: [TransactionTemplate] = []
    @State private var showAddSheet = false
    @State private var editingTemplate: TransactionTemplate?

    let ledger: Ledger?
    private var effectiveLedger: Ledger? { ledger ?? appContainer.currentLedger }

    init(ledger: Ledger? = nil) {
        self.ledger = ledger
    }

    var body: some View {
        List {
            if templates.isEmpty {
                Text("暂无模板，点击右上角 + 添加")
                    .foregroundStyle(.secondary)
            }
            ForEach(templates) { template in
                templateRow(template)
                    .contentShape(Rectangle())
                    .onTapGesture { editingTemplate = template }
                    .swipeActions {
                        Button(role: .destructive) {
                            try? appContainer.templateService.deleteTemplate(template, context: modelContext)
                            loadTemplates()
                        } label: { Label("删除", systemImage: "trash") }
                    }
            }
        }
        .navigationTitle("模板管理")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showAddSheet = true } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showAddSheet, onDismiss: { loadTemplates() }) {
            AddEditTemplateView(ledger: effectiveLedger)
        }
        .sheet(item: $editingTemplate, onDismiss: { loadTemplates() }) { template in
            AddEditTemplateView(editing: template, ledger: effectiveLedger)
        }
        .onAppear(perform: loadTemplates)
    }

    private func templateRow(_ t: TransactionTemplate) -> some View {
        HStack(spacing: 12) {
            Image(systemName: t.category?.iconName ?? t.type.systemIcon)
                .font(.title3)
                .foregroundStyle(t.category != nil
                    ? Color(hex: t.category!.colorHex)
                    : .blue)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(LocalizedStringKey(t.name))
                        .font(.designBodyMedium)
                }
                if let note = t.note, !note.isEmpty {
                    Text(note)
                        .font(.designBodySmall)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                amountView(t)
                if let account = t.account {
                    Text(LocalizedStringKey(account.name))
                        .font(.designBodySmall)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func amountView(_ t: TransactionTemplate) -> some View {
        CurrencyText(
            amount: abs(t.amount),
            currencyCode: t.currencyCode,
            size: 17,
            foregroundColor: t.type == .expense ? Color.red : Color.green
        )
    }

    private func loadTemplates() {
        guard let ledger = effectiveLedger else { return }
        templates = (try? appContainer.templateService.fetchTemplates(for: ledger, context: modelContext)) ?? []
    }
}
