import SwiftUI
@preconcurrency import CoreData

struct MainSplitView: View {
    @Environment(AppContainer.self) private var appContainer
    @State private var selection: MacNavItem = .dashboard
    @State private var showAddSheet = false
    @State private var allLedgers: [Ledger] = []
    @State private var showCreateLedgerSheet = false

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
        } detail: {
            NavigationStack {
                mainColumnContent
            }
            .navigationSplitViewColumnWidth(min: 400, ideal: 600)
        }
        .navigationTitle("")
        .toolbar { macToolbar }
        .onAppear { loadLedgers() }
        .onChange(of: appContainer.currentLedger?.id) { _, _ in loadLedgers() }
        .onReceive(NotificationCenter.default.publisher(for: .macMenuNavigate)) { notif in
            if let item = notif.object as? MacNavItem {
                selection = item
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
                Text("  " + (appContainer.currentLedger?.name ?? "小金库"))
                    .font(.custom("SpaceGrotesk-Bold", fixedSize: 18))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.designGlassBg.opacity(0.5))
                    )
            }
            .menuStyle(.borderlessButton)
        }
        ToolbarItem(placement: .primaryAction) {
            Button { showAddSheet = true } label: { Image(systemName: "plus") }
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List {
            ForEach(MacNavItem.allCases) { item in
                HStack(spacing: 10) {
                    Image(systemName: item.icon)
                        .frame(width: 20)
                    Text(item.rawValue)
                }
                .font(.designBodyMedium)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .padding(.vertical, 6)
                .padding(.horizontal, 8)
                .background(selection == item ? Color.accentColor.opacity(0.15) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .onTapGesture {
                    if selection != item {
                        selection = item
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    // MARK: - Main Column

    @ViewBuilder
    private var mainColumnContent: some View {
        switch selection {
        case .dashboard:
            DashboardContentColumn()
        case .accounts:
            AccountListContent()
        case .transactions:
            TransactionListContent()
        case .reports:
            ReportTypeContent()
        }
    }

    private func loadLedgers() {
        let ctx = appContainer.viewContext
        let req = NSFetchRequest<Ledger>(entityName: "Ledger")
        req.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        allLedgers = (try? ctx.fetch(req)) ?? []
    }
}
