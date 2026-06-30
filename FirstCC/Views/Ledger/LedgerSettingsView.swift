import SwiftUI
@preconcurrency import CoreData
import CloudKit

struct LedgerSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var modelContext
    @Environment(AppContainer.self) private var appContainer

    let ledger: Ledger
    @State private var name: String = ""
    @State private var type: LedgerType = .personal
    @State private var currencyCode: String = "CNY"
    @State private var showDeleteAlert = false
    @State private var showCloseShareAlert = false
    @State private var showExitShareAlert = false
    @State private var showCloudShare = false
    @State private var cloudShare: CKShare?
    @State private var isExiting = false
    @State private var clonedLedgerID: UUID?
    @State private var isCreatingShare = false
    @State private var shareError: String?
    @State private var shareDetected: Bool? = nil  // nil=检测中, true=共享存在, false=无共享
    @State private var shareZoneIDForPurge: CKRecordZone.ID?
    #if DEBUG
    @State private var isSeeding = false
    #endif

    private var isOwner: Bool {
        // 优先用 CKShare.currentUserParticipant 判断（基于当前 iCloud 账户，最可靠）
        if let share = cloudShare, share.currentUserParticipant?.role == .owner { return true }
        // 回退到比较 recordID
        return appContainer.isOwner(of: ledger)
    }
    private var isShared: Bool { shareDetected == true }

    private let currencies = ["CNY", "USD", "EUR", "JPY", "GBP", "HKD", "AUD", "CAD"]

    var body: some View {
        NavigationStack {
            Form {
            Section("基本信息") {
                TextField("账本名称", text: $name)
                Picker("类型", selection: $type) {
                    ForEach(LedgerType.allCases, id: \.self) { t in
                        Label(t.displayName, systemImage: t.systemIcon).tag(t)
                    }
                }
                Picker("默认货币", selection: $currencyCode) {
                    ForEach(currencies, id: \.self) { code in
                        Text("\(code) (\(currencyName(code)))").tag(code)
                    }
                }
            }

            Section {
                    if shareDetected == nil {
                        HStack { ProgressView(); Text("正在检测共享状态...").font(.designBodySmall).foregroundStyle(.secondary) }
                    } else if isShared {
                        NavigationLink {
                            UserListView(ledger: ledger)
                        } label: {
                            Label("共享成员", systemImage: "person.2.fill")
                        }
                        if isOwner {
                            Button {
                                openExistingShare()
                            } label: {
                                Label("管理共享", systemImage: "square.and.arrow.up")
                            }
                            Button(role: .destructive) {
                                showCloseShareAlert = true
                            } label: {
                                HStack {
                                    Label("关闭共享", systemImage: "person.2.slash")
                                    if isExiting { Spacer(); ProgressView() }
                                }
                            }
                            .disabled(isExiting)
                        } else {
                            Button(role: .destructive) {
                                showExitShareAlert = true
                            } label: {
                                HStack {
                                    Label("退出共享", systemImage: "rectangle.portrait.and.arrow.right")
                                    if isExiting { Spacer(); ProgressView() }
                                }
                            }
                            .disabled(isExiting)
                        }
                    } else {
                        Button {
                            createShareAndShow()
                        } label: {
                            HStack {
                                Label("启用共享", systemImage: "person.2.badge.plus")
                                if isCreatingShare { Spacer(); ProgressView() }
                            }
                        }
                        .disabled(isCreatingShare)
                    }
                } header: {
                    Text("共享管理")
                } footer: {
                    if shareDetected == nil {
                        Text("正在检查 iCloud 共享状态...")
                    } else if isShared {
#if DEBUG
                        let diag = "currentUser: \(appContainer.currentUserRecordID ?? "nil")\nownerRID: \(ledger.ownerUserRecordID ?? "nil")"
                        let sharedMsg = isOwner ? "此账本已开启共享，其他用户可加入协作记账" : "你正在参与此共享账本，仅拥有者可管理成员"
                        Text(sharedMsg + "\n\n[诊断] \(diag)")
#else
                        Text(isOwner ? "此账本已开启共享，其他用户可加入协作记账" : "你正在参与此共享账本，仅拥有者可管理成员")
#endif
                    } else {
                        Text("开启后可邀请其他 iCloud 用户共同记账")
                    }
                }

            Section("数据管理") {
                NavigationLink("账户管理") {
                    AccountsManagementView(ledger: ledger)
                }
                NavigationLink("分类管理") {
                    CategoryListView(ledger: ledger)
                }
                NavigationLink("联系人管理") {
                    MemberListView(ledger: ledger)
                }
                NavigationLink("商家管理") {
                    MerchantListView(ledger: ledger)
                }
                NavigationLink("项目管理") {
                    ProjectListView(ledger: ledger)
                }
                NavigationLink("预算管理") {
                    BudgetBookListView(ledger: ledger)
                }
                NavigationLink("模板管理") {
                    TemplateListView(ledger: ledger)
                }
                NavigationLink("周期账管理") {
                    RecurringListView(ledger: ledger)
                }
                NavigationLink("数据导出") {
                    ExportView()
                }
            }

            #if DEBUG
            Section {
                Button {
                    isSeeding = true
                    Task {
                        DummyDataSeeder.seed(context: modelContext, ledger: ledger)
                        NotificationCenter.default.post(name: .transactionDidChange, object: nil)
                        isSeeding = false
                    }
                } label: {
                    HStack {
                        Label("生成3年测试数据", systemImage: "ladybug")
                        if isSeeding {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(isSeeding)
            } footer: {
                Text("仅在 DEBUG 模式可用。在当前账本中创建约2000-3000笔随机支出和每月收入记录，覆盖过去3年。")
            }
            #endif

            if !isShared || isOwner {
                Section {
                    Button(role: .destructive) {
                        showDeleteAlert = true
                    } label: {
                        Label("删除账本", systemImage: "trash")
                    }
                }
            }
        }
        .navigationTitle("账本设置")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") { save() }
                    .disabled(name.isEmpty)
            }
        }
        .onAppear {
            name = ledger.name
            type = ledger.type
            currencyCode = ledger.defaultCurrencyCode
        }
        .task { await detectShare() }
        .sheet(isPresented: $showCloudShare) {
            if let container = appContainer.cloudKitContainer, let share = cloudShare {
                CloudSharingView(
                    share: share, container: container, ledger: ledger,
                    syncService: appContainer.syncService as? SyncServiceImpl,
                    onStopSharing: {
                        Task { await handleStopSharing() }
                    }
                )
            } else {
                ContentUnavailableView("共享未就绪", systemImage: "icloud.slash", description: Text("暂时无法读取共享信息，请稍后重试。"))
            }
        }
        .alert("确认删除", isPresented: $showDeleteAlert) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) { confirmDelete() }
        } message: {
            if isShared && isOwner {
                Text("这是共享账本。删除后其他成员将无法访问，数据将保留在你的本地。")
            } else {
                Text("删除账本会同时删除该账本下的所有数据，此操作不可撤销。")
            }
        }
        .alert("关闭共享", isPresented: $showCloseShareAlert) {
            Button("取消", role: .cancel) {}
            Button("关闭共享", role: .destructive) { closeShare() }
        } message: {
            Text("关闭共享后，其他成员将无法访问此账本。你的数据将保留为本地账本。")
        }
        .alert("退出共享", isPresented: $showExitShareAlert) {
            Button("取消", role: .cancel) {}
            Button("退出共享", role: .destructive) { exitShare() }
        } message: {
            Text("退出后你将无法访问此共享账本。数据将保留一份本地副本。")
        }
        .alert("共享失败", isPresented: .init(get: { shareError != nil }, set: { if !$0 { shareError = nil } })) {
            Button("确定", role: .cancel) { shareError = nil }
        } message: {
            Text(shareError ?? "未知错误")
        }
        }
    }

    private func createShareAndShow() {
        isCreatingShare = true
        Task {
            do {
                guard let syncService = appContainer.syncService as? SyncServiceImpl else {
                    throw SyncError.invalidShareTarget
                }
                let share = try await syncService.createShare(for: ledger)
                await MainActor.run {
                    ledger.isShared = true
                    ledger.shareRecordName = share.recordID.recordName
                    do {
                        try modelContext.save()
                    } catch {
                        DiagnosticLog.log("LedgerSettings: save after share failed: \(error.localizedDescription)")
                    }
                    cloudShare = share
                    isCreatingShare = false
                    showCloudShare = true
                }
                do {
                    try await syncService.syncParticipants(share: share, for: ledger)
                } catch {
                    DiagnosticLog.log("LedgerSettings: syncParticipants failed: \(error.localizedDescription)")
                }
            } catch {
                await MainActor.run {
                    isCreatingShare = false
                    shareError = error.localizedDescription
                }
            }
        }
    }

    private func detectShare() async {
        // 方式1：通过 shareRecordName
        if let recordName = ledger.shareRecordName {
            let recordID = CKRecord.ID(recordName: recordName)
            do {
                let records = try await CKContainer.default().sharedCloudDatabase.records(for: [recordID])
                if let share = records[recordID] as? CKShare {
                    repairLedgerFromShare(share)
                    cloudShare = share
                    shareDetected = true
                    return
                }
            } catch {
                // recordName 方式失败，继续 fallback
            }
        }

        // 方式2：通过 Core Data fetchShares
        do {
            let shares = try appContainer.coreDataStack.container.fetchShares(matching: [ledger.objectID])
            if let share = shares[ledger.objectID] {
                repairLedgerFromShare(share)
                cloudShare = share
                shareDetected = true
                return
            }
        } catch {}

        // 方式3：直接查询 shared database 中的 CKShare 记录
        do {
            let results = try await CKContainer.default().sharedCloudDatabase.records(
                matching: CKQuery(recordType: "cloudkit.share", predicate: NSPredicate(value: true))
            )
            for (_, result) in results.matchResults {
                if let share = try? result.get() as? CKShare {
                    // 保存 shareRecordName 以便后续使用
                    ledger.shareRecordName = share.recordID.recordName
                    repairLedgerFromShare(share)
                    cloudShare = share
                    shareDetected = true
                    return
                }
            }
        } catch {}

        shareDetected = false
    }

    private func repairLedgerFromShare(_ share: CKShare) {
        var changed = false
        if !ledger.isShared {
            ledger.isShared = true
            changed = true
        }
        if ledger.shareRecordName == nil {
            ledger.shareRecordName = share.recordID.recordName
            changed = true
        }
        // currentUserParticipant 基于当前 iCloud 登录状态，是判断 owner 的最可靠方式
        // 只有 owner 设备才写入自己的 recordID，participant 不碰（等 CloudKit 同步）
        if share.currentUserParticipant?.role == .owner {
            let myID = appContainer.currentUserRecordID
            if ledger.ownerUserRecordID != myID {
                ledger.ownerUserRecordID = myID
                changed = true
            }
        }
        if changed {
            try? modelContext.save()
        }
    }

    private func openExistingShare() {
        // Always re-detect to get the latest CKShare state
        Task {
            await detectShare()
            await MainActor.run {
                if cloudShare != nil {
                    showCloudShare = true
                } else {
                    shareError = String(localized: "无法读取共享信息，请稍后重试")
                }
            }
        }
    }

    private func save() {
        ledger.name = name
        ledger.type = type
        ledger.defaultCurrencyCode = currencyCode
        try? appContainer.ledgerService.updateLedger(ledger, context: modelContext)
        dismiss()
    }

    private func confirmDelete() {
        do {
            try appContainer.ledgerService.deleteLedger(ledger, context: modelContext)
            DiagnosticLog.log("LedgerSettingsView: deleted \(ledger.name) OK")
        } catch {
            DiagnosticLog.log("LedgerSettingsView: delete FAILED \(error.localizedDescription)")
        }
        if ledger.id == appContainer.currentLedger?.id {
            if let next = (try? appContainer.ledgerService.fetchLedgers(context: modelContext))?.first {
                appContainer.currentLedger = next
                UserDefaults.standard.set(next.id.uuidString, forKey: "currentLedgerID")
            }
        }
        dismiss()
    }

    // MARK: - Exit & Close Share

    private func exitShare() {
        isExiting = true
        Task {
            do {
                let clone = try LedgerDeepCopyService.deepCopy(ledger, into: modelContext)
                // Re-detect to get latest CKShare state before showing system UI
                await detectShare()
                await MainActor.run {
                    clonedLedgerID = clone.id
                    shareZoneIDForPurge = cloudShare?.recordID.zoneID
                    isExiting = false
                    showCloudShare = true
                }
            } catch {
                await MainActor.run {
                    isExiting = false
                    shareError = String(localized: "数据复制失败：\(error.localizedDescription)")
                }
            }
        }
    }

    private func closeShare() {
        isExiting = true
        Task {
            await MainActor.run {
                isExiting = false
                showCloudShare = true
            }
        }
    }

    @MainActor
    private func handleStopSharing() async {
        if isOwner {
            ledger.isShared = false
            try? modelContext.save()
            appContainer.syncStatus = .synced
            dismiss()
        } else if let cloneID = clonedLedgerID {
            // Record the original shared ledger as exited so it won't appear in the list
            appContainer.exitedSharedLedgerIDs.insert(ledger.id)
            let fetch = NSFetchRequest<Ledger>(entityName: "Ledger")
            fetch.predicate = NSPredicate(format: "id == %@", cloneID as CVarArg)
            fetch.fetchLimit = 1
            if let clone = try? modelContext.fetch(fetch).first {
                appContainer.currentLedger = clone
                UserDefaults.standard.set(clone.id.uuidString, forKey: "currentLedgerID")
                dismiss()
                // Purge the shared zone now that participant removal is complete.
                // This is Apple's recommended approach — safe because CloudKit has
                // already processed the participant removal server-side.
                if let zoneID = shareZoneIDForPurge {
                    appContainer.coreDataStack.purgeSharedZone(zoneID: zoneID)
                }
                appContainer.syncStatus = .synced
            }
        } else {
            dismiss()
        }
    }

    private func currencyName(_ code: String) -> String {
        switch code {
        case "CNY": return String(localized: "人民币")
        case "USD": return String(localized: "美元")
        case "EUR": return String(localized: "欧元")
        case "JPY": return String(localized: "日元")
        case "GBP": return String(localized: "英镑")
        case "HKD": return String(localized: "港币")
        case "AUD": return String(localized: "澳元")
        case "CAD": return String(localized: "加元")
        default: return code
        }
    }
}

#if DEBUG
// MARK: - DummyDataSeeder

private enum DummyDataSeeder {
    /// 生成 3 年模拟交易数据（支出为负数，含每月收入）
    static func seed(context: NSManagedObjectContext, ledger: Ledger) {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        guard let threeYearsAgo = cal.date(byAdding: .year, value: -3, to: today) else { return }

        let accounts = fetchAccounts(ledger: ledger, context: context)
        let expenseCategories = fetchCategories(type: .expense, ledger: ledger, context: context)
        let incomeCategories = fetchCategories(type: .income, ledger: ledger, context: context)
        let merchants = fetchMerchants(ledger: ledger, context: context)

        guard !accounts.isEmpty, !expenseCategories.isEmpty else {
            print("[DummyDataSeeder] 缺少账户或支出分类，跳过生成。")
            return
        }

        let categoryWeights: [(category: Category, dailyChance: Double, amountRange: ClosedRange<Double>)] = {
            let catByName: [String: Category] = Dictionary(
                uniqueKeysWithValues: expenseCategories.map { ($0.name, $0) }
            )
            let specs: [(String, Double, ClosedRange<Double>)] = [
                ("餐饮饮食", 0.85, 10...80),
                ("交通出行", 0.55, 5...120),
                ("购物消费", 0.40, 20...600),
                ("娱乐休闲", 0.30, 30...300),
                ("住房居家", 0.20, 50...3000),
                ("医疗健康", 0.15, 20...500),
                ("教育学习", 0.12, 30...800),
                ("通讯网络", 0.25, 20...200),
                ("人情往来", 0.10, 100...2000),
                ("金融服务", 0.08, 5...200),
                ("其他杂项", 0.15, 5...150),
            ]
            return specs.compactMap { name, chance, range in
                guard let cat = catByName[name] ?? expenseCategories.first(where: { $0.name.hasPrefix(name) }) else {
                    return nil
                }
                return (cat, chance, range)
            }
        }()

        var totalExpenseCount = 0
        var totalIncomeCount = 0
        let batchSize = 200

        var currentDate = threeYearsAgo
        while currentDate <= today {
            let expenseCount = Int.random(in: 1...4)
            for _ in 0..<expenseCount {
                guard let spec = Self.weightedRandom(from: categoryWeights, by: \.dailyChance) else { continue }

                let amount = Decimal(Double.random(in: spec.amountRange))
                let negAmount = -amount

                let hour = Int.random(in: 6...22)
                let minute = Int.random(in: 0...59)
                let txnDate = cal.date(bySettingHour: hour, minute: minute, second: 0, of: currentDate) ?? currentDate

                let note: String? = {
                    let n: [String] = switch spec.category.name {
                    case "餐饮饮食": ["午餐", "晚餐", "外卖", "买菜", "早点", "零食"]
                    case "交通出行": ["通勤", "打车", "加油", "高铁"]
                    case "购物消费": ["日用品", "衣服", "数码", "护肤品"]
                    default: []
                    }
                    return n.randomElement()
                }()

                let t = Transaction(
                    type: .expense,
                    amount: negAmount,
                    note: note,
                    date: txnDate,
                    account: accounts.randomElement()!,
                    category: spec.category,
                    merchant: merchants.randomElement(),
                    context: context
                )
                t.ledger = ledger
                totalExpenseCount += 1
            }

            if totalExpenseCount % batchSize == 0 {
                try? context.save()
            }

            currentDate = cal.date(byAdding: .day, value: 1, to: currentDate) ?? today
        }

        // 每月 1-2 笔收入
        var monthCursor = threeYearsAgo
        while monthCursor <= today {
            let incomeCount = Int.random(in: 1...2)
            for _ in 0..<incomeCount {
                guard let cat = incomeCategories.randomElement() else { continue }
                let isSalary = cat.name.contains("工资") || cat.name.contains("薪金")
                let amountRange: ClosedRange<Double> = isSalary ? 8000...35000 : 500...8000
                let amount = Decimal(Double.random(in: amountRange))

                let day = Int.random(in: 1...min(28, cal.range(of: .day, in: .month, for: monthCursor)?.count ?? 28))
                let txnDate = cal.date(bySetting: .day, value: day, of: monthCursor) ?? monthCursor
                let finalDate = cal.date(bySettingHour: Int.random(in: 8...18), minute: 0, second: 0, of: txnDate) ?? txnDate

                let t = Transaction(
                    type: .income,
                    amount: amount,
                    note: isSalary ? "工资" : nil,
                    date: finalDate,
                    account: accounts.randomElement()!,
                    category: cat,
                    context: context
                )
                t.ledger = ledger
                totalIncomeCount += 1
            }

            monthCursor = cal.date(byAdding: .month, value: 1, to: monthCursor) ?? today
        }

        try? context.save()

        print("[DummyDataSeeder] 完成：支出 \(totalExpenseCount) 笔，收入 \(totalIncomeCount) 笔")
    }

    // MARK: Helpers

    private static func fetchAccounts(ledger: Ledger, context: NSManagedObjectContext) -> [Account] {
        let request = NSFetchRequest<Account>(entityName: "Account")
        request.predicate = NSPredicate(format: "ledger.id == %@", ledger.id as CVarArg)
        return (try? context.fetch(request)) ?? []
    }

    private static func fetchCategories(type: TransactionType, ledger: Ledger, context: NSManagedObjectContext) -> [Category] {
        let request = NSFetchRequest<Category>(entityName: "Category")
        request.predicate = NSPredicate(format: "ledger.id == %@ AND typeRaw == %@",
            ledger.id as CVarArg, type.rawValue)
        return (try? context.fetch(request)) ?? []
    }

    private static func fetchMerchants(ledger: Ledger, context: NSManagedObjectContext) -> [Merchant] {
        let request = NSFetchRequest<Merchant>(entityName: "Merchant")
        request.predicate = NSPredicate(format: "ledger.id == %@", ledger.id as CVarArg)
        return (try? context.fetch(request)) ?? []
    }

    private static func weightedRandom<T>(
        from items: [T],
        by weight: (T) -> Double
    ) -> T? {
        guard !items.isEmpty else { return nil }
        let weights = items.map(weight)
        let total = weights.reduce(0, +)
        guard total > 0 else { return items.randomElement() }
        let r = Double.random(in: 0..<total)
        var cumulative: Double = 0
        for (i, w) in weights.enumerated() {
            cumulative += w
            if r < cumulative { return items[i] }
        }
        return items.last
    }
}
#endif
