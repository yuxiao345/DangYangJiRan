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
                                Text(ledger.name).font(.designBodyMedium).foregroundStyle(Color.designOnSurface)
                                if ledger.isShared {
                                    Image(systemName: "person.2.fill").font(.designBodyCaption)
                                        .foregroundStyle(Color.designPrimaryFixed)
                                }
                            }
                            Text("\(ledger.type.displayName) · \(ledger.defaultCurrencyCode)")
                                .font(.designBodyCaption).foregroundStyle(Color.designOnSurfaceVariant)
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

// MARK: - Appearance Settings

struct AppearanceSettingsView: View {
    @AppStorage("appearanceMode") private var appearanceMode: AppearanceMode = .system

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                // Section: Appearance Mode
                VStack(alignment: .leading, spacing: 12) {
                    Text("外观模式").font(.designLabel).foregroundStyle(Color.designOnSurfaceVariant)

                    HStack(spacing: 16) {
                        appearanceOption(.system)
                        appearanceOption(.light)
                        appearanceOption(.dark)
                    }
                }

                Spacer()
            }
            .padding(32)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .designScreen()
    }

    // MARK: - Option Card

    private func appearanceOption(_ mode: AppearanceMode) -> some View {
        let isSelected = appearanceMode == mode
        return VStack(spacing: 8) {
            // Preview thumbnail
            appearancePreview(mode)
                .frame(width: 128, height: 80)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isSelected ? Color.accentColor : Color.designOnSurfaceVariant.opacity(0.15), lineWidth: isSelected ? 2 : 1)
                )
                .shadow(color: .black.opacity(0.06), radius: 3, y: 2)

            // Radio + label
            HStack(spacing: 6) {
                Image(systemName: isSelected ? "circle.inset.filled" : "circle")
                    .font(.system(size: 12))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.designOnSurfaceVariant.opacity(0.5))
                Text(mode.displayName)
                    .font(.designBodyCaption)
                    .foregroundStyle(isSelected ? Color.designOnSurface : Color.designOnSurfaceVariant)
            }
        }
        .onTapGesture { appearanceMode = mode }
        .buttonStyle(.plain)
    }

    // MARK: - Preview Thumbnail

    @ViewBuilder
    private func appearancePreview(_ mode: AppearanceMode) -> some View {
        let bgColor: Color = {
            switch mode {
            case .light: Color.white
            case .dark: Color(red: 0.15, green: 0.15, blue: 0.17)
            case .system: Color(red: 0.85, green: 0.85, blue: 0.88) // gradient-like
            }
        }()

        let windowBg: Color = {
            switch mode {
            case .light: Color(red: 0.95, green: 0.95, blue: 0.97)
            case .dark: Color(red: 0.12, green: 0.12, blue: 0.14)
            case .system: Color(red: 0.88, green: 0.88, blue: 0.90)
            }
        }()

        let sidebarBg: Color = {
            switch mode {
            case .light: Color(red: 0.92, green: 0.92, blue: 0.94)
            case .dark: Color(red: 0.10, green: 0.10, blue: 0.12)
            case .system: Color(red: 0.84, green: 0.84, blue: 0.87)
            }
        }()

        let toolbarBg: Color = {
            switch mode {
            case .light: Color(red: 0.97, green: 0.97, blue: 0.98)
            case .dark: Color(red: 0.16, green: 0.16, blue: 0.18)
            case .system: Color(red: 0.91, green: 0.91, blue: 0.93)
            }
        }()

        let textFg: Color = {
            switch mode {
            case .light: Color.black.opacity(0.8)
            case .dark: Color.white.opacity(0.85)
            case .system: Color.black.opacity(0.7)
            }
        }()

        ZStack {
            // Window chrome background
            RoundedRectangle(cornerRadius: 8)
                .fill(bgColor)

            VStack(spacing: 0) {
                // Traffic light buttons
                HStack(spacing: 4) {
                    Circle().fill(Color.red.opacity(0.7)).frame(width: 4, height: 4)
                    Circle().fill(Color.orange.opacity(0.6)).frame(width: 4, height: 4)
                    Circle().fill(Color.green.opacity(0.6)).frame(width: 4, height: 4)
                    Spacer()
                }
                .padding(.horizontal, 6)
                .padding(.top, 5)
                .padding(.bottom, 3)

                // Toolbar
                Rectangle().fill(toolbarBg).frame(height: 7)

                // Content area with sidebar mock
                HStack(spacing: 0) {
                    Rectangle().fill(sidebarBg).frame(width: 28)
                    VStack(spacing: 2) {
                        ForEach(0..<3, id: \.self) { i in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(textFg.opacity(0.15))
                                .frame(height: 4)
                                .padding(.horizontal, i == 0 ? 6 : (i == 1 ? 12 : 18))
                        }
                        Spacer()
                    }
                    .padding(.vertical, 6)
                }
            }
        }
    }
}

private extension AppearanceMode {
    var displayName: String {
        switch self {
        case .system: String(localized: "自动")
        case .light: String(localized: "浅色")
        case .dark: String(localized: "深色")
        }
    }
}

// MARK: - About Settings

struct AboutSettingsView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("关于").font(.designHeadlineMedium).foregroundStyle(Color.designOnSurface)
                    Text("钱伲 — 家庭记账与资产管理")
                        .foregroundStyle(Color.designOnSurfaceVariant)
                    if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
                       let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String {
                        Text("版本 \(version) (\(build))")
                            .font(.designBodyCaption)
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
