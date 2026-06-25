import SwiftUI
@preconcurrency import CoreData

struct MainSplitView: View {
    @Environment(AppContainer.self) private var appContainer
    @State private var selection: MacNavItem = .dashboard
    @State private var showAddSheet = false
    @State private var allLedgers: [Ledger] = []
    @State private var navPath = NavigationPath()
    @State private var showCreateLedgerSheet = false
    @State private var sidebarWidth: CGFloat = 200

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack(spacing: 0) {
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
                        .foregroundStyle(Color.designOnSurface)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Capsule().fill(Color.designOnSurfaceVariant.opacity(0.08)))
                }
                .menuStyle(.borderlessButton)
                .padding(.leading, 16)

                Spacer()

                Button { showAddSheet = true } label: {
                    Image(systemName: "plus").fontWeight(.semibold)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.borderless)
                .padding(.trailing, 16)
            }
            .frame(height: 44)
            .background(.regularMaterial)

            Divider()

            // Sidebar + Content
            HStack(spacing: 0) {
                sidebar
                    .frame(width: sidebarWidth)
                    .designScreen()

                // Draggable divider
                Color.clear
                    .frame(width: 6)
                    .contentShape(Rectangle())
                    .onHover { inside in
                        inside ? NSCursor.resizeLeftRight.push() : NSCursor.pop()
                    }
                    .gesture(
                        DragGesture()
                            .onChanged { v in sidebarWidth += v.translation.width; sidebarWidth = max(sidebarWidth, 160) }
                            .onEnded { _ in NSCursor.pop() }
                    )

                mainColumnContent
                    .designScreen()
            }
        }
        .onChange(of: selection) { _, _ in navPath.removeLast(navPath.count) }
        .onAppear { loadLedgers() }
        .onChange(of: appContainer.currentLedger?.id) { _, _ in loadLedgers() }
        .onReceive(NotificationCenter.default.publisher(for: .macMenuNavigate)) { notif in
            if let item = notif.object as? MacNavItem { selection = item }
        }
        .sheet(isPresented: $showAddSheet) { MacAddTransactionSheet() }
        .sheet(isPresented: $showCreateLedgerSheet) { CreateLedgerMacSheet { loadLedgers() } }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List {
            ForEach(MacNavItem.allCases) { item in
                HStack(spacing: 10) {
                    Image(systemName: item.icon).frame(width: 20)
                    Text(item.rawValue)
                }
                .font(.designBodyMedium)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .padding(.vertical, 6).padding(.horizontal, 8)
                .background(selection == item ? Color.accentColor.opacity(0.15) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .onTapGesture { if selection != item { selection = item } }
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
            NavigationStack(path: $navPath) { AccountListContent() }
        case .transactions:
            NavigationStack(path: $navPath) { TransactionListContent() }
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
