import Foundation
import SwiftData

@Model
final class Member {
    var id: UUID
    var name: String
    var avatar: String
    var isActive: Bool
    var sortOrder: Int

    var ledger: Ledger?

    init(id: UUID = UUID(), name: String, avatar: String = "person.circle", isActive: Bool = true, sortOrder: Int = 0) {
        self.id = id
        self.name = name
        self.avatar = avatar
        self.isActive = isActive
        self.sortOrder = sortOrder
    }
}
