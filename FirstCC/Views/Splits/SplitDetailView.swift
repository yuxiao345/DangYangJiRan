import SwiftUI
@preconcurrency import CoreData

struct SplitDetailView: View {
    @Environment(\.managedObjectContext) private var modelContext
    @EnvironmentObject private var appContainer: AppContainer

    let splitGroup: SplitGroup
    @State private var showForm = false
    @State private var entries: [SplitEntry] = []

    private var currencyCode: String { splitGroup.currencyCode }
    private var settlementColor: Color {
        switch splitGroup.settlementStatus {
        case .settled: return .green
        case .partial: return .orange
        case .unsettled: return .secondary
        }
    }

    var body: some View {
        List {
            Section("概览") {
                HStack {
                    Text("总金额")
                    Spacer()
                    Text(splitGroup.totalAmount, format: .currency(code: currencyCode))
                }
                HStack {
                    Text("分摊方式")
                    Spacer()
                    Text(splitGroup.splitType.displayName).foregroundStyle(.secondary)
                }
                HStack {
                    Text("已付金额")
                    Spacer()
                    Text(splitGroup.totalPaid, format: .currency(code: currencyCode))
                        .foregroundStyle(Color.designPrimaryFixedDim)
                }
                HStack {
                    Text("剩余")
                    Spacer()
                    Text(splitGroup.remainingAmount, format: .currency(code: currencyCode))
                        .foregroundStyle(splitGroup.remainingAmount > 0 ? .red : .green)
                }
                HStack {
                    Text("状态")
                    Spacer()
                    Text(splitGroup.settlementStatus.displayName)
                        .foregroundStyle(settlementColor)
                        .fontWeight(.medium)
                }
            }

            Section("明细") {
                ForEach(entries) { entry in
                    SplitEntryRowView(entry: entry) {
                        toggleEntry(entry)
                    }
                }
            }

            if splitGroup.settlementStatus != .settled {
                Section {
                    Button {
                        settleAll()
                    } label: {
                        Label("一键结算", systemImage: "checkmark.circle")
                    }
                    .disabled(splitGroup.entries?.isEmpty ?? true)
                }
            }

            if let note = splitGroup.note, !note.isEmpty {
                Section("备注") {
                    Text(note).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("分摊详情")
        .navigationBarTitleDisplayMode(.inline)
        .task { loadEntries() }
        .onReceive(NotificationCenter.default.publisher(for: .transactionDidChange)) { _ in
            loadEntries()
        }
    }

    private func loadEntries() {
        entries = Array(splitGroup.entries ?? Set())
    }

    private func toggleEntry(_ entry: SplitEntry) {
        if entry.isPaid {
            entry.isPaid = false
            entry.paidDate = nil
        } else {
            entry.isPaid = true
            entry.paidDate = Date()
        }
        try? modelContext.save()
        loadEntries()
    }

    private func settleAll() {
        guard let splitService = appContainer.splitService else { return }
        try? splitService.settleSplit(splitGroup, context: modelContext)
        loadEntries()
    }
}
