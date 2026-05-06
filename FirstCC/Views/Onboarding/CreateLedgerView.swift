import SwiftUI
import SwiftData

struct CreateLedgerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appContainer: AppContainer

    @State private var name = ""
    @State private var ledgerType: LedgerType = .family
    @State private var currencyCode = "CNY"

    var body: some View {
        Form {
            Section("账本信息") {
                TextField("账本名称", text: $name)
                Picker("类型", selection: $ledgerType) {
                    ForEach(LedgerType.allCases, id: \.self) { type in
                        Label(type.displayName, systemImage: type.systemIcon)
                            .tag(type)
                    }
                }
                Picker("默认货币", selection: $currencyCode) {
                    Text("人民币 (CNY)").tag("CNY")
                    Text("美元 (USD)").tag("USD")
                    Text("欧元 (EUR)").tag("EUR")
                    Text("日元 (JPY)").tag("JPY")
                }
            }
        }
        .navigationTitle("创建账本")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("创建") {
                    createLedger()
                }
                .disabled(name.isEmpty)
            }
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
            appContainer.currentLedger = ledger
            dismiss()
        } catch {
            print("Failed to create ledger: \(error)")
        }
    }
}
