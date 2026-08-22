import SwiftUI

struct MainTabView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            DashboardView()
                .tabItem {
                    Label("总览", systemImage: "rectangle.grid.1x2")
                }
                .tag(0)
                .accessibilityIdentifier("tab-dashboard")

            NavigationStack {
                AccountListView()
            }
                .tabItem {
                    Label("账户", systemImage: "creditcard")
                }
                .tag(1)
                .accessibilityIdentifier("tab-accounts")

            NavigationStack {
                TransactionListView()
            }
                .tabItem {
                    Label("流水", systemImage: "list.bullet")
                }
                .tag(2)
                .accessibilityIdentifier("tab-transactions")

            ReportsView()
                .tabItem {
                    Label("报表", systemImage: "chart.bar")
                }
                .tag(3)
                .accessibilityIdentifier("tab-reports")

            SettingsView()
                .tabItem {
                    Label("设置", systemImage: "gearshape")
                }
                .tag(4)
                .accessibilityIdentifier("tab-settings")
        }
        .tint(Color.designAccentGreen)
    }
}
