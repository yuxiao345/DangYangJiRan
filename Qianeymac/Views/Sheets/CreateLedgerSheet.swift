import SwiftUI
@preconcurrency import CoreData

struct CreateLedgerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var modelContext
    @Environment(AppContainer.self) private var appContainer
    @State private var name = ""
    @State private var type: LedgerType = .personal
    @State private var currencyCode = "CNY"

    let onCreated: (Ledger) -> Void

    var body: some View {
        VStack(spacing: 20) {
            Text("新建账本").font(.designHeadlineLarge)
            Form {
                TextField("账本名称", text: $name)
                Picker("类型", selection: $type) {
                    ForEach(LedgerType.allCases, id: \.self) { t in
                        Text(t.displayName).tag(t)
                    }
                }
                Picker("默认货币", selection: $currencyCode) {
                    ForEach(["CNY", "USD", "EUR", "JPY", "GBP", "HKD"], id: \.self) { code in
                        Text(code).tag(code)
                    }
                }
            }
            .formStyle(.grouped)
            HStack(spacing: 12) {
                Button("取消") { dismiss() }.keyboardShortcut(.escape)
                Button("创建") { create() }.keyboardShortcut(.return).disabled(name.isEmpty)
            }
        }
        .padding(24).frame(width: 360, height: 300)
    }

    private func create() {
        let ledger = Ledger(context: modelContext)
        ledger.id = UUID()
        ledger.name = name
        ledger.type = type
        ledger.defaultCurrencyCode = currencyCode
        ledger.iconName = type.systemIcon
        ledger.createdAt = Date.now
        try? modelContext.save()
        onCreated(ledger)
        dismiss()
    }
}

