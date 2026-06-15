import SwiftUI
@preconcurrency import CoreData

struct MainSplitView: View {
    @Environment(AppContainer.self) private var appContainer
    @State private var selection: MacNavItem = .dashboard
    @State private var selectedAccount: Account?
    @State private var selectedTransaction: Transaction?
    @State private var settingsMainSelection: SettingsMainItem?
    @State private var settingsSelectedLedger: Ledger?
    @State private var settingsLedgerSubSelection: LedgerSettingsItem?
    @State private var showAddSheet = false
    @State private var allLedgers: [Ledger] = []
    @State private var showCreateLedgerSheet = false

    @ContentBuilder
    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
        } detail: {
            mainColumnContent
                .inspector(isPresented: Binding(get: { inspectorShown }, set: { if !$0 { selectedAccount = nil; selectedTransaction = nil; settingsMainSelection = nil } })) {
                    inspectorContent
                }
                .navigationSplitViewColumnWidth(min: 360, ideal: 560)
        }
        .navigationTitle("")
        .toolbar { macToolbar }
        .onAppear { loadLedgers() }
        .onChange(of: appContainer.currentLedger?.id) { _, _ in loadLedgers() }
        .onReceive(NotificationCenter.default.publisher(for: .macMenuNavigate)) { notif in
            if let item = notif.object as? MacNavItem {
                selection = item
                selectedAccount = nil
                selectedTransaction = nil
            }
        }
        .sheet(isPresented: $showAddSheet) {
            MacAddTransactionSheet()
        }
        .sheet(isPresented: $showCreateLedgerSheet) {
            CreateLedgerMacSheet { loadLedgers() }
        }
    }

    @ToolbarContentBuilder
    private var macToolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Menu {
                ForEach(allLedgers) { ledger in
                    Button {
                        appContainer.currentLedger = ledger
                        UserDefaults.standard.set(ledger.id.uuidString, forKey: "currentLedgerID")
                    } label: {
                        if ledger.id == appContainer.currentLedger?.id {
                            Label(ledger.name, systemImage: "checkmark")
                        } else { Text(ledger.name) }
                    }
                }
                if !allLedgers.isEmpty { Divider() }
                Button { showCreateLedgerSheet = true } label: {
                    Label("新增账本", systemImage: "plus")
                }
            } label: {
                Text(appContainer.currentLedger?.name ?? "小金库")
                    .font(.custom("SpaceGrotesk-Bold", fixedSize: 18))
            }.menuStyle(.borderlessButton)
        }
        ToolbarItem(placement: .primaryAction) {
            Button { showAddSheet = true } label: { Image(systemName: "plus") }
        }
        .visibilityPriority(.high) // @available(macOS 27, *)
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List {
            ForEach(MacNavItem.allCases) { item in
                Label(item.rawValue, systemImage: item.icon)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .padding(.vertical, 2)
                    .background(selection == item ? Color.accentColor.opacity(0.15) : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .onTapGesture {
                        if selection != item {
                            selection = item
                            selectedAccount = nil
                            selectedTransaction = nil
                        }
                    }
            }
        }
        .listStyle(.sidebar)
    }

    private var inspectorShown: Bool {
        selectedAccount != nil || selectedTransaction != nil || settingsMainSelection != nil
    }

    // MARK: - Main Column

    @ViewBuilder
    private var mainColumnContent: some View {
        switch selection {
        case .dashboard:
            DashboardContentColumn()
        case .accounts:
            AccountListContent(selection: $selectedAccount)
        case .transactions:
            TransactionListContent(selection: $selectedTransaction)
        case .reports:
            ReportTypeContent()
        case .settings:
            SettingsContentColumn(
                mainSelection: $settingsMainSelection,
                selectedLedger: $settingsSelectedLedger,
                ledgerSubSelection: $settingsLedgerSubSelection
            )
        }
    }

    @ViewBuilder
    private var inspectorContent: some View {
        switch selection {
        case .accounts:
            if let account = selectedAccount {
                AccountDetailContent(account: account)
                    .toolbar { ToolbarItem(placement: .destructiveAction) { Button("关闭") { selectedAccount = nil } } }
            }
        case .transactions:
            if let transaction = selectedTransaction {
                TransactionDetailContent(transaction: transaction)
                    .toolbar { ToolbarItem(placement: .destructiveAction) { Button("关闭") { selectedTransaction = nil } } }
            }
        case .settings:
            if settingsMainSelection != nil {
                SettingsDetailColumn(
                    mainSelection: $settingsMainSelection,
                    selectedLedger: $settingsSelectedLedger,
                    ledgerSubSelection: $settingsLedgerSubSelection
                )
            }
        default: EmptyView()
        }
    }

    private func loadLedgers() {
        let ctx = appContainer.viewContext
        let req = NSFetchRequest<Ledger>(entityName: "Ledger")
        req.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        allLedgers = (try? ctx.fetch(req)) ?? []
    }
}

