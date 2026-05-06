import SwiftUI

struct SettingsView: View {
    var body: some View {
        NavigationStack {
            List {
                Section("账本") {
                    NavigationLink("账本管理") {
                        Text("账本列表（Phase 1）")
                    }
                    NavigationLink("成员管理") {
                        Text("成员列表（Phase 3）")
                    }
                }
                Section("安全") {
                    Label("Face ID / Touch ID 锁", systemImage: "lock")
                }
                Section("外观") {
                    Label("深色模式", systemImage: "moon")
                }
            }
            .navigationTitle("设置")
        }
    }
}
