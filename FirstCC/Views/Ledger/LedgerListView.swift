import SwiftUI
@preconcurrency import CoreData

struct LedgerListView: View {
    @Environment(\.managedObjectContext) private var modelContext
    @EnvironmentObject private var appContainer: AppContainer
    @State private var ledgers: [Ledger] = []
    @State private var showCreateSheet = false
    @State private var showDeleteAlert = false
    @State private var ledgerToDelete: Ledger?
    @State private var settingsLedger: Ledger?

    var body: some View {
        List {
            ForEach(ledgers) { ledger in
                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Image(systemName: ledger.iconName)
                                .foregroundStyle(Color.designPrimaryContainer)
                            Text(ledger.name)
                                .font(.designBodyMedium)
                        }
                        HStack(spacing: 6) {
                            Text(ledger.type.displayName)
                                .font(.designBodySmall)
                                .foregroundStyle(Color.designOnSurfaceVariant)
                            Text("·")
                                .foregroundStyle(Color.designOnSurfaceVariant)
                            Text(ledger.defaultCurrencyCode)
                                .font(.designBodySmall)
                                .foregroundStyle(Color.designOnSurfaceVariant)
                        }
                    }
                    Spacer(minLength: 0)

                    Button {
                        openSettings(ledger)
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.designBodyMedium)
                            .foregroundStyle(Color.designOnSurfaceVariant)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.borderless)

                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.designPrimaryContainer)
                        .fontWeight(.semibold)
                        .opacity(ledger.id == appContainer.currentLedger?.id ? 1 : 0)
                        .frame(width: 24)
                }
                .contentShape(Rectangle())
                .onTapGesture { switchLedger(ledger) }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    if ledgers.count > 1 {
                        Button(role: .destructive) {
                            ledgerToDelete = ledger
                            showDeleteAlert = true
                        } label: {
                            Text("删除")
                        }
                    }
                }
                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                    Button {
                        openSettings(ledger)
                    } label: {
                        Label("设置", systemImage: "gearshape")
                    }
                    .tint(Color.designPrimaryContainer)
                }
            }
        }
        .navigationTitle("账本管理")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showCreateSheet = true } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .onAppear(perform: load)
        .sheet(item: $settingsLedger) { ledger in
            LedgerSettingsView(ledger: ledger)
        }
        .sheet(isPresented: $showCreateSheet) {
            CreateLedgerView { newLedger in
                switchLedger(newLedger)
                load()
            }
        }
        .alert("确认删除", isPresented: $showDeleteAlert) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) { confirmDelete() }
        } message: {
            Text("删除账本会同时删除该账本下的所有数据，此操作不可撤销。")
        }
    }

    private func openSettings(_ ledger: Ledger) {
        if ledger.id != appContainer.currentLedger?.id {
            appContainer.currentLedger = ledger
            UserDefaults.standard.set(ledger.id.uuidString, forKey: "currentLedgerID")
        }
        settingsLedger = ledger
    }

    private func load() {
        ledgers = (try? appContainer.ledgerService.fetchLedgers(context: modelContext)) ?? []
    }

    private func switchLedger(_ ledger: Ledger) {
        guard ledger.id != appContainer.currentLedger?.id else { return }
        appContainer.currentLedger = ledger
        UserDefaults.standard.set(ledger.id.uuidString, forKey: "currentLedgerID")
        load()
    }

    private func confirmDelete() {
        guard let ledger = ledgerToDelete, ledgers.count > 1 else { return }
        let wasCurrent = ledger.id == appContainer.currentLedger?.id
        try? appContainer.ledgerService.deleteLedger(ledger, context: modelContext)
        if wasCurrent, let next = (try? appContainer.ledgerService.fetchLedgers(context: modelContext))?.first {
            appContainer.currentLedger = next
            UserDefaults.standard.set(next.id.uuidString, forKey: "currentLedgerID")
        }
        load()
    }
}
