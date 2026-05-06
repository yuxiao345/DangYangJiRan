import Foundation
import SwiftData

@Model
final class Merchant {
    var id: UUID
    var name: String
    var category: String?
    var isActive: Bool
    var sortOrder: Int

    var ledger: Ledger?

    init(id: UUID = UUID(), name: String, category: String? = nil, isActive: Bool = true, sortOrder: Int = 0) {
        self.id = id
        self.name = name
        self.category = category
        self.isActive = isActive
        self.sortOrder = sortOrder
    }
}
