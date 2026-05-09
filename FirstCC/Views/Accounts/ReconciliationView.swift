import SwiftUI
import SwiftData

/// Review and confirm bank reconciliation after CSV import
struct ReconciliationView: View {
    @EnvironmentObject private var appContainer: AppContainer
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let account: Account
    let bankItems: [BankTransactionItem]
    let year: Int
    let month: Int

    @State private var matches: [ReconciliationMatch] = []
    @State private var isConfirming = false

    // Track user-modified actions per match
    @State private var userActions: [UUID: UserAction] = [:]

    enum UserAction {
        case confirmed(Transaction)
        case ignored
        case createNew
    }

    var body: some View {
        List {
            summarySection
            matchedSection
            conflictedSection
            unmatchedSection
        }
        .navigationTitle("对账核对")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(action: confirmReconciliation) {
                    if isConfirming {
                        ProgressView()
                    } else {
                        Text("确认对账")
                    }
                }
                .disabled(isConfirming || !hasAnyAction)
            }
        }
        .task { runMatching() }
    }

    // MARK: - Summary

    private var summarySection: some View {
        Section("匹配概览") {
            HStack(spacing: 20) {
                statBox("银行笔数", value: "\(bankItems.count)", color: .primary)
                statBox("已匹配", value: "\(matchedCount)", color: .green)
                statBox("冲突", value: "\(conflictedCount)", color: .orange)
                statBox("未匹配", value: "\(unmatchedCount)", color: .red)
            }
            .padding(.vertical, 4)

            let bankTotal = bankItems.compactMap { $0.amount }.reduce(Decimal.zero, +)
            LabeledContent("银行账单总额") {
                CurrencyText(amount: bankTotal, currencyCode: account.currencyCode, showSign: false, font: .body)
            }
        }
    }

    private func statBox(_ label: String, value: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Matched

    @ViewBuilder
    private var matchedSection: some View {
        let items = matches.filter { $0.status == .matched }
        if !items.isEmpty {
            Section("已匹配 (\(items.count))") {
                ForEach(items) { match in
                    matchRow(match, isMatched: true)
                }
            }
        }
    }

    @ViewBuilder
    private var conflictedSection: some View {
        let items = matches.filter { $0.status == .conflicted }
        if !items.isEmpty {
            Section("冲突 (\(items.count))") {
                ForEach(items) { match in
                    matchRow(match, isMatched: false)
                }
            }
        }
    }

    @ViewBuilder
    private var unmatchedSection: some View {
        let items = matches.filter { $0.status == .unmatched }
        if !items.isEmpty {
            Section("未匹配 (\(items.count))") {
                ForEach(items) { match in
                    matchRow(match, isMatched: false)
                }
            }
        }
    }

    // MARK: - Row

    private func matchRow(_ match: ReconciliationMatch, isMatched: Bool) -> some View {
        let action = userActions[match.id]

        return VStack(alignment: .leading, spacing: 6) {
            // Bank item info
            HStack {
                if let date = match.bankItem.transDate {
                    Text(date, format: .dateTime.month(.twoDigits).day(.twoDigits))
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                Spacer()
                if let amount = match.bankItem.amount {
                    Text(amount, format: .number.precision(.fractionLength(2)))
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundStyle(.red)
                }
                statusBadge(match, action: action)
            }

            if let desc = match.bankItem.desc, !desc.isEmpty {
                Text(desc)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let action {
                actionInfo(action)
            }

            // Match selection / action buttons
            if match.status != .matched || action != nil {
                actionButtons(match, action: action)
            }
        }
        .padding(.vertical, 4)
    }

    private func statusBadge(_ match: ReconciliationMatch, action: UserAction?) -> some View {
        Group {
            if let action {
                switch action {
                case .confirmed: Label("已确认", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                case .ignored: Label("已忽略", systemImage: "eye.slash.fill").foregroundStyle(.secondary)
                case .createNew: Label("将创建", systemImage: "plus.circle.fill").foregroundStyle(.blue)
                }
            } else if match.status == .matched {
                Label("自动匹配", systemImage: "link")
                    .foregroundStyle(.green)
            } else if match.status == .conflicted {
                Label("有冲突", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            } else {
                Label("未匹配", systemImage: "questionmark.circle")
                    .foregroundStyle(.red)
            }
        }
        .font(.caption)
    }

    @ViewBuilder
    private func actionInfo(_ action: UserAction) -> some View {
        switch action {
        case .confirmed(let txn):
            HStack {
                Image(systemName: "arrow.trianglehead.swap")
                    .font(.caption2)
                Text("App: ¥\(abs(txn.amount).formatted(.number.precision(.fractionLength(2))))")
                    .font(.caption2)
                if let note = txn.note, !note.isEmpty {
                    Text(note)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        case .ignored, .createNew:
            EmptyView()
        }
    }

    @ViewBuilder
    private func actionButtons(_ match: ReconciliationMatch, action: UserAction?) -> some View {
        HStack(spacing: 8) {
            if match.status == .matched, action == nil {
                Button {
                    if let txn = match.candidates.first {
                        userActions[match.id] = .confirmed(txn)
                    }
                } label: {
                    Label("确认匹配", systemImage: "checkmark")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .tint(.green)
            }

            if match.status == .conflicted, action == nil {
                ForEach(Array(match.candidates.enumerated()), id: \.element.id) { (i, txn) in
                    Button {
                        userActions[match.id] = .confirmed(txn)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Label(
                                "¥\(abs(txn.amount).formatted(.number.precision(.fractionLength(2))))",
                                systemImage: "\(i + 1).circle"
                            )
                            HStack(spacing: 6) {
                                Text(txn.date, format: .dateTime.month(.twoDigits).day(.twoDigits))
                                    .font(.caption2)
                                if let note = txn.note, !note.isEmpty {
                                    Text(note)
                                        .font(.caption2)
                                        .lineLimit(1)
                                }
                            }
                            .foregroundStyle(.secondary)
                            // Match reason vs bank item
                            matchReasonText(bankItem: match.bankItem, candidate: txn)
                        }
                    }
                    .buttonStyle(.bordered)
                    .tint(.blue)
                }
            }

            if action == nil {
                Button {
                    userActions[match.id] = .ignored
                } label: {
                    Label("忽略", systemImage: "eye.slash")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .tint(.secondary)
            }

            if action != nil {
                Button {
                    userActions.removeValue(forKey: match.id)
                } label: {
                    Label("撤销", systemImage: "arrow.uturn.backward")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .tint(.orange)
            }
        }
    }

    // MARK: - Computed

    private var matchedCount: Int {
        matches.count { $0.status == .matched }
    }

    private var conflictedCount: Int {
        matches.count { $0.status == .conflicted }
    }

    private var unmatchedCount: Int {
        matches.count { $0.status == .unmatched }
    }

    private var hasAnyAction: Bool {
        !userActions.isEmpty || matchedCount > 0
    }

    /// Show why two candidates conflict — date diff + amount diff
    private func matchReasonText(bankItem: BankTransactionItem, candidate: Transaction) -> Text {
        let calendar = Calendar.current
        let dayDiff: Int = {
            guard let bankDate = bankItem.transDate else { return 99 }
            let bankDay = calendar.startOfDay(for: bankDate)
            let txnDay = calendar.startOfDay(for: candidate.date)
            return calendar.dateComponents([.day], from: bankDay, to: txnDay).day ?? 99
        }()
        let amountDiff = abs((bankItem.amount ?? 0) - candidate.amount)

        let parts: [String] = [
            dayDiff == 0 ? "日期相同" : "日期差\(abs(dayDiff))天",
            amountDiff == 0 ? "金额相同" : "金额差\(amountDiff.formatted(.number.precision(.fractionLength(2))))",
        ]
        return Text(parts.joined(separator: "，"))
            .font(.caption2)
            .foregroundStyle(.orange)
    }

    // MARK: - Actions

    private func runMatching() {
        let service = ReconciliationServiceImpl()
        matches = service.matchItems(bankItems, for: account, year: year, month: month, context: modelContext)
    }

    private func confirmReconciliation() {
        guard let ledger = appContainer.currentLedger else { return }
        isConfirming = true

        // Apply user actions to matches
        var finalMatches = matches
        for i in finalMatches.indices {
            if let action = userActions[finalMatches[i].id] {
                switch action {
                case .confirmed(let txn):
                    finalMatches[i].userAction = .confirmed(txn)
                case .ignored:
                    finalMatches[i].userAction = .ignored
                case .createNew:
                    finalMatches[i].userAction = .createNew
                }
            } else if finalMatches[i].status == .matched, let txn = finalMatches[i].candidates.first {
                finalMatches[i].userAction = .confirmed(txn)
            }
        }

        let bankTotal = bankItems.compactMap { $0.amount }.reduce(Decimal.zero, +)
        let service = ReconciliationServiceImpl()

        do {
            _ = try service.confirmReconciliation(
                matches: finalMatches,
                account: account,
                year: year,
                month: month,
                bankAmount: bankTotal,
                ledger: ledger,
                context: modelContext
            )
            dismiss()
        } catch {
            isConfirming = false
        }
    }
}
