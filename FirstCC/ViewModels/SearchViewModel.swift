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
    }

    var totalCount: Int { searchResults.count }

    var totalAmount: Decimal {
        searchResults.reduce(0) { $0 + $1.amount }
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
            chips.append(FilterChip(label: "分类(\(selectedCategoryIDs.count))", isManual: true, clearAction: { [weak self] in
                self?.selectedCategoryIDs.removeAll()
            }))
        }

        // Member count chip
        if !selectedMemberIDs.isEmpty {
            chips.append(FilterChip(label: "成员(\(selectedMemberIDs.count))", isManual: true, clearAction: { [weak self] in
                self?.selectedMemberIDs.removeAll()
            }))
        }

        // Project count chip
        if !selectedProjectIDs.isEmpty {
            chips.append(FilterChip(label: "项目(\(selectedProjectIDs.count))", isManual: true, clearAction: { [weak self] in
                self?.selectedProjectIDs.removeAll()
            }))
        }

        return chips
    }

    var hasManualFilters: Bool {
        !selectedCategoryIDs.isEmpty || !selectedMemberIDs.isEmpty || !selectedProjectIDs.isEmpty
        || dateFrom != nil || dateTo != nil || amountMin != nil || amountMax != nil
        || manualType != nil || !manualKeyword.isEmpty
    }

    var hasResults: Bool { !searchResults.isEmpty }

    // MARK: - Toggle Helpers

    func toggleCategory(_ id: UUID) { selectedCategoryIDs.toggle(id) }
    func toggleMember(_ id: UUID)   { selectedMemberIDs.toggle(id) }
    func toggleProject(_ id: UUID)  { selectedProjectIDs.toggle(id) }

    func clearAllManualFilters() {
        selectedCategoryIDs.removeAll()
        selectedMemberIDs.removeAll()
        selectedProjectIDs.removeAll()
        dateFrom = nil
        dateTo = nil
        amountMin = nil
        amountMax = nil
        manualType = nil
        manualKeyword = ""
    }

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
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            performSearch(text: text, context: context)
        }
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
        Task { @MainActor in
            var query = ParsedSearchQuery()
            if !text.trimmingCharacters(in: .whitespaces).isEmpty {
                query = await parseWithNLFallback(text)
            }
            self.parsedQuery = query

            var filters = TransactionFilters()

            // Merge NLP date + manual date (narrowest wins)
            let manualDate: Range<Date>? = {
                if let from = dateFrom, let to = dateTo {
                    return min(from, to)..<max(from, to)
                } else if let from = dateFrom {
                    return from..<Date.distantFuture
                } else if let to = dateTo {
                    return Date.distantPast..<to
                }
                return nil
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
            filters.projectIDs = selectedProjectIDs.isEmpty ? nil : selectedProjectIDs

            let results = (try? transactionService.fetchTransactions(
                for: ledger, context: context, filters: filters
            )) ?? []

            self.searchResults = results
            self.isSearching = false
        }
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
