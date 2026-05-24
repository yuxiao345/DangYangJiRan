import Foundation
@preconcurrency import CoreData

enum CategorySeeder {
    static func seed(modelContext: NSManagedObjectContext, ledger: Ledger) {
        let expenseCategories: [(name: String, icon: String, color: String, sub: [(String, String, String)])] = [
            ("餐饮", "fork.knife", "#FF6B35", [
                ("三餐", "sun.max", "#FF8C5A"),
                ("零食", "carrot", "#FFA07A"),
                ("聚餐", "person.3", "#FF7F50"),
            ]),
            ("交通", "car.fill", "#607D8B", [
                ("公交地铁", "bus", "#78909C"),
                ("加油", "fuelpump", "#8D9FA8"),
                ("停车", "parkingsign", "#9BA9B0"),
                ("打车", "car.front.waves.up", "#708090"),
            ]),
            ("购物", "bag.fill", "#E91E63", [
                ("服饰", "tshirt", "#EC407A"),
                ("日用品", "basket", "#F06292"),
                ("数码", "desktopcomputer", "#F48FB1"),
            ]),
            ("居家", "house.fill", "#795548", [
                ("房租", "house.lodge", "#8D6E63"),
                ("物业", "building.2", "#A1887F"),
                ("水电", "bolt.fill", "#BCAAA4"),
            ]),
            ("娱乐", "tv.fill", "#673AB7", [
                ("电影", "film", "#7E57C2"),
                ("游戏", "gamecontroller", "#9575CD"),
                ("旅行", "airplane", "#B39DDB"),
            ]),
            ("教育", "book.fill", "#2196F3", [
                ("学费", "graduationcap", "#42A5F5"),
                ("书籍", "book.closed", "#64B5F6"),
            ]),
            ("医疗", "cross.case.fill", "#4CAF50", [
                ("看病", "stethoscope", "#66BB6A"),
                ("药品", "pills", "#81C784"),
            ]),
            ("通讯", "antenna.radiowaves.left.and.right", "#00BCD4", [
                ("话费", "phone", "#26C6DA"),
                ("网络", "wifi", "#4DD0E1"),
            ]),
            ("人情", "gift.fill", "#FF9800", [
                ("红包", "envelope", "#FFA726"),
                ("礼物", "giftcard", "#FFB74D"),
            ]),
            ("金融", "yensign.circle", "#9E9E9E", [
                ("手续费", "doc.text", "#BDBDBD"),
                ("利息", "percent", "#E0E0E0"),
            ]),
            ("保险", "shield.checkered", "#3F51B5", []),
            ("宠物", "pawprint", "#8D6E63", []),
            ("其他", "ellipsis", "#757575", []),
        ]

        let incomeCategories: [(name: String, icon: String, color: String, sub: [(String, String, String)])] = [
            ("工资", "dollarsign.circle", "#4CAF50", [
                ("基本工资", "banknote", "#66BB6A"),
                ("奖金", "star", "#81C784"),
            ]),
            ("兼职", "laptopcomputer", "#8BC34A", []),
            ("投资", "chart.line.uptrend.xyaxis", "#009688", [
                ("股息", "chart.bar", "#26A69A"),
                ("基金", "chart.pie", "#4DB6AC"),
            ]),
            ("礼金", "gift.fill", "#E91E63", []),
            ("退款", "arrow.uturn.backward", "#FF5722", []),
            ("报销", "doc.text.magnifyingglass", "#FF9800", []),
            ("其他收入", "plus.circle", "#607D8B", []),
        ]

        var sortOrder = 0
        for cat in expenseCategories {
            let category = Category(
                name: cat.name,
                iconName: cat.icon,
                colorHex: cat.color,
                type: .expense,
                isSystem: true,
                sortOrder: sortOrder,
                context: modelContext
            )
            category.ledger = ledger
            sortOrder += 1

            for (subIdx, sub) in cat.sub.enumerated() {
                let subCategory = Category(
                    name: sub.0,
                    iconName: sub.1,
                    colorHex: sub.2,
                    type: .expense,
                    isSystem: true,
                    sortOrder: subIdx,
                    parent: category,
                    context: modelContext
                )
                subCategory.ledger = ledger
            }
        }

        for cat in incomeCategories {
            let category = Category(
                name: cat.name,
                iconName: cat.icon,
                colorHex: cat.color,
                type: .income,
                isSystem: true,
                sortOrder: sortOrder,
                context: modelContext
            )
            category.ledger = ledger
            sortOrder += 1

            for (subIdx, sub) in cat.sub.enumerated() {
                let subCategory = Category(
                    name: sub.0,
                    iconName: sub.1,
                    colorHex: sub.2,
                    type: .income,
                    isSystem: true,
                    sortOrder: subIdx,
                    parent: category,
                    context: modelContext
                )
                subCategory.ledger = ledger
            }
        }
    }
}
