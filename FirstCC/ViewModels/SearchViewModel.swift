import Foundation
@preconcurrency import CoreData
#if canImport(FoundationModels)
import FoundationModels
#endif

@MainActor
@Observable
final class SearchViewModel {
    let ledger: Ledger
    private let transactionService: TransactionServiceProtocol

    var searchText = ""
    var searchResults: [Transaction] = []
    var parsedQuery: ParsedSearchQuery?
    var isSearching = false
    var hasSearched = false

    // MARK: - Manual Filter State (AdvancedFilterPanel)

    var isFilterPanelExpanded = false
    var selectedCategoryIDs: Set<UUID> = []
    var selectedMemberIDs: Set<UUID> = []
    var selectedMerchantIDs: Set<UUID> = []
    var selectedProjectIDs: Set<UUID> = []
    var dateFrom: Date?
    var dateTo: Date?
    var amountMin: Decimal?
    var amountMax: Decimal?
    var manualType: TransactionType?
    var manualKeyword = ""

    private var searchTask: Task<Void, Never>?

    init(ledger: Ledger, transactionService: TransactionServiceProtocol) {
        self.ledger = ledger
        self.transactionService = transactionService
        reloadSavedFilters()
        restoreFilterState()
    }

    // MARK: - Filter State Persistence

    private static let filterStateKey = "active_filter_state"

    private func persistFilterState() {
        let state = SavedFilter(
            name: "__active__", dateFrom: dateFrom, dateTo: dateTo,
            amountMin: amountMin, amountMax: amountMax,
            categoryIDs: Array(selectedCategoryIDs),
            memberIDs: Array(selectedMemberIDs),
            merchantIDs: Array(selectedMerchantIDs),
            projectIDs: Array(selectedProjectIDs),
            keyword: manualKeyword, createdAt: Date()
        )
        if let data = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(data, forKey: Self.filterStateKey)
        }
    }

    private func restoreFilterState() {
        guard let data = UserDefaults.standard.data(forKey: Self.filterStateKey),
              let state = try? JSONDecoder().decode(SavedFilter.self, from: data) else { return }
        dateFrom = state.dateFrom; dateTo = state.dateTo
        amountMin = state.amountMin; amountMax = state.amountMax
        selectedCategoryIDs = Set(state.categoryIDs)
        selectedMemberIDs = Set(state.memberIDs)
        selectedMerchantIDs = Set(state.merchantIDs)
        selectedProjectIDs = Set(state.projectIDs)
        manualKeyword = state.keyword
    }

    var totalCount: Int { searchResults.count }

    var totalAmount: Decimal {
        searchResults.reduce(0) { $0 + $1.ledgerAmount }
    }

    // MARK: - Filter Chips

    struct FilterChip: Identifiable {
        let id = UUID()
        let label: String
        let isManual: Bool
        let clearAction: (() -> Void)?
    }

    var activeFilterChips: [FilterChip] {
        var chips: [FilterChip] = []

        // NLP-parsed chips (read-only)
        if let dk = parsedQuery?.dateKeyword { chips.append(FilterChip(label: dk, isManual: false, clearAction: nil)) }
        if let ak = parsedQuery?.amountKeyword { chips.append(FilterChip(label: ak, isManual: false, clearAction: nil)) }
        if let tk = parsedQuery?.typeKeyword { chips.append(FilterChip(label: tk, isManual: false, clearAction: nil)) }

        // Manual date chip
        if dateFrom != nil || dateTo != nil {
            let df = DateFormatter()
            df.dateStyle = .short; df.timeStyle = .none
            let from = dateFrom.map { df.string(from: $0) } ?? "..."
            let to = dateTo.map { df.string(from: $0) } ?? "..."
            chips.append(FilterChip(label: "\(from) – \(to)", isManual: true, clearAction: { [weak self] in
                self?.dateFrom = nil; self?.dateTo = nil
            }))
        }

        // Manual amount chip
        if amountMin != nil || amountMax != nil {
            let minStr = amountMin.map { "¥\($0)" } ?? "¥0"
            let maxStr = amountMax.map { "¥\($0)" } ?? "..."
            chips.append(FilterChip(label: "\(minStr) – \(maxStr)", isManual: true, clearAction: { [weak self] in
                self?.amountMin = nil; self?.amountMax = nil
            }))
        }

        // Manual type chip
        if let t = manualType {
            chips.append(FilterChip(label: t.displayName, isManual: true, clearAction: { [weak self] in
                self?.manualType = nil
            }))
        }

        // Category count chip
        if !selectedCategoryIDs.isEmpty {
            chips.append(FilterChip(label: String(localized: "分类(\(selectedCategoryIDs.count))"), isManual: true, clearAction: { [weak self] in
                self?.selectedCategoryIDs.removeAll()
            }))
        }

        // Member count chip
        if !selectedMemberIDs.isEmpty {
            chips.append(FilterChip(label: String(localized: "成员(\(selectedMemberIDs.count))"), isManual: true, clearAction: { [weak self] in
                self?.selectedMemberIDs.removeAll()
            }))
        }

        // Merchant count chip
        if !selectedMerchantIDs.isEmpty {
            chips.append(FilterChip(label: String(localized: "商家(\(selectedMerchantIDs.count))"), isManual: true, clearAction: { [weak self] in
                self?.selectedMerchantIDs.removeAll()
            }))
        }

        // Project count chip
        if !selectedProjectIDs.isEmpty {
            chips.append(FilterChip(label: String(localized: "项目(\(selectedProjectIDs.count))"), isManual: true, clearAction: { [weak self] in
                self?.selectedProjectIDs.removeAll()
            }))
        }

        return chips
    }

    // MARK: - Sort

    enum SortOrder: String, CaseIterable {
        case dateDesc = "按日期排序"
        case amountDesc = "按金额降序"
        case amountAsc = "按金额升序"

        var displayName: String { NSLocalizedString(rawValue, comment: "") }
    }

    var sortOrder: SortOrder = .dateDesc

    var sortedResults: [Transaction] {
        switch sortOrder {
        case .dateDesc:
            return searchResults.sorted { $0.date > $1.date }
        case .amountDesc:
            return searchResults.sorted { abs($0.amount) > abs($1.amount) }
        case .amountAsc:
            return searchResults.sorted { abs($0.amount) < abs($1.amount) }
        }
    }

    /// 仅当按日期排序时，列表才按天分组。按金额排序时分组标题没有意义，视图直接铺平用
    /// `sortedResults`（见 `SearchView` / `MacSearchView` 的 `resultList`）。
    var groupsByDay: Bool { sortOrder == .dateDesc }

    /// 搜索结果按天分组，组间按真实日期倒序，组内按真实时间倒序。
    ///
    /// 分组身份与排序统一由 `groupedByDay` 用 `Date` 提供 —— 原先两端各写一份、拿完整
    /// 日期字符串当 key 再按字符串 `>` 比较，得到的是 Unicode 码位序而非日期序。
    ///
    /// 标题用 `.fullDate` 而不是流水列表那种「今天/昨天/月日」—— 搜索结果可能跨年，
    /// 不带年份的标题在跨年结果里分不清是哪一年。
    var dayGroups: [TransactionDayGroup] {
        sortedResults.groupedByDay(titleStyle: .fullDate)
    }

    var hasManualFilters: Bool {
        !selectedCategoryIDs.isEmpty || !selectedMemberIDs.isEmpty || !selectedMerchantIDs.isEmpty || !selectedProjectIDs.isEmpty
        || dateFrom != nil || dateTo != nil || amountMin != nil || amountMax != nil
        || manualType != nil || !manualKeyword.isEmpty
    }

    var hasResults: Bool { !searchResults.isEmpty }

    // MARK: - Toggle Helpers

    func toggleCategory(_ id: UUID) { selectedCategoryIDs.toggle(id) }
    func toggleMember(_ id: UUID)   { selectedMemberIDs.toggle(id) }
    func toggleMerchant(_ id: UUID) { selectedMerchantIDs.toggle(id) }
    func toggleProject(_ id: UUID)  { selectedProjectIDs.toggle(id) }

    func clearAllManualFilters() {
        selectedCategoryIDs.removeAll()
        selectedMemberIDs.removeAll()
        selectedMerchantIDs.removeAll()
        selectedProjectIDs.removeAll()
        dateFrom = nil
        dateTo = nil
        amountMin = nil
        amountMax = nil
        manualType = nil
        manualKeyword = ""
        persistFilterState()
    }

    // MARK: - Saved Filters

    var savedFilters: [SavedFilter] = []

    func reloadSavedFilters() { savedFilters = UserDefaults.standard.savedFilters() }

    func saveCurrentFilter(name: String) {
        let filter = SavedFilter(
            name: name,
            dateFrom: dateFrom, dateTo: dateTo,
            amountMin: amountMin, amountMax: amountMax,
            categoryIDs: Array(selectedCategoryIDs),
            memberIDs: Array(selectedMemberIDs),
            merchantIDs: Array(selectedMerchantIDs),
            projectIDs: Array(selectedProjectIDs),
            keyword: manualKeyword,
            createdAt: Date()
        )
        UserDefaults.standard.saveFilter(filter)
        reloadSavedFilters()
    }

    func applyFilter(_ filter: SavedFilter) {
        dateFrom = filter.dateFrom; dateTo = filter.dateTo
        amountMin = filter.amountMin; amountMax = filter.amountMax
        selectedCategoryIDs = Set(filter.categoryIDs)
        selectedMemberIDs = Set(filter.memberIDs)
        selectedMerchantIDs = Set(filter.merchantIDs)
        selectedProjectIDs = Set(filter.projectIDs)
        manualKeyword = filter.keyword
    }

    func deleteFilter(id: UUID) { UserDefaults.standard.deleteFilter(id: id); reloadSavedFilters() }

    // MARK: - Search

    func scheduleSearch(context: NSManagedObjectContext) {
        searchTask?.cancel()
        searchResults = []
        parsedQuery = nil
        hasSearched = false

        let hasText = !searchText.trimmingCharacters(in: .whitespaces).isEmpty
        guard hasText || hasManualFilters else {
            isSearching = false
            return
        }

        isSearching = true
        let text = searchText
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            performSearch(text: text, context: context)
        }
    }

    /// 回车触发搜索，无 debounce — 用于手动提交场景
    func submitSearch(context: NSManagedObjectContext) {
        searchTask?.cancel()
        searchResults = []
        parsedQuery = nil
        hasSearched = false

        let hasText = !searchText.trimmingCharacters(in: .whitespaces).isEmpty
        guard hasText || hasManualFilters else {
            isSearching = false
            return
        }

        isSearching = true
        performSearch(text: searchText, context: context)
    }

    func applyManualFilters(context: NSManagedObjectContext) {
        searchResults = []
        parsedQuery = nil
        hasSearched = false
        isSearching = true

        let text = searchText
        searchTask?.cancel()
        searchTask = Task {
            performSearch(text: text, context: context)
        }
    }

    private func performSearch(text: String, context: NSManagedObjectContext) {
        // Capture values on MainActor before any async work (prevents Core Data thread-safety violations)
        let ledgerID = ledger.id
        let capturedService = transactionService
        guard let coordinator = context.persistentStoreCoordinator else {
            isSearching = false
            return
        }

        // Cancel any previous search task; this single Task chain is fully cancellable
        searchTask?.cancel()
        searchTask = Task {
            // Phase 1: Parse text (lightweight, on MainActor to read NL model availability)
            var query = ParsedSearchQuery()
            if !text.trimmingCharacters(in: .whitespaces).isEmpty {
                query = await parseWithNLFallback(text)
            }
            guard !Task.isCancelled else { return }
            self.parsedQuery = query

            // Build filters on MainActor (reads @MainActor state like dateFrom, amountMin, etc.)
            let filters = buildFilters(from: query)
            guard !Task.isCancelled else { return }

            // Phase 2: Heavy fetch on background context, not blocking UI
            let objectIDs = await Task.detached {
                let bgContext = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
                bgContext.persistentStoreCoordinator = coordinator

                return await bgContext.perform {
                    let bgReq = NSFetchRequest<Ledger>(entityName: "Ledger")
                    bgReq.predicate = NSPredicate(format: "id == %@", ledgerID as CVarArg)
                    bgReq.fetchLimit = 1
                    guard let bgLedger = try? bgContext.fetch(bgReq).first else { return [NSManagedObjectID]() }
                    return (try? capturedService.fetchTransactions(for: bgLedger, context: bgContext, filters: filters))?
                        .map(\.objectID) ?? []
                }
            }.value

            guard !Task.isCancelled else { return }

            self.searchResults = objectIDs.compactMap { context.object(with: $0) as? Transaction }
            self.isSearching = false
            self.hasSearched = true
            self.persistFilterState()
        }
    }

    /// Build TransactionFilters from parsed query + manual filter state.
    /// Must be called on MainActor (reads published filter state).
    @MainActor
    private func buildFilters(from query: ParsedSearchQuery) -> TransactionFilters {
        var filters = TransactionFilters()

        // Merge NLP date + manual date (narrowest wins)
        //
        // dateFrom / dateTo 统一是「起始日 / 结束日（都含整天）」口径，两个写入方都遵守：
        // 日期选择器写选中时刻（初值 Date.now，带时分秒），搜索面板的预设直接写日界。
        // 「日」精度意味着用前必须归零到日界 —— 不归零会让「6月1日–6月2日」实际变成
        // [6月1日 14:30, 6月2日 14:30)，把当天早些时候的交易挡在区间外。
        // 结束日再 +1 天换成排他上界（TransactionServiceImpl 的谓词是 date < upper），
        // 与 ExportView 口径一致。写入方切不可反过来塞排他上界，否则会再被 +1 天。
        let manualDate: Range<Date>? = {
            switch (dateFrom, dateTo) {
            case (let from?, let to?):
                let lower = min(from, to).startOfDay
                let upper = max(from, to).startOfDay.adding(.day, value: 1)
                return lower..<upper
            case (let from?, nil):
                return from.startOfDay..<Date.distantFuture
            case (nil, let to?):
                return Date.distantPast..<to.startOfDay.adding(.day, value: 1)
            case (nil, nil):
                return nil
            }
        }()
        filters.dateRange = intersectRanges(query.dateRange, manualDate)

        // Merge NLP amount + manual amount
        let manualAmount: ClosedRange<Decimal>? = {
            switch (amountMin, amountMax) {
            case (let lo?, let hi?): return Swift.min(lo, hi)...Swift.max(lo, hi)
            case (let lo?, nil): return lo...Decimal.greatestFiniteMagnitude
            case (nil, let hi?): return 0...hi
            case (nil, nil): return nil
            }
        }()
        filters.amountRange = intersectAmountRanges(query.amountRange, manualAmount)

        // Type: manual overrides NLP
        filters.type = manualType ?? query.transactionType

        // Keyword: combine NLP + manual
        let combined = [query.keyword, manualKeyword.isEmpty ? nil : manualKeyword]
            .compactMap { $0 }.filter { !$0.isEmpty }
        filters.keyword = combined.isEmpty ? nil : combined.joined(separator: " ")

        // Multi-select: manual only (NLP can't parse these)
        filters.categoryIDs = selectedCategoryIDs.isEmpty ? nil : selectedCategoryIDs
        filters.memberIDs = selectedMemberIDs.isEmpty ? nil : selectedMemberIDs
        filters.merchantIDs = selectedMerchantIDs.isEmpty ? nil : selectedMerchantIDs
        filters.projectIDs = selectedProjectIDs.isEmpty ? nil : selectedProjectIDs

        return filters
    }

    // MARK: - Range Helpers

    private func intersectRanges(_ a: Range<Date>?, _ b: Range<Date>?) -> Range<Date>? {
        switch (a, b) {
        case (let a?, let b?):
            let lower = max(a.lowerBound, b.lowerBound)
            let upper = min(a.upperBound, b.upperBound)
            return lower < upper ? lower..<upper : nil
        case (let a?, nil): return a
        case (nil, let b?): return b
        case (nil, nil): return nil
        }
    }

    private func intersectAmountRanges(_ a: ClosedRange<Decimal>?, _ b: ClosedRange<Decimal>?) -> ClosedRange<Decimal>? {
        switch (a, b) {
        case (let a?, let b?):
            let lower = Swift.max(a.lowerBound, b.lowerBound)
            let upper = Swift.min(a.upperBound, b.upperBound)
            return lower <= upper ? lower...upper : nil
        case (let a?, nil): return a
        case (nil, let b?): return b
        case (nil, nil): return nil
        }
    }

    // MARK: - NL Parser

    private func parseWithNLFallback(_ text: String) async -> ParsedSearchQuery {
        #if canImport(FoundationModels)
        if #available(iOS 27.0, *) {
            let model = SystemLanguageModel()
            switch model.availability {
            case .available:
                if let nlResult = await NLQueryParser.parse(text),
                   !nlResult.isEmpty {
                    return nlResult
                }
            case .unavailable(let reason):
                let status: String
                switch reason {
                case .deviceNotEligible: status = "设备不支持"
                case .appleIntelligenceNotEnabled: status = "Apple Intelligence未开启"
                case .modelNotReady: status = "模型未就绪"
                @unknown default: status = "未知原因"
                }
                Logger.info("NL模型不可用: \(status) → 回退规则引擎 | 输入: \(text)")
            }
        }
        #endif
        let result = ChineseExpressionParser.parse(text)
        DiagnosticLog.log("[搜索] 规则引擎 | 日期:\(result.dateKeyword ?? "无") 类型:\(result.typeKeyword ?? "无") 关键词:\(result.keyword ?? "无")")
        return result
    }
}
