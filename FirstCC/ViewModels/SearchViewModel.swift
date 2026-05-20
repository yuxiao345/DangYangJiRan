import Foundation
import SwiftData

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

    private var searchTask: Task<Void, Never>?

    init(ledger: Ledger, transactionService: TransactionServiceProtocol) {
        self.ledger = ledger
        self.transactionService = transactionService
    }

    var totalCount: Int { searchResults.count }

    var totalAmount: Decimal {
        searchResults.reduce(0) { $0 + abs($1.amount) }
    }

    var activeFilters: [String] {
        guard let q = parsedQuery else { return [] }
        var chips: [String] = []
        if let dk = q.dateKeyword { chips.append(dk) }
        if let ak = q.amountKeyword { chips.append(ak) }
        if let tk = q.typeKeyword { chips.append(tk) }
        return chips
    }

    var hasResults: Bool { !searchResults.isEmpty }

    func scheduleSearch(context: ModelContext) {
        searchTask?.cancel()
        searchResults = []
        parsedQuery = nil
        hasSearched = false

        guard !searchText.trimmingCharacters(in: .whitespaces).isEmpty else {
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

    private func performSearch(text: String, context: ModelContext) {
        let query = ChineseExpressionParser.parse(text)
        parsedQuery = query
        hasSearched = true

        var filters = TransactionFilters()
        filters.dateRange = query.dateRange
        filters.amountRange = query.amountRange
        filters.type = query.transactionType
        filters.keyword = query.keyword

        let results = (try? transactionService.fetchTransactions(
            for: ledger, context: context, filters: filters
        )) ?? []

        searchResults = results
        isSearching = false
    }
}
