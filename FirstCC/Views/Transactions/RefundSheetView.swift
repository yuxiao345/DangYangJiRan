import SwiftUI
import SwiftData

struct RefundSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appContainer: AppContainer

    let original: Transaction
    let onDone: () -> Void

    @State private var amount: Decimal = 0
    @State private var date: Date = Date()
    @State private var note: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("原交易金额") {
                        CurrencyText(amount: abs(original.amount), currencyCode: original.currencyCode, font: .body)
                    }
                    LabeledContent("原交易日期") {
                        Text(original.date.formatted(date: .abbreviated, time: .omitted))
                            .foregroundStyle(.secondary)
                    }
                }

                Section("退款信息") {
                    HStack {
                        Text("¥")
                        TextField("退款金额", value: $amount, format: .number)
                            .keyboardType(.decimalPad)
                    }
                    DatePicker("退款日期", selection: $date, displayedComponents: .date)
                    TextField("备注（可选）", text: $note)
                }

                if amount > abs(original.amount) {
                    Section {
                        Label("退款金额超过原交易金额", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                }
            }
            .navigationTitle("退款")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("确认退款") { save() }
                        .disabled(amount <= 0)
                }
            }
            .onAppear {
                amount = abs(original.amount)
            }
        }
    }

    private func save() {
        do {
            try appContainer.transactionService.createRefund(
                for: original,
                amount: amount,
                context: modelContext
            )
            onDone()
            dismiss()
        } catch {
            print("Refund failed: \(error)")
        }
    }
}
