import Foundation
@preconcurrency import CoreData

enum CategorySeeder {
    static func seed(modelContext: NSManagedObjectContext, ledger: Ledger) {
        let expenseCategories: [(name: String, icon: String, color: String, sub: [(String, String, String)])] = [
            ("餐饮饮食", "fork.knife", "#FF6B35", [
                ("三餐", "sun.max", "#FF8C5A"),
                ("零食", "carrot.fill", "#FFA07A"),
                ("水果", "apple.logo", "#FFAB76"),
                ("饮料", "cup.and.saucer.fill", "#FFB347"),
                ("烟酒", "flame.fill", "#D2691E"),
                ("米面粮油", "takeoutbag.and.cup.and.straw", "#DEB887"),
            ]),
            ("交通出行", "car.fill", "#607D8B", [
                ("公共交通", "bus.fill", "#78909C"),
                ("共享单车", "bicycle", "#8D9FA8"),
                ("打车租车", "car.front.waves.up", "#708090"),
                ("飞机火车", "airplane", "#5F9EA0"),
                ("充电加油", "fuelpump.fill", "#6D8C8C"),
                ("过路过桥", "road.lanes", "#7F8C8D"),
                ("交通保险", "shield.checkered", "#808B96"),
                ("违章罚款", "exclamationmark.triangle.fill", "#A0522D"),
                ("停车车位", "parkingsign", "#8B9DAF"),
            ]),
            ("购物消费", "bag.fill", "#E91E63", [
                ("服饰鞋包", "tshirt.fill", "#EC407A"),
                ("数码产品", "desktopcomputer", "#F06292"),
                ("家居百货", "sofa.fill", "#F48FB1"),
                ("护肤化妆", "sparkles", "#F8BBD0"),
                ("金银首饰", "crown.fill", "#FFD700"),
                ("日用消耗", "basket.fill", "#FFB6C1"),
                ("软件授权", "key.icloud", "#DB7093"),
            ]),
            ("住房居家", "house.fill", "#795548", [
                ("房租房贷", "house.lodge.fill", "#8D6E63"),
                ("物业管理", "building.2.fill", "#A1887F"),
                ("水电燃气", "bolt.fill", "#BCAAA4"),
                ("维修装修", "wrench.and.screwdriver.fill", "#9E9E9E"),
                ("家政服务", "figure.child.and.lock.open", "#C4A882"),
                ("美容美发", "scissors", "#D2B48C"),
            ]),
            ("通讯网络", "antenna.radiowaves.left.and.right", "#00BCD4", [
                ("手机", "phone.fill", "#26C6DA"),
                ("宽带", "wifi", "#4DD0E1"),
                ("快递邮寄", "shippingbox.fill", "#80DEEA"),
            ]),
            ("休闲娱乐", "tv.fill", "#673AB7", [
                ("运动健身", "figure.run", "#7E57C2"),
                ("聚会活动", "person.3.fill", "#9575CD"),
                ("旅游", "airplane.departure", "#B39DDB"),
                ("影视服务", "play.tv.fill", "#7C4DFF"),
                ("电影音乐", "music.note.list", "#9C27B0"),
                ("游戏服务订阅", "gamecontroller.fill", "#AB47BC"),
            ]),
            ("医疗健康", "cross.case.fill", "#4CAF50", [
                ("门诊挂号", "stethoscope", "#66BB6A"),
                ("医疗药品", "pills.fill", "#81C784"),
                ("住院手术", "bed.double.fill", "#A5D6A7"),
                ("医疗保险", "heart.circle.fill", "#43A047"),
                ("保健预防", "figure.strengthtraining.traditional", "#C8E6C9"),
                ("物品设备", "ear.badge.waveform", "#2E7D32"),
            ]),
            ("教育学习", "book.fill", "#2196F3", [
                ("书本教材", "book.closed.fill", "#42A5F5"),
                ("报名考试", "pencil.and.list.clipboard", "#64B5F6"),
                ("教育服务订阅", "graduationcap.fill", "#90CAF9"),
            ]),
            ("人情往来", "gift.fill", "#FF9800", [
                ("送礼请客", "giftcard.fill", "#FFA726"),
                ("孝敬家长", "heart.fill", "#FFB74D"),
                ("慈善捐助", "hand.raised.fill", "#FFCC80"),
                ("社交红包", "envelope.fill", "#E65100"),
            ]),
            ("金融保险", "yensign.circle.fill", "#9E9E9E", [
                ("银行手续", "building.columns.fill", "#BDBDBD"),
                ("投资亏损", "chart.line.downtrend.xyaxis", "#E57373"),
                ("按揭还款", "creditcard.fill", "#A1887F"),
                ("消费税收", "doc.text.fill", "#E0E0E0"),
                ("利息支出", "percent", "#B0BEC5"),
                ("赔偿罚款", "exclamationmark.octagon.fill", "#FF8A65"),
                ("黑洞", "nosign", "#424242"),
            ]),
            ("宠植养护", "pawprint.fill", "#8D6E63", [
                ("宠物食品", "fish.fill", "#A1887F"),
                ("宠物用品", "waterbottle.fill", "#9E9E9E"),
                ("宠植医疗", "cross.case", "#A0522D"),
                ("宠植洗护", "shower.fill", "#BCAAA4"),
            ]),
            ("置业投资", "building.columns.fill", "#3F51B5", [
                ("房屋", "house.circle.fill", "#5C6BC0"),
                ("汽车", "car.2.fill", "#7986CB"),
                ("车位", "parkingsign.circle.fill", "#9FA8DA"),
                ("商铺", "storefront.fill", "#C5CAE9"),
                ("黄金白银", "bitcoinsign.circle.fill", "#E8D44D"),
            ]),
            ("其他支出", "ellipsis", "#757575", []),
        ]

        let incomeCategories: [(name: String, icon: String, color: String, sub: [(String, String, String)])] = [
            ("工资薪金", "dollarsign.circle.fill", "#4CAF50", [
                ("基本工资", "banknote.fill", "#66BB6A"),
                ("一次性奖金", "star.fill", "#81C784"),
                ("年终奖", "gift.fill", "#A5D6A7"),
                ("补贴", "doc.text.image.fill", "#C8E6C9"),
                ("兼职收入", "laptopcomputer", "#2E7D32"),
            ]),
            ("投资收益", "chart.line.uptrend.xyaxis", "#009688", [
                ("股票", "chart.bar.fill", "#26A69A"),
                ("基金", "chart.pie.fill", "#4DB6AC"),
                ("理财", "creditcard.and.123", "#80CBC4"),
            ]),
            ("副业所得", "hammer.fill", "#8BC34A", []),
            ("礼金收入", "gift.fill", "#E91E63", []),
            ("退款返利", "arrow.uturn.backward.circle.fill", "#FF5722", []),
            ("变卖资产", "tag.fill", "#FF9800", []),
            ("其他收入", "plus.circle.fill", "#607D8B", []),
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
