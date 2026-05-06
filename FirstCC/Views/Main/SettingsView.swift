import SwiftUI

struct SettingsView: View {
    var body: some View {
        NavigationStack {
            List {
                Section("账本") {
                    NavigationLink("账户管理") {
                        AccountsManagementView()
                    }
                    NavigationLink("成员管理") {
                        MemberListView()
                    }
                    NavigationLink("商家管理") {
                        MerchantListView()
                    }
                    NavigationLink("项目管理") {
                        ProjectListView()
                    }
                    NavigationLink("模板管理") {
                        TemplateListView()
                    }
                    NavigationLink("分类管理") {
                        CategoryListView()
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
