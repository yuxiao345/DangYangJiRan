import SwiftUI
import SwiftData

struct PendingReimbursementView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appContainer: AppContainer
    @State private var expenses: [Transaction] = []
    @State private var selectedIDs: Set<UUID> = []
    @State private var showSettleSheet = false

    let ledger: Ledger?
    private var effectiveLedger: Ledger? { ledger ?? appContainer.currentLedger }

    init(ledger: Ledger? = nil) {
        self.ledger = ledger
    }

    var body: some View {
        List {
            if expenses.isEmpty {
                Text("暂无待报销记录")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(expenses) { expense in
                    HStack {
                        Image(systemName: selectedIDs.contains(expense.id)
                              ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(selectedIDs.contains(expense.id) ? .blue : .secondary)
                            .font(.title3)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(LocalizedStringKey(expense.category?.name ?? ""))
                                .font(.designBodyMedium)
                            if let note = expense.note, !note.isEmpty {
                                Text(note)
                                    .font(.designBodySmall)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            CurrencyText(amount: abs(expense.amount), currencyCode: expense.currencyCode, size: 17)
                            Text(expense.date.formatted(date: .abbreviated, time: .omitted))
                                .font(.designBodySmall)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { toggle(expense.id) }
                }
            }
        }
        .navigationTitle("待报销")
        .toolbar {
            if !expenses.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Button("确认报销") {
                        showSettleSheet = true
                    }
                    .disabled(selectedIDs.isEmpty)
                }
            }
        }
        .onAppear(perform: load)
        .sheet(isPresented: $showSettleSheet) {
            AddEditTransactionView(
                prefillType: .income,
                prefillExpenseIDs: Array(selectedIDs)
            )
        }
    }

    private func toggle(_ id: UUID) {
        if selectedIDs.contains(id) { selectedIDs.remove(id) }
        else { selectedIDs.insert(id) }
    }

    private func load() {
        guard let ledger = effectiveLedger else { return }
        let all = (try? appContainer.transactionService.fetchTransactions(for: ledger, context: modelContext, filters: nil)) ?? []
        expenses = all.filter { t in
            t.type == .expense && t.reimbursementStatus == .pending
        }
    }
}
