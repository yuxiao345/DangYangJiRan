import SwiftUI
@preconcurrency import CoreData

struct MacRecurringListView: View {
    @Environment(AppContainer.self) private var appContainer
    @Environment(\.managedObjectContext) private var modelContext
    let ledger: Ledger?
    @State private var rules: [RecurringRule] = []
    @State private var showAddSheet = false
    @State private var editingRule: RecurringRule?
    @State private var showDeleteAlert = false
    @State private var ruleToDelete: RecurringRule?
    @State private var refreshTrigger = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("周期账管理").font(.designHeadlineMedium).foregroundStyle(Color.designOnSurface)
                Spacer()
                Button { showAddSheet = true } label: {
                    Image(systemName: "plus").fontWeight(.semibold)
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 12)

            if rules.isEmpty {
                Text("暂无周期账")
                    .foregroundStyle(Color.designOnSurfaceVariant)
                    .padding(24)
                    .frame(maxWidth: .infinity)
            } else {
                List {
                    if !activeRules.isEmpty {
                        Section {
                            ForEach(activeRules) { rule in
                                ruleRow(rule)
                            }
                        } header: {
                            Text("进行中")
                                .font(.designBodyLarge)
                                .foregroundStyle(Color.designPrimaryFixedDim)
                        }
                    }
                    if !pausedRules.isEmpty {
                        Section {
                            ForEach(pausedRules) { rule in
                                ruleRow(rule)
                            }
                        } header: {
                            Text("已暂停")
                                .font(.designBodyLarge)
                                .foregroundStyle(Color.designOnSurfaceVariant)
                        }
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
            }
        }
        .frame(minWidth: 480, maxWidth: 680, minHeight: 400)
        .designScreen()
        .onAppear(perform: load)
        .onChange(of: refreshTrigger) { _, _ in load() }
        .alert("删除周期账", isPresented: $showDeleteAlert) {
            Button("取消", role: .cancel) { ruleToDelete = nil }
            Button("删除", role: .destructive) { confirmDelete() }
        } message: {
            if let r = ruleToDelete, let t = r.template {
                Text("确定要删除周期账「\(t.name)」吗？此操作不可撤销。")
            }
        }
        .sheet(isPresented: $showAddSheet, onDismiss: { refreshTrigger.toggle() }) {
            MacAddEditRecurringView(ledger: effectiveLedger)
        }
        .sheet(item: $editingRule, onDismiss: { refreshTrigger.toggle() }) { rule in
            MacAddEditRecurringView(editing: rule, ledger: effectiveLedger)
        }
    }

    private var effectiveLedger: Ledger? { ledger ?? appContainer.currentLedger }

    private var activeRules: [RecurringRule] { rules.filter(\.isActive) }
    private var pausedRules: [RecurringRule] { rules.filter { !$0.isActive } }

    private func ruleRow(_ rule: RecurringRule) -> some View {
        let t = rule.template
        return HStack(spacing: 10) {
            Image(systemName: t?.category?.iconName ?? t?.type.systemIcon ?? "arrow.triangle.2.circlepath")
                .foregroundStyle(categoryColor(t))
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(LocalizedStringKey(t?.name ?? "周期账")).font(.designBodyMedium)
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.designBodyCaption)
                        .foregroundStyle(Color.designPrimaryContainer)
                }
                HStack(spacing: 4) {
                    Text(frequencyDescription(rule))
                    if !rule.isActive {
                        Text("· 已暂停")
                            .foregroundStyle(.orange)
                    }
                }
                .font(.designBodyCaption)
                .foregroundStyle(.secondary)
                if rule.isActive, let next = rule.nextGenerateDate {
                    Text("下次生成: \(next.formatted(date: .abbreviated, time: .omitted))")
                        .font(.designBodyCaption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                if let t {
                    CurrencyText(
                        amount: t.type == .expense ? -abs(t.amount) : abs(t.amount),
                        currencyCode: t.currencyCode,
                        showSign: true, size: 14,
                        foregroundColor: t.type == .expense ? Color.designAccentRed : Color.designAccentGreen
                    )
                }
                if let account = t?.account {
                    Text(LocalizedStringKey(account.name))
                        .font(.designBodyCaption)
                        .foregroundStyle(Color.designOnSurfaceVariant)
                }
            }
            Image(systemName: rule.isActive ? "pause.circle" : "play.circle")
                .font(.system(size: 16))
                .foregroundStyle(rule.isActive ? .orange : .green)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
                .onTapGesture {
                    try? appContainer.recurringService.toggleActive(for: rule, context: modelContext)
                    refreshTrigger.toggle()
                }
            Image(systemName: "pencil")
                .font(.caption).foregroundStyle(.tertiary)
                .frame(width: 20, height: 20).contentShape(Rectangle())
                .onTapGesture { editingRule = rule }
            Image(systemName: "trash")
                .font(.caption).foregroundStyle(.tertiary)
                .frame(width: 20, height: 20).contentShape(Rectangle())
                .onTapGesture { ruleToDelete = rule; showDeleteAlert = true }
        }
        .padding(.vertical, 4)
        .opacity(rule.isActive ? 1.0 : 0.55)
    }

    private func frequencyDescription(_ rule: RecurringRule) -> String {
        var desc: String
        if rule.interval > 1 {
            desc = String(localized: "每\(String(rule.interval))\(rule.frequency.unitName)")
        } else {
            desc = rule.frequency.displayName
        }
        if let end = rule.endDate {
            desc += String(localized: " · 至\(end.formatted(date: .abbreviated, time: .omitted))")
        }
        return desc
    }

    private func categoryColor(_ t: TransactionTemplate?) -> Color {
        guard let t, let c = t.category else { return .blue }
        return Color(hex: c.colorHex)
    }

    private func load() {
        guard let l = effectiveLedger else { return }
        rules = (try? appContainer.recurringService.fetchRules(for: l, context: modelContext)) ?? []
    }

    private func confirmDelete() {
        guard let rule = ruleToDelete else { return }
        if let t = rule.template {
            try? appContainer.templateService.deleteTemplate(t, context: modelContext)
        }
        ruleToDelete = nil
        load()
    }
}
