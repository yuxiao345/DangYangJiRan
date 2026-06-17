import SwiftUI
@preconcurrency import CoreData

// MARK: - Navigation

enum MacNavItem: String, CaseIterable, Identifiable {
    case dashboard = "总览"
    case accounts = "账户"
    case transactions = "流水"
    case reports = "报表"
    case settings = "设置"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .dashboard: "rectangle.3.group"
        case .accounts: "creditcard"
        case .transactions: "list.bullet"
        case .reports: "chart.bar"
        case .settings: "gearshape"
        }
    }
}

