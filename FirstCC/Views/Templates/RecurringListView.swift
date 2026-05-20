import SwiftUI
import SwiftData

struct RecurringListView: View {
    @EnvironmentObject private var appContainer: AppContainer
    @Environment(\.modelContext) private var modelContext
    @State private var rules: [RecurringRule] = []
    @State private var showAddSheet = false
    @State private var editingRule: RecurringRule?

    let ledger: Ledger?
    private var effectiveLedger: Ledger? { ledger ?? appContainer.currentLedger }

    init(ledger: Ledger? = nil) {
        self.ledger = ledger
    }

    var body: some View {
        List {
            if rules.isEmpty {
                Text("暂无周期账，点击右上角 + 添加")
                    .foregroundStyle(.secondary)
            }

            if !activeRules.isEmpty {
                Section("进行中") {
                    ForEach(activeRules) { rule in
                        ruleRow(rule)
                    }
                }
            }

            if !pausedRules.isEmpty {
                Section("已暂停") {
                    ForEach(pausedRules) { rule in
                        ruleRow(rule)
                    }
                }
            }
        }
        .navigationTitle("周期账管理")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showAddSheet = true } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showAddSheet, onDismiss: { loadRules() }) {
            AddEditRecurringView(ledger: effectiveLedger)
        }
        .sheet(item: $editingRule, onDismiss: { loadRules() }) { rule in
            AddEditRecurringView(editing: rule, ledger: effectiveLedger)
        }
        .task { loadRules() }
    }

    private var activeRules: [RecurringRule] {
        rules.filter { $0.isActive }
    }

    private var pausedRules: [RecurringRule] {
        rules.filter { !$0.isActive }
    }

    private func ruleRow(_ rule: RecurringRule) -> some View {
        let t = rule.template
        return HStack(spacing: 12) {
            Image(systemName: t?.category?.iconName ?? t?.type.systemIcon ?? "arrow.triangle.2.circlepath")
                .font(.title3)
                .foregroundStyle(categoryColor(t))
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(LocalizedStringKey(t?.name ?? "周期账"))
                        .font(.designBodyMedium)
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.designBodySmall)
                        .foregroundStyle(Color.designPrimaryContainer)
                }
                Text(frequencyDescription(rule))
                    .font(.designBodySmall)
                    .foregroundStyle(.secondary)
                if let next = rule.nextGenerateDate {
                    Text("下次生成: \(next.formatted(date: .abbreviated, time: .omitted))")
                        .font(.designBodySmall)
                        .foregroundStyle(.secondary)
                }
                if let t, let generated = t.generatedTransactions, !generated.isEmpty {
                    Text("已生成 \(generated.count) 笔")
                        .font(.designBodySmall)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                if let t {
                    CurrencyText(
                        amount: t.type == .expense ? -abs(t.amount) : abs(t.amount),
                        currencyCode: t.currencyCode,
                        showSign: true,
                        size: 17,
                        foregroundColor: t.type == .expense ? .red : .green
                    )
                }
                if let account = t?.account {
                    Text(LocalizedStringKey(account.name))
                        .font(.designBodySmall)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture { editingRule = rule }
        .swipeActions(edge: .trailing) {
            Button {
                if let t = rule.template {
                    try? appContainer.recurringService.disableRecurring(template: t, context: modelContext)
                    loadRules()
                }
            } label: {
                Label(rule.isActive ? "暂停" : "恢复", systemImage: rule.isActive ? "pause" : "play")
            }
            .tint(rule.isActive ? .orange : .green)

            Button(role: .destructive) {
                if let t = rule.template {
                    try? appContainer.templateService.deleteTemplate(t, context: modelContext)
                    loadRules()
                }
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
    }

    private func frequencyDescription(_ rule: RecurringRule) -> String {
        var desc = ""
        if rule.interval > 1 {
            desc += "每\(rule.interval)"
        }
        desc += rule.frequency.displayName
        if let end = rule.endDate {
            desc += " · 至\(end.formatted(date: .abbreviated, time: .omitted))"
        }
        return desc
    }

    private func categoryColor(_ t: TransactionTemplate?) -> Color {
        guard let t, let c = t.category else { return .blue }
        return Color(hex: c.colorHex)
    }

    private func loadRules() {
        guard let ledger = effectiveLedger else { return }
        rules = (try? appContainer.recurringService.fetchRules(for: ledger, context: modelContext)) ?? []
    }
}
