import SwiftUI
import SwiftData

struct SplitFormView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appContainer: AppContainer

    let transaction: Transaction
    let ledger: Ledger

    @State private var splitType: SplitType = .equal
    @State private var note: String = ""
    @State private var selectedMembers: Set<UUID> = []
    @State private var fixedAmounts: [UUID: Decimal] = [:]
    @State private var members: [Member] = []

    private var amount: Decimal { abs(transaction.amount) }

    var body: some View {
        NavigationStack {
            Form {
                Section("交易信息") {
                    HStack {
                        Text("金额")
                        Spacer()
                        Text(amount, format: .currency(code: transaction.currencyCode))
                            .foregroundStyle(.secondary)
                    }
                    if let note = transaction.note, !note.isEmpty {
                        HStack {
                            Text("备注")
                            Spacer()
                            Text(note).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                }

                Section("分摊方式") {
                    Picker("方式", selection: $splitType) {
                        ForEach(SplitType.allCases, id: \.self) { t in
                            Text(t.displayName).tag(t)
                        }
                    }
                }

                Section("选择成员") {
                    ForEach(members) { member in
                        HStack {
                            Image(systemName: member.avatar)
                                .foregroundStyle(.blue)
                            Text(member.name)
                            Spacer()
                            if selectedMembers.contains(member.id) {
                                Image(systemName: "checkmark").foregroundStyle(.blue)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if selectedMembers.contains(member.id) {
                                selectedMembers.remove(member.id)
                                fixedAmounts.removeValue(forKey: member.id)
                            } else {
                                selectedMembers.insert(member.id)
                            }
                        }
                    }
                    if members.isEmpty {
                        Text("暂无成员，请先在成员管理中创建").foregroundStyle(.secondary)
                    }
                }

                if !selectedMembers.isEmpty && splitType != .equal {
                    Section("每人金额") {
                        ForEach(selectedMembersArray) { member in
                            HStack {
                                Text(member.name)
                                Spacer()
                                TextField("0.00", value: binding(for: member.id), format: .number)
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                                    .frame(width: 120)
                            }
                        }
                        if splitType == .percentage {
                            Text("合计: \(totalSelectedAmount, format: .number)%")
                                .foregroundStyle(totalSelectedAmount == 100 ? AnyShapeStyle(.secondary) : AnyShapeStyle(.red))
                        } else {
                            Text("合计: ¥\(totalSelectedAmount, format: .number)")
                                .foregroundStyle(totalSelectedAmount == amount ? AnyShapeStyle(.secondary) : AnyShapeStyle(.red))
                        }
                    }
                }

                if splitType == .equal && !selectedMembers.isEmpty {
                    Section {
                        HStack {
                            Text("每人")
                            Spacer()
                            Text(amount / Decimal(selectedMembers.count), format: .currency(code: transaction.currencyCode))
                                .foregroundStyle(.secondary)
                        }
                    } header: {
                        Text("均分金额")
                    }
                }

                Section("备注") {
                    TextField("分摊备注（可选）", text: $note)
                }
            }
            .navigationTitle("创建分摊")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("创建") { createSplit() }
                        .disabled(selectedMembers.isEmpty || !isAmountValid)
                }
            }
            .task { loadMembers() }
        }
    }

    private var selectedMembersArray: [Member] {
        members.filter { selectedMembers.contains($0.id) }
    }

    private var totalSelectedAmount: Decimal {
        selectedMembersArray.reduce(0) { sum, member in
            sum + (fixedAmounts[member.id] ?? 0)
        }
    }

    private var isAmountValid: Bool {
        if splitType == .equal { return true }
        if splitType == .percentage { return totalSelectedAmount == 100 }
        return totalSelectedAmount == amount
    }

    private func binding(for memberID: UUID) -> Binding<Decimal> {
        Binding(
            get: { fixedAmounts[memberID] ?? 0 },
            set: { fixedAmounts[memberID] = $0 }
        )
    }

    private func loadMembers() {
        members = (try? appContainer.memberService.fetchMembers(for: ledger, context: modelContext)) ?? []
    }

    private func createSplit() {
        let membersList = selectedMembersArray
        let amounts: [Decimal]?
        switch splitType {
        case .equal:
            let share = amount / Decimal(membersList.count)
            amounts = Array(repeating: share, count: membersList.count)
        case .percentage:
            amounts = membersList.map { amount * (fixedAmounts[$0.id] ?? 0) / 100 }
        case .fixed:
            amounts = membersList.map { fixedAmounts[$0.id] ?? 0 }
        }

        guard let splitService = appContainer.splitService else { return }
        do {
            _ = try splitService.createSplit(
                totalAmount: amount,
                currencyCode: transaction.currencyCode,
                splitType: splitType,
                members: membersList,
                amounts: amounts,
                note: note.isEmpty ? nil : note,
                date: transaction.date,
                transaction: transaction,
                ledger: ledger,
                context: modelContext
            )
            dismiss()
        } catch {
            Logger.error("创建分摊失败: \(error)")
        }
    }
}
