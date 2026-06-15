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

// MARK: - Settings Navigation

enum SettingsMainItem: String, CaseIterable, Identifiable {
    case appearance = "外观"
    case ledgers = "账本"
    case about = "关于"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .appearance: "paintbrush"
        case .ledgers: "books.vertical"
        case .about: "info.circle"
        }
    }
}

enum LedgerSettingsItem: String, CaseIterable, Identifiable {
    case categories = "分类管理"
    case members = "成员管理"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .categories: "square.grid.2x2"
        case .members: "person.2"
        }
    }
}
