import SwiftUI
@preconcurrency import CoreData

// MARK: - Settings Window (⌘,)

/// Standard macOS Preferences-style window registered via `Settings` scene.
/// Uses toolbar tabs: Appearance / Ledger / About.
struct SettingsWindow: View {
    @State private var tab: SettingsTab = .appearance

    var body: some View {
        TabView(selection: $tab) {
            AppearanceSettingsView()
                .tabItem { Label("显示", systemImage: "paintbrush") }
                .tag(SettingsTab.appearance)

            LedgerSettingsContent()
                .tabItem { Label("账本设置", systemImage: "books.vertical") }
            .tag(SettingsTab.ledger)

            AboutSettingsView()
                .tabItem { Label("关于", systemImage: "info.circle") }
                .tag(SettingsTab.about)
        }
        .tabViewStyle(.automatic)
        .frame(width: 600, height: 480)
        .fixedSize()
    }
}

private enum SettingsTab: Hashable {
    case appearance, ledger, about
}

// MARK: - Ledger Settings Content

/// Full per-ledger settings: basic info, data management links, sharing, delete.
private struct LedgerSettingsContent: View {
    @Environment(AppContainer.self) private var appContainer
    @Environment(\.managedObjectContext) private var modelContext

    @State private var name: String = ""
    @State private var ledgerType: LedgerType = .personal
    @State private var currencyCode: String = "CNY"

    @State private var showDeleteAlert = false
    @State private var ledgerToDelete: Ledger?

    // Counts for data management badges
    @State private var accountCount = 0
    @State private var categoryCount = 0
    @State private var memberCount = 0
    @State private var merchantCount = 0
    @State private var projectCount = 0
    @State private var templateCount = 0
    @State private var recurringCount = 0
    @State private var budgetCount = 0

    // Sheet state for management views
    @State private var sheetAccounts = false
    @State private var sheetCategories = false
    @State private var sheetMembers = false
    @State private var sheetMerchants = false
    @State private var sheetProjects = false
    @State private var sheetBudgets = false
    @State private var sheetTemplates = false
    @State private var sheetRecurring = false
    @State private var sheetExport = false

    private let currencies = ["CNY", "USD", "EUR", "JPY", "GBP", "HKD", "AUD", "CAD", "KRW", "TWD", "SGD", "CHF", "NZD", "THB", "MYR", "INR"]

    private var effectiveLedger: Ledger? {
        appContainer.currentLedger
    }

    var body: some View {
        ScrollView {
            if let ledger = effectiveLedger {
                VStack(alignment: .leading, spacing: 0) {
                    // Section 1 — 当前账本
                    currentLedgerSection(ledger: ledger)
                    sectionDivider
                    // Section 2 — 基本信息
                    basicInfoSection(ledger: ledger)
                    sectionDivider
                    // Section 3 — 数据管理
                    dataManagementSection
                    sectionDivider
                    // Section 4 — 共享管理
                    sharingSection
                    sectionDivider
                    deleteSection
                }
                .padding(.vertical, 20)
                .frame(maxWidth: .infinity)
            } else {
                noLedgerView
            }
        }
        .designScreen()
        .navigationTitle("")
        .task { loadFromLedger(); loadCounts() }
        .onChange(of: appContainer.currentLedger?.id) { _, _ in loadFromLedger(); loadCounts() }
        .onChange(of: name) { _, _ in autoSave() }
        .onChange(of: ledgerType) { _, _ in autoSave() }
        .onChange(of: currencyCode) { _, _ in autoSave() }
        .alert("确认删除", isPresented: $showDeleteAlert) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) { confirmDelete() }
        } message: {
            Text("删除账本会同时删除该账本下的所有数据，此操作不可撤销。")
        }
        .sheet(isPresented: $sheetAccounts) { MacAccountListView() }
        .sheet(isPresented: $sheetCategories) { if let ledger = effectiveLedger { MacCategoryListView(ledger: ledger) } }
        .sheet(isPresented: $sheetMembers) { if let ledger = effectiveLedger { MacMemberListView(ledger: ledger) } }
        .sheet(isPresented: $sheetMerchants) { PlaceholderView(title: "商家管理", icon: "building.2") }
        .sheet(isPresented: $sheetProjects) { PlaceholderView(title: "项目管理", icon: "folder") }
        .sheet(isPresented: $sheetBudgets) { BudgetBookListView(ledger: effectiveLedger) }
        .sheet(isPresented: $sheetTemplates) { PlaceholderView(title: "模板管理", icon: "doc.text") }
        .sheet(isPresented: $sheetRecurring) { PlaceholderView(title: "周期账管理", icon: "repeat") }
        .sheet(isPresented: $sheetExport) { PlaceholderView(title: "数据导出", icon: "square.and.arrow.up") }
    }

    /// Full-width hairline divider matching Apple Calendar Settings style
    private var sectionDivider: some View {
        Divider()
            .padding(.vertical, 20)
    }

    // MARK: - No Ledger

    private var noLedgerView: some View {
        VStack(spacing: 16) {
            Image(systemName: "books.vertical").font(.system(size: 40))
                .foregroundStyle(Color.designOnSurfaceVariant.opacity(0.4))
            Text("暂无账本").font(.designBodyMedium).foregroundStyle(Color.designOnSurfaceVariant)
            Text("请先在主窗口工具栏创建账本").font(.designBodyCaption).foregroundStyle(Color.designOnSurfaceVariant.opacity(0.6))
            Button("新建账本") {
                // Post notification to open create ledger sheet in main window
                NotificationCenter.default.post(name: .macCreateLedger, object: nil)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.designPrimaryContainer)
        }
        .frame(maxWidth: .infinity, minHeight: 300)
        .padding(32)
    }

    // MARK: - Current Ledger

    private func currentLedgerSection(ledger: Ledger) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("当前账本").font(.designLabel).foregroundStyle(Color.designOnSurfaceVariant)
            HStack(spacing: 8) {
                Image(systemName: ledger.iconName)
                    .foregroundStyle(Color.designPrimaryContainer)
                Text(ledger.name).font(.designBodyMedium)
                    .foregroundStyle(Color.designOnSurface)
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, 40)
    }

    // MARK: - Basic Info

    private func basicInfoSection(ledger: Ledger) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("基本信息").font(.designLabel).foregroundStyle(Color.designOnSurfaceVariant)

            VStack(spacing: 10) {
                LabeledContent("名称：") {
                    TextField("", text: $name)
                        .textFieldStyle(.roundedBorder)
                }
                LabeledContent("类型：") {
                    Picker("", selection: $ledgerType) {
                        ForEach(LedgerType.allCases, id: \.self) { t in Text(t.displayName).tag(t) }
                    }
                    .pickerStyle(.menu).labelsHidden()
                }
                LabeledContent("币种：") {
                    Picker("", selection: $currencyCode) {
                        ForEach(currencies, id: \.self) { code in
                            Text("\(code) \(CurrencyFormatter.currencySymbol(for: code))").tag(code)
                        }
                    }
                    .pickerStyle(.menu).labelsHidden()
                }
            }
            .buttonSizing(.flexible)       // macOS 26+ — makes Picker fill available width
            .frame(width: 300)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(.horizontal, 40)
    }

    // MARK: - Data Management

    private var dataManagementSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("数据管理").font(.designLabel).foregroundStyle(Color.designOnSurfaceVariant)
                .padding(.bottom, 4)

            VStack(spacing: 0) {
                managementRow("账户管理", icon: "creditcard", count: accountCount) { sheetAccounts = true }
                Divider()
                managementRow("分类管理", icon: "square.grid.2x2", count: categoryCount) { sheetCategories = true }
                Divider()
                managementRow("联系人管理", icon: "person.2", count: memberCount) { sheetMembers = true }
                Divider()
                managementRow("商家管理", icon: "building.2", count: merchantCount) { sheetMerchants = true }
                Divider()
                managementRow("项目管理", icon: "folder", count: projectCount) { sheetProjects = true }
                Divider()
                managementRow("预算管理", icon: "chart.pie", count: budgetCount) { sheetBudgets = true }
                Divider()
                managementRow("模板管理", icon: "doc.text", count: templateCount) { sheetTemplates = true }
                Divider()
                managementRow("周期账管理", icon: "repeat", count: recurringCount) { sheetRecurring = true }
                Divider()
                managementRow("数据导出", icon: "square.and.arrow.up", count: nil) { sheetExport = true }
            }
        }
        .padding(.horizontal, 40)
    }

    private func managementRow(
        _ title: String, icon: String, count: Int?, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .frame(width: 22)
                    .foregroundStyle(Color.designPrimaryContainer)
                Text(title).font(.designBodyMedium).foregroundStyle(Color.designOnSurface)
                Spacer()
                if let c = count, c > 0 {
                    Text("\(c)").font(.designBodyCaption).foregroundStyle(Color.designOnSurfaceVariant)
                }
                Image(systemName: "chevron.right")
                    .font(.designBodyCaption).foregroundStyle(Color.designOnSurfaceVariant.opacity(0.4))
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Sharing

    private var sharingSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("共享管理").font(.designLabel).foregroundStyle(Color.designOnSurfaceVariant)

            HStack {
                Image(systemName: "person.2")
                    .foregroundStyle(Color.designOnSurfaceVariant)
                Text("iCloud 共享")
                    .font(.designBodyMedium).foregroundStyle(Color.designOnSurface)
                Spacer()
                Text("即将上线").font(.designBodyCaption)
                    .foregroundStyle(Color.designOnSurfaceVariant.opacity(0.6))
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(Capsule().fill(Color.designSurfaceContainer.opacity(0.5)))
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, 40)
    }

    // MARK: - Delete

    private var deleteSection: some View {
        HStack {
            Spacer()
            Button(role: .destructive) {
                ledgerToDelete = effectiveLedger
                showDeleteAlert = true
            } label: {
                Label("删除账本", systemImage: "trash")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.red)
            Spacer()
        }
        .padding(.horizontal, 40)
        .padding(.top, 8)
    }

    // MARK: - Data Loading

    private func loadFromLedger() {
        guard let ledger = effectiveLedger else { return }
        name = ledger.name
        ledgerType = ledger.type
        currencyCode = ledger.defaultCurrencyCode
    }

    private func loadCounts() {
        guard let ledger = effectiveLedger else {
            accountCount = 0; categoryCount = 0; memberCount = 0
            merchantCount = 0; projectCount = 0; templateCount = 0
            recurringCount = 0; budgetCount = 0
            return
        }
        let ctx = modelContext
        accountCount = (try? appContainer.accountService.fetchAccounts(for: ledger, includeArchived: false, context: ctx))?.count ?? 0
        categoryCount = (try? appContainer.categoryService.fetchCategories(for: ledger, type: nil, context: ctx))?.count ?? 0
        memberCount = (try? appContainer.memberService.fetchMembers(for: ledger, context: ctx))?.count ?? 0
        merchantCount = (try? appContainer.merchantService.fetchMerchants(for: ledger, context: ctx))?.count ?? 0
        projectCount = (try? appContainer.projectService.fetchProjects(for: ledger, context: ctx))?.count ?? 0
        templateCount = (try? appContainer.templateService.fetchTemplates(for: ledger, context: ctx))?.count ?? 0
        recurringCount = (try? appContainer.recurringService.fetchRules(for: ledger, context: ctx))?.count ?? 0
        budgetCount = (try? appContainer.budgetService.fetchBooks(for: ledger, context: ctx))?.count ?? 0
    }

    private func autoSave() {
        guard let ledger = effectiveLedger, !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        ledger.name = name
        ledger.typeRaw = ledgerType.rawValue
        ledger.defaultCurrencyCode = currencyCode
        try? modelContext.save()
    }

    private func confirmDelete() {
        guard let ledger = ledgerToDelete else { return }
        let wasCurrent = ledger.id == appContainer.currentLedger?.id
        do {
            try appContainer.ledgerService.deleteLedger(ledger, context: modelContext)
        } catch {
            DiagnosticLog.log("SettingsWindow: delete FAILED \(error.localizedDescription)")
        }
        if wasCurrent, let next = (try? appContainer.ledgerService.fetchLedgers(context: modelContext))?.first {
            appContainer.currentLedger = next
            UserDefaults.standard.set(next.id.uuidString, forKey: "currentLedgerID")
        }
    }
}

// MARK: - Placeholder View

private struct PlaceholderView: View {
    let title: String
    let icon: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 32))
                .foregroundStyle(Color.designOnSurfaceVariant.opacity(0.4))
            Text(title).font(.designBodyMedium).foregroundStyle(Color.designOnSurfaceVariant)
            Text("即将上线").font(.designBodyCaption)
                .foregroundStyle(Color.designOnSurfaceVariant.opacity(0.4))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .designScreen()
    }
}

// MARK: - Mac Account List Placeholder (navigable from settings)

struct MacAccountListView: View {
    @Environment(AppContainer.self) private var appContainer
    @Environment(\.managedObjectContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var accounts: [Account] = []
    @State private var accountSheet: AccountSheet?

    enum AccountSheet: Identifiable, Equatable {
        case new
        case edit(Account)
        var id: String {
            switch self {
            case .new: "new"
            case .edit(let a): a.id.uuidString
            }
        }
    }

    var body: some View {
        List {
            ForEach(accounts) { account in
                Button {
                    accountSheet = .edit(account)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: account.iconName ?? "creditcard")
                            .foregroundStyle(Color(hex: account.colorHex ?? "#007AFF"))
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(account.name).font(.designBodyMedium).foregroundStyle(Color.designOnSurface)
                                if account.isArchived {
                                    Text("已归档").font(.system(size: 9, weight: .medium))
                                        .foregroundStyle(Color.designOnSurfaceVariant)
                                        .padding(.horizontal, 5).padding(.vertical, 1)
                                        .background(Capsule().fill(Color.designOnSurfaceVariant.opacity(0.12)))
                                }
                            }
                            Text(account.typeDisplayName).font(.designBodyCaption).foregroundStyle(Color.designOnSurfaceVariant)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 4)
                    .opacity(account.isArchived ? 0.55 : 1.0)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .scrollContentBackground(.hidden)
        .designScreen()
        .navigationTitle("账户管理")
        .frame(minWidth: 420, minHeight: 340)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    accountSheet = .new
                } label: {
                    Image(systemName: "plus")
                }
            }
            ToolbarItem(placement: .cancellationAction) {
                Button("完成") { dismiss() }
            }
        }
        .onAppear { load() }
        .sheet(item: $accountSheet) { sheet in
            switch sheet {
            case .new:
                MacAccountEditSheet(ledger: appContainer.currentLedger!)
            case .edit(let account):
                MacAccountEditSheet(editing: account, ledger: appContainer.currentLedger!)
            }
        }
        .onChange(of: accountSheet) { _, newValue in
            if newValue == nil { load() }  // sheet dismissed
        }
    }

    private func load() {
        guard let ledger = appContainer.currentLedger else { return }
        accounts = (try? appContainer.accountService.fetchAccounts(for: ledger, includeArchived: true, context: modelContext)) ?? []
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let macCreateLedger = Notification.Name("macCreateLedger")
}
