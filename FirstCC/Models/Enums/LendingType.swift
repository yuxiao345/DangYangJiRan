import Foundation

enum LendingType: String, Codable, CaseIterable {
    case borrow = "借入"
    case lend = "借出"
}
