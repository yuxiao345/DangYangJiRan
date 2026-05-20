import SwiftUI

struct SettingsView: View {
    var body: some View {
        NavigationStack {
            List {
                Section("账本") {
                    NavigationLink("账本管理") {
                        LedgerListView()
                    }
                }
                Section("安全") {
                    Label("Face ID / Touch ID 锁", systemImage: "lock")
                }
                Section("外观") {
                    Label("深色模式", systemImage: "moon")
                }
            }
            .designScreen()
            .scrollContentBackground(.hidden)
            .navigationTitle("设置")
        }
    }
}
