import SwiftUI
@preconcurrency import CoreData

private enum AppTab: Hashable {
    case dashboard, accounts, transactions, reports, settings
}

struct MainTabView: View {
    @Environment(\.managedObjectContext) private var modelContext
    @State private var selectedTab: AppTab = .dashboard

    var body: some View {
        TabView(selection: $selectedTab) {
            DashboardView()
                .tabItem {
                    Label("总览", systemImage: "rectangle.grid.1x2")
                }
                .tag(AppTab.dashboard)
                .accessibilityIdentifier("tab-dashboard")

            NavigationStack {
                AccountListView()
            }
                .tabItem {
                    Label("账户", systemImage: "creditcard")
                }
                .tag(AppTab.accounts)
                .accessibilityIdentifier("tab-accounts")

            NavigationStack {
                TransactionListView()
            }
            .navigationDestination(for: NSManagedObjectID.self) { id in
                if let tx = modelContext.object(with: id) as? Transaction {
                    TransactionDetailView(transaction: tx)
                }
            }
                .tabItem {
                    Label("流水", systemImage: "list.bullet")
                }
                .tag(AppTab.transactions)
                .accessibilityIdentifier("tab-transactions")

            ReportsView()
                .tabItem {
                    Label("报表", systemImage: "chart.bar")
                }
                .tag(AppTab.reports)
                .accessibilityIdentifier("tab-reports")

            SettingsView()
                .tabItem {
                    Label("设置", systemImage: "gearshape")
                }
                .tag(AppTab.settings)
                .accessibilityIdentifier("tab-settings")
        }
        .tint(Color.designAccentGreen)
    }
}
