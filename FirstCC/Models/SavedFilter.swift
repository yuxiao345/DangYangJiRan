import Foundation

struct SavedFilter: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var dateFrom: Date?
    var dateTo: Date?
    var amountMin: Decimal?
    var amountMax: Decimal?
    var categoryIDs: [UUID]
    var memberIDs: [UUID]
    var projectIDs: [UUID]
    var keyword: String
    var createdAt: Date

    static func == (lhs: SavedFilter, rhs: SavedFilter) -> Bool { lhs.id == rhs.id }
}

extension UserDefaults {
    private static let savedFiltersKey = "saved_search_filters"

    func savedFilters() -> [SavedFilter] {
        guard let data = data(forKey: Self.savedFiltersKey),
              let filters = try? JSONDecoder().decode([SavedFilter].self, from: data) else {
            return []
        }
        return filters.sorted { $0.createdAt > $1.createdAt }
    }

    func saveFilter(_ filter: SavedFilter) {
        var filters = savedFilters()
        filters.removeAll { $0.id == filter.id }
        filters.insert(filter, at: 0)
        if let data = try? JSONEncoder().encode(Array(filters.prefix(20))) {
            set(data, forKey: Self.savedFiltersKey)
        }
    }

    func deleteFilter(id: UUID) {
        var filters = savedFilters()
        filters.removeAll { $0.id == id }
        if let data = try? JSONEncoder().encode(filters) {
            set(data, forKey: Self.savedFiltersKey)
        }
    }
}
