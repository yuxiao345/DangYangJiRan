import SwiftUI
@preconcurrency import CoreData

struct CreateLedgerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var modelContext
    @Environment(AppContainer.self) private var appContainer

    var onDone: ((Ledger) -> Void)?

    @State private var name = ""
    @State private var ledgerType: LedgerType = .family
    @State private var currencyCode = "CNY"
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("账本信息") {
                    TextField("账本名称", text: $name)
                        .accessibilityIdentifier("create-ledger-name-field")
                    Picker("类型", selection: $ledgerType) {
                        ForEach(LedgerType.allCases, id: \.self) { type in
                            Label(type.displayName, systemImage: type.systemIcon)
                                .tag(type)
                        }
                    }
                    .accessibilityIdentifier("create-ledger-type-picker")
                    Picker("默认货币", selection: $currencyCode) {
                        Text("人民币 (CNY)").tag("CNY")
                        Text("美元 (USD)").tag("USD")
                        Text("欧元 (EUR)").tag("EUR")
                        Text("日元 (JPY)").tag("JPY")
                    }
                    .accessibilityIdentifier("create-ledger-currency-picker")
                }
            }
            .navigationTitle("创建账本")
            .errorAlert("创建失败", message: $errorMessage)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("创建") {
                        createLedger()
                    }
                    .disabled(name.isEmpty)
                    .accessibilityIdentifier("create-ledger-save-button")
                }
            }
            .accessibilityIdentifier("create-ledger-view")
        }
    }

    private func createLedger() {
        do {
            let ledger = try appContainer.ledgerService.createLedger(
                name: name,
                type: ledgerType,
                currencyCode: currencyCode,
                context: modelContext
            )
            appContainer.categoryService.seedDefaults(ledger: ledger, context: modelContext)
            MerchantSeeder.seed(modelContext: modelContext, ledger: ledger)
            appContainer.currentLedger = ledger
            UserDefaults.standard.set(ledger.id.uuidString, forKey: "currentLedgerID")
            onDone?(ledger)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
