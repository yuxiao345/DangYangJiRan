import SwiftUI

struct CreateLedgerView: View {
    @Environment(\.dismiss) private var dismiss
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
                        Label(type.rawValue, systemImage: type.systemIcon)
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
                    appContainer.isAuthenticated = true
                    dismiss()
                }
                .disabled(name.isEmpty)
            }
        }
    }
}
