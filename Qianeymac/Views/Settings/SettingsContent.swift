import SwiftUI
@preconcurrency import CoreData

struct SettingsContentColumn: View {
    @Binding var mainSelection: SettingsMainItem?
    @Binding var selectedLedger: Ledger?
    @Binding var ledgerSubSelection: LedgerSettingsItem?

    var body: some View {
        Group {
            if let ledger = selectedLedger {
                ledgerSubList(ledger)
            } else {
                mainList
            }
        }
    }

    // MARK: Main settings list

    private var mainList: some View {
        List(selection: $mainSelection) {
            ForEach(SettingsMainItem.allCases) { item in
                Label(item.rawValue, systemImage: item.icon)
                    .padding(.vertical, 3)
                    .tag(item)
            }
        }
        .scrollContentBackground(.hidden)
        .designScreen()
    }

    // MARK: Ledger sub-items list

    private func ledgerSubList(_ ledger: Ledger) -> some View {
        List(selection: $ledgerSubSelection) {
            Section {
                ForEach(LedgerSettingsItem.allCases) { item in
                    Label(item.rawValue, systemImage: item.icon)
                        .padding(.vertical, 3)
                        .tag(item)
                }
            } header: {
                HStack {
                    Button {
                        self.selectedLedger = nil
                        self.ledgerSubSelection = nil
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .buttonStyle(.borderless)
                    Text(ledger.name).font(.headline)
                }
                .padding(.bottom, 4)
            }
        }
        .scrollContentBackground(.hidden)
        .designScreen()
    }
}

// MARK: - Settings Detail Column

struct SettingsDetailColumn: View {
    @Environment(AppContainer.self) private var appContainer
    @Environment(\.managedObjectContext) private var modelContext
    @Binding var mainSelection: SettingsMainItem?
    @Binding var selectedLedger: Ledger?
    @Binding var ledgerSubSelection: LedgerSettingsItem?

    var body: some View {
        Group {
            if let main = mainSelection {
                switch main {
                case .appearance:
                    AppearanceSettingsView()
                case .ledgers:
                    if let ledger = selectedLedger, let sub = ledgerSubSelection {
                        ledgerSubDetail(ledger: ledger, sub: sub)
                    } else {
                        LedgerListSettingsView(onSelect: { ledger in
                            selectedLedger = ledger
                            ledgerSubSelection = nil
                        })
                    }
                case .about:
                    AboutSettingsView()
                }
            } else {
                EmptySelectionView(message: "选择设置项")
            }
        }
    }

    @ViewBuilder
    private func ledgerSubDetail(ledger: Ledger, sub: LedgerSettingsItem) -> some View {
        switch sub {
        case .categories:
            MacCategoryListView(ledger: ledger)
        case .members:
            MacMemberListView(ledger: ledger)
        }
    }
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
    }
}

// MARK: - Ledger List Settings

struct LedgerListSettingsView: View {
    @Environment(AppContainer.self) private var appContainer
    @Environment(\.managedObjectContext) private var modelContext
    @State private var ledgers: [Ledger] = []
    @State private var showCreateSheet = false
    @State private var showDeleteAlert = false
    @State private var ledgerToDelete: Ledger?

    let onSelect: (Ledger) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("账本管理").font(.headline).foregroundStyle(Color.designOnSurface)
                    Spacer()
                    Button { showCreateSheet = true } label: {
                        Image(systemName: "plus").fontWeight(.semibold)
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.bottom, 4)

                ForEach(ledgers) { ledger in
                    ledgerRow(ledger)
                }

                if ledgers.isEmpty {
                    Text("暂无账本").foregroundStyle(Color.designOnSurfaceVariant).padding(.top, 20)
                }
            }
            .padding(24).frame(maxWidth: 600)
        }
        .designScreen()
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

    private func ledgerRow(_ ledger: Ledger) -> some View {
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
            if ledgers.count > 1 && (!ledger.isShared || appContainer.isOwner(of: ledger)) {
                Button {
                    ledgerToDelete = ledger
                    showDeleteAlert = true
                } label: {
                    Image(systemName: "trash").foregroundStyle(Color.designAccentRed)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(12)
        .background(Color.designGlassBg.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .contentShape(Rectangle())
        .onTapGesture {
            if ledger.id != appContainer.currentLedger?.id {
                appContainer.currentLedger = ledger
                UserDefaults.standard.set(ledger.id.uuidString, forKey: "currentLedgerID")
            }
            onSelect(ledger)
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
            DiagnosticLog.log("LedgerListSettings: delete FAILED \(error.localizedDescription)")
        }
        if wasCurrent, let next = (try? appContainer.ledgerService.fetchLedgers(context: modelContext))?.first {
            appContainer.currentLedger = next
            UserDefaults.standard.set(next.id.uuidString, forKey: "currentLedgerID")
        }
        load()
    }
}

