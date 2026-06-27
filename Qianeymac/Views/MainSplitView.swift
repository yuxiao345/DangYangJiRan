import SwiftUI
@preconcurrency import CoreData
import CloudKit
import Contacts

/// Main window layout.
/// Uses standard NavigationSplitView.
/// Note: macOS 27 beta 2 had a NavigationSplitView click-interception bug
/// (FB18201935, NSGlassContainerView), worked around in commit 224b58a with
/// HStack + custom divider. That workaround was reverted after returning to
/// macOS 26.5 / Xcode 26.5 release — the standard API works correctly here.
struct MainSplitView: View {
    @Environment(AppContainer.self) private var appContainer
    @State private var selection: MacNavItem = .dashboard
    @State private var selectedReportType: ReportType?
    @State private var showAddSheet = false
    @State private var allLedgers: [Ledger] = []
    @State private var showCreateLedgerSheet = false
    @State private var isCreatingShare = false
    @State private var shareParticipants: [User] = []
    @State private var participantAvatars: [UUID: NSImage] = [:]
    private let contactStore = CNContactStore()

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
        .designScreen()
        .onAppear { loadLedgers(); loadParticipants() }
        .onChange(of: appContainer.currentLedger?.id) { _, _ in loadLedgers(); loadParticipants() }
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
                Text("  " + (appContainer.currentLedger?.name ?? String(localized: "小金库")))
                    .font(.custom("SpaceGrotesk-Bold", fixedSize: 18))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            }
            .menuStyle(.borderlessButton)
        }
        ToolbarItem(placement: .principal) {
            ShareBadgeView(
                isShared: isShared,
                isCreatingShare: isCreatingShare,
                shareParticipants: shareParticipants,
                participantAvatars: participantAvatars,
                onTap: {
                    if isShared { manageSharing() }
                    else { createShareAndShow() }
                }
            )
        }
        ToolbarItem(placement: .primaryAction) {
            Button { showAddSheet = true } label: {
                Image(systemName: "plus")
            }
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List {
            ForEach(MacNavItem.allCases) { item in
                if item == .reports {
                    DisclosureGroup {
                        ForEach(ReportType.allCases) { type in
                            sidebarRow(icon: type.icon, label: type.rawValue,
                                       selected: selection == .reports && selectedReportType == type,
                                       isChild: true)
                                .onTapGesture {
                                    selection = .reports
                                    selectedReportType = type
                                }
                        }
                    } label: {
                        sidebarRow(icon: item.icon, label: item.rawValue,
                                   selected: selection == item)
                    }
                } else {
                    sidebarRow(icon: item.icon, label: item.rawValue,
                               selected: selection == item)
                        .onTapGesture {
                            if selection != item {
                                selection = item
                                selectedReportType = nil
                            }
                        }
                }
            }
        }
        .listStyle(.sidebar)
    }

    private func sidebarRow(icon: String, label: String, selected: Bool, isChild: Bool = false) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .frame(width: 20)
            Text(label)
        }
        .font(.designBodyMedium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .padding(.vertical, isChild ? 5 : 6)
        .padding(.horizontal, 8)
        .padding(.leading, isChild ? 8 : 0)
        .background(selected ? Color.accentColor.opacity(0.15) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
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
            if selectedReportType == nil {
                Color.clear.onAppear { selectedReportType = .trend }
            } else {
                ReportDetailContent()
            }
        }
    }

    private func loadLedgers() {
        let ctx = appContainer.viewContext
        let req = NSFetchRequest<Ledger>(entityName: "Ledger")
        req.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        allLedgers = (try? ctx.fetch(req)) ?? []
    }

    // MARK: - Share

    private var isShared: Bool {
        appContainer.currentLedger?.isShared ?? false
    }

    private func loadParticipants() {
        guard let ledger = appContainer.currentLedger, ledger.isShared else {
            shareParticipants = []
            participantAvatars = [:]
            return
        }
        let users = (ledger.members as? Set<User>)?.sorted(by: { $0.joinedAt < $1.joinedAt }) ?? []
        shareParticipants = users
        let currentIDs = Set(users.map(\.id))
        participantAvatars = participantAvatars.filter { currentIDs.contains($0.key) }
        loadContactAvatars(for: users)
    }

    private func loadContactAvatars(for users: [User]) {
        contactStore.requestAccess(for: .contacts) { granted, _ in
            guard granted else { return }
            let keys = [CNContactThumbnailImageDataKey] as [CNKeyDescriptor]
            var avatars: [UUID: NSImage] = [:]
            for user in users {
                let predicate = CNContact.predicateForContacts(matchingName: user.displayName)
                if let contacts = try? contactStore.unifiedContacts(matching: predicate, keysToFetch: keys),
                   let imageData = contacts.first?.thumbnailImageData {
                    avatars[user.id] = NSImage(data: imageData)
                }
            }
            DispatchQueue.main.async { self.participantAvatars.merge(avatars) { _, new in new } }
        }
    }

    // MARK: - Share Actions

    private func createShareAndShow() {
        guard let ledger = appContainer.currentLedger,
              let syncService = appContainer.syncService as? SyncServiceImpl else { return }
        guard let service = NSSharingService(named: .cloudSharing) else { return }
        isCreatingShare = true
        let itemProvider = NSItemProvider()
        itemProvider.registerCKShare(container: CKContainer.default(), allowedSharingOptions: .standard) {
            let share = try await syncService.createShare(for: ledger)
            await MainActor.run {
                ledger.isShared = true
                ledger.shareRecordName = share.recordID.recordName
                try? appContainer.viewContext.save()
                isCreatingShare = false
            }
            Task { @MainActor in
                try? await syncService.syncParticipants(share: share, for: ledger)
                loadParticipants()
            }
            return share
        }
        service.perform(withItems: [itemProvider])
    }

    private func manageSharing() {
        guard let ledger = appContainer.currentLedger,
              let syncService = appContainer.syncService as? SyncServiceImpl else {
            NSAlert(error: NSError(domain: "", code: 0, userInfo: [NSLocalizedDescriptionKey: "无法获取共享服务"])).runModal()
            return
        }
        isCreatingShare = true
        Task {
            let share = try? await syncService.discoverShare(for: ledger)
            await MainActor.run {
                isCreatingShare = false
                if let share {
                    showSharingService(share: share)
                } else {
                    createShareAndShow()
                }
            }
        }
    }

    private func showSharingService(share: CKShare) {
        guard let service = NSSharingService(named: .cloudSharing) else {
            NSAlert(error: NSError(domain: "CK", code: 0, userInfo: [NSLocalizedDescriptionKey: "CloudKit 共享服务不可用"])).runModal()
            return
        }
        // Set metadata for proper collaboration UI
        share[CKShare.SystemFieldKey.title] = appContainer.currentLedger?.name ?? "共享账本"
        let itemProvider = NSItemProvider()
        itemProvider.registerCloudKitShare(share, container: CKContainer.default())
        service.delegate = CloudSharingDelegate(onStop: { [self] in
            Task { @MainActor in
                appContainer.currentLedger?.isShared = false
                try? appContainer.viewContext.save()
                loadParticipants()
            }
        })
        service.perform(withItems: [itemProvider])
    }
}

