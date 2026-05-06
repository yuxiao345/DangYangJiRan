import Foundation

enum ReimbursementStatus: String, Codable, CaseIterable {
    case none = "无"
    case pending = "待报销"
    case approved = "已批准"
    case reimbursed = "已报销"
}
