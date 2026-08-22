import SwiftUI
@preconcurrency import CoreData

struct CreateLedgerMacSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var modelContext
    @Environment(AppContainer.self) private var appContainer
    let onDone: () -> Void
    @State private var name = ""
    @State private var currencyCode = "CNY"
    @State private var errorMessage: String?

    private let currencies = ["CNY", "USD", "EUR", "JPY", "GBP", "HKD"]

    var body: some View {
        NavigationStack {
            Form {
                Section("账本信息") {
                    TextField("名称", text: $name)
                    .accessibilityIdentifier("create-ledger-mac-name-field")
                    Picker("货币", selection: $currencyCode) {
                        ForEach(currencies, id: \.self) { c in Text(c).tag(c) }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("新增账本")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("创建") { create() }
                        .disabled(name.isEmpty)
                        .accessibilityIdentifier("create-ledger-mac-save-button")
                }
            }
            .alert("创建失败", isPresented: .constant(errorMessage != nil)) {
                Button("好") { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
        }
        .frame(width: 400, height: 280)
    }

    private func create() {
        do {
            let ledger = try appContainer.ledgerService.createLedger(name: name, type: .personal, currencyCode: currencyCode, context: modelContext)
            appContainer.categoryService.seedDefaults(ledger: ledger, context: modelContext)
            appContainer.currentLedger = ledger
            UserDefaults.standard.set(ledger.id.uuidString, forKey: "currentLedgerID")
            onDone()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
