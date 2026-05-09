import Foundation

enum BankMatchStatus: String, Codable, CaseIterable {
    case unmatched
    case matched
    case conflicted
    case ignored
}
