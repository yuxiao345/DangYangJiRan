import SwiftUI
@preconcurrency import CoreData

// MARK: - Settings (two-column NavigationStack)

struct MacSettingsView: View {
    var body: some View {
        List {
            Section("设置") {
                NavigationLink(value: SettingsNavItem.appearance) {
                    Label("外观", systemImage: "paintbrush")
                }
                NavigationLink(value: SettingsNavItem.ledgers) {
                    Label("账本", systemImage: "books.vertical")
                }
                NavigationLink(value: SettingsNavItem.about) {
                    Label("关于", systemImage: "info.circle")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .designScreen()
        .navigationDestination(for: SettingsNavItem.self) { item in
            switch item {
            case .appearance:
                AppearanceSettingsView()
            case .ledgers:
                MacLedgerSettingsView()
            case .about:
                AboutSettingsView()
            }
        }
    }
}

enum SettingsNavItem: Hashable {
    case appearance, ledgers, about
}

// MARK: - Ledger Settings (replaces SettingsContentColumn + SettingsDetailColumn)

struct MacLedgerSettingsView: View {
    @Environment(AppContainer.self) private var appContainer
    @Environment(\.managedObjectContext) private var modelContext
    @State private var ledgers: [Ledger] = []
    @State private var showCreateSheet = false
    @State private var showDeleteAlert = false
    @State private var ledgerToDelete: Ledger?

    var body: some View {
        List {
            ForEach(ledgers) { ledger in
                NavigationLink(value: ledger) {
                    HStack(spacing: 10) {
                        Image(systemName: ledger.iconName)
                            .foregroundStyle(ledger.isShared ? Color.designPrimaryFixed : Color.designPrimaryContainer)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 4) {
                                Text(ledger.name).font(.body).foregroundStyle(Color.designOnSurface)
                                if ledger.isShared {
                                    Image(systemName: "person.2.fill").font(.caption2)
                                        .foregroundStyle(Color.designPrimaryFixed)
                                }
                            }
                            Text("\(ledger.type.displayName) · \(ledger.defaultCurrencyCode)")
                                .font(.caption).foregroundStyle(Color.designOnSurfaceVariant)
                        }
                        Spacer()
                        if ledger.id == appContainer.currentLedger?.id {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.designPrimaryContainer).fontWeight(.semibold)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .contextMenu {
                    if ledgers.count > 1 && (!ledger.isShared || appContainer.isOwner(of: ledger)) {
                        Button(role: .destructive) {
                            ledgerToDelete = ledger
                            showDeleteAlert = true
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
                }
                .swipeActions(edge: .trailing) {
                    if ledgers.count > 1 && (!ledger.isShared || appContainer.isOwner(of: ledger)) {
                        Button(role: .destructive) {
                            ledgerToDelete = ledger
                            showDeleteAlert = true
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .designScreen()
        .navigationTitle("账本管理")
        .navigationDestination(for: Ledger.self) { ledger in
            MacLedgerDetailView(ledger: ledger)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showCreateSheet = true } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .onAppear(perform: load)
        .sheet(isPresented: $showCreateSheet, onDismiss: { load() }) {
            CreateLedgerSheet { newLedger in
                appContainer.currentLedger = newLedger
                UserDefaults.standard.set(newLedger.id.uuidString, forKey: "currentLedgerID")
                load()
            }
        }
        .alert("确认删除", isPresented: $showDeleteAlert) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) { confirmDelete() }
        } message: {
            if let ledger = ledgerToDelete, ledger.isShared {
                Text("这是共享账本。删除后其他成员将无法访问，数据将保留在你的本地。")
            } else {
                Text("删除账本会同时删除该账本下的所有数据，此操作不可撤销。")
            }
        }
    }

    private func load() {
        let all = (try? appContainer.ledgerService.fetchLedgers(context: modelContext)) ?? []
        ledgers = all.filter { !appContainer.exitedSharedLedgerIDs.contains($0.id) }
    }

    private func confirmDelete() {
        guard let ledger = ledgerToDelete, ledgers.count > 1 else { return }
        let wasCurrent = ledger.id == appContainer.currentLedger?.id
        do {
            try appContainer.ledgerService.deleteLedger(ledger, context: modelContext)
        } catch {
            DiagnosticLog.log("LedgerSettings: delete FAILED \(error.localizedDescription)")
        }
        if wasCurrent, let next = (try? appContainer.ledgerService.fetchLedgers(context: modelContext))?.first {
            appContainer.currentLedger = next
            UserDefaults.standard.set(next.id.uuidString, forKey: "currentLedgerID")
        }
        load()
    }
}

// MARK: - Ledger Detail (categories + members)

struct MacLedgerDetailView: View {
    let ledger: Ledger

    var body: some View {
        List {
            NavigationLink(value: LedgerDetailNavItem.categories(ledger)) {
                Label("分类管理", systemImage: "square.grid.2x2")
            }
            NavigationLink(value: LedgerDetailNavItem.members(ledger)) {
                Label("成员管理", systemImage: "person.2")
            }
        }
        .scrollContentBackground(.hidden)
        .designScreen()
        .navigationTitle(ledger.name)
        .navigationDestination(for: LedgerDetailNavItem.self) { item in
            switch item {
            case .categories(let l): MacCategoryListView(ledger: l)
            case .members(let l): MacMemberListView(ledger: l)
            }
        }
    }
}

enum LedgerDetailNavItem: Hashable {
    case categories(Ledger)
    case members(Ledger)
}

// MARK: - Appearance Settings

struct AppearanceSettingsView: View {
    @AppStorage("appearanceMode") private var appearanceMode: AppearanceMode = .system

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("外观").font(.headline).foregroundStyle(Color.designOnSurface)
                    Picker("外观模式", selection: $appearanceMode) {
                        Text("跟随系统").tag(AppearanceMode.system)
                        Text("浅色").tag(AppearanceMode.light)
                        Text("深色").tag(AppearanceMode.dark)
                    }
                    .pickerStyle(.segmented).frame(maxWidth: 300)
                }
                .padding(24).glassCard(cornerRadius: 16)
            }
            .padding(32).frame(maxWidth: 600)
        }
        .designScreen()
        .navigationTitle("外观")
    }
}

// MARK: - About Settings

struct AboutSettingsView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("关于").font(.headline).foregroundStyle(Color.designOnSurface)
                    Text("钱伲 — 家庭记账与资产管理")
                        .foregroundStyle(Color.designOnSurfaceVariant)
                    if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
                       let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String {
                        Text("版本 \(version) (\(build))")
                            .font(.caption)
                            .foregroundStyle(Color.designOnSurfaceVariant.opacity(0.6))
                    }
                }
                .padding(24).glassCard(cornerRadius: 16)
            }
            .padding(32).frame(maxWidth: 600)
        }
        .designScreen()
        .navigationTitle("关于")
    }
}
