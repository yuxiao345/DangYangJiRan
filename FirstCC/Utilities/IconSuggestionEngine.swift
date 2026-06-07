import Foundation

/// 中文分类名称 → SF Symbol 图标推荐引擎
///
/// 流程：输入中文名 → 子串匹配关键词表 → 获得英文搜索词 → 在候选符号库中子串匹配 → 返回推荐图标
enum IconSuggestionEngine {

    // MARK: - 中文关键词 → 英文搜索词

    private static let keywordMap: [(keyword: String, searchTerms: [String])] = [
        // 餐饮
        ("餐饮", ["fork.knife", "cart", "basket", "cup", "leaf"]),
        ("吃饭", ["fork.knife", "cart", "basket"]),
        ("外卖", ["fork.knife", "cart", "bag"]),
        ("食品", ["fork.knife", "cart", "leaf"]),
        ("零食", ["fork.knife", "cart", "bag"]),
        ("水果", ["leaf", "cart", "fork.knife"]),
        ("买菜", ["cart", "basket", "leaf"]),
        ("食堂", ["fork.knife", "cup"]),
        ("早餐", ["fork.knife", "cup"]),
        ("午餐", ["fork.knife", "cup"]),
        ("晚餐", ["fork.knife", "cup"]),
        ("咖啡", ["cup"]),
        ("奶茶", ["cup"]),
        ("饮料", ["cup"]),

        // 交通
        ("交通", ["car", "bus", "fuelpump", "bicycle", "tram"]),
        ("出行", ["car", "bus", "airplane", "bicycle"]),
        ("打车", ["car"]),
        ("地铁", ["tram", "bus"]),
        ("公交", ["bus"]),
        ("火车", ["tram", "bus"]),
        ("加油", ["fuelpump", "car"]),
        ("停车", ["car", "parking"]),
        ("高速", ["car", "road"]),
        ("洗车", ["car", "drop"]),
        ("保养", ["car", "wrench"]),
        ("骑行", ["bicycle"]),
        ("共享单车", ["bicycle"]),

        // 住房
        ("住房", ["house", "bed", "building"]),
        ("房租", ["house", "building", "bed"]),
        ("房贷", ["house", "building", "bank"]),
        ("物业", ["house", "building", "wrench"]),
        ("维修", ["wrench", "hammer"]),
        ("搬家", ["box", "truck", "house"]),

        // 购物
        ("购物", ["bag", "cart", "basket", "store"]),
        ("消费", ["bag", "cart", "creditcard"]),
        ("百货", ["bag", "cart", "basket"]),
        ("日用品", ["bag", "cart", "basket"]),
        ("超市", ["cart", "basket", "bag"]),
        ("网购", ["bag", "cart", "shipping"]),

        // 娱乐
        ("娱乐", ["film", "gamecontroller", "music", "tv", "theatre"]),
        ("电影", ["film", "tv"]),
        ("游戏", ["gamecontroller"]),
        ("音乐", ["music"]),
        ("演出", ["theatre", "music"]),
        ("KTV", ["music"]),

        // 旅行
        ("旅游", ["airplane", "suitcase", "hotel", "map"]),
        ("旅行", ["airplane", "suitcase", "hotel", "map"]),
        ("机票", ["airplane"]),
        ("酒店", ["hotel", "bed"]),
        ("景点", ["map", "camera"]),
        ("签证", ["doc", "airplane"]),

        // 医疗
        ("医疗", ["cross", "pill", "heart", "bandage"]),
        ("看病", ["cross", "stethoscope", "heart"]),
        ("药", ["pill", "cross"]),
        ("医院", ["cross", "stethoscope", "bed"]),
        ("体检", ["heart", "stethoscope", "cross"]),
        ("牙科", ["cross", "mouth"]),
        ("挂号", ["cross", "doc"]),

        // 教育
        ("教育", ["book", "graduationcap", "pencil", "backpack"]),
        ("书", ["book"]),
        ("学费", ["graduationcap", "book", "dollarsign"]),
        ("培训", ["book", "pencil", "graduationcap"]),
        ("文具", ["pencil", "scissors"]),
        ("考试", ["pencil", "rosette", "book"]),
        ("课程", ["book", "pencil"]),
        ("网课", ["laptop", "book", "wifi"]),

        // 通讯
        ("通讯", ["wifi", "phone", "antenna", "network"]),
        ("网络", ["wifi", "network"]),
        ("电话", ["phone"]),
        ("手机", ["phone"]),
        ("宽带", ["wifi", "antenna"]),
        ("快递", ["shipping", "box"]),
        ("邮寄", ["shipping", "envelope"]),

        // 收入
        ("工资", ["dollarsign", "yensign", "banknote", "briefcase"]),
        ("薪水", ["dollarsign", "yensign", "banknote"]),
        ("奖金", ["dollarsign", "yensign", "banknote", "star"]),
        ("理财", ["chart", "dollarsign", "percent", "bank"]),
        ("投资", ["chart", "dollarsign", "percent", "building"]),
        ("分红", ["dollarsign", "chart", "percent"]),
        ("利息", ["dollarsign", "yensign", "percent", "chart"]),
        ("租金", ["building", "house", "dollarsign"]),
        ("退税", ["doc", "dollarsign", "arrow"]),
        ("兼职", ["briefcase", "dollarsign"]),
        ("外快", ["dollarsign", "banknote"]),
        ("报销", ["doc", "dollarsign", "arrow"]),
        ("收款", ["dollarsign", "banknote", "arrow"]),

        // 保险
        ("保险", ["shield", "umbrella", "heart"]),
        ("社保", ["shield", "building", "doc"]),
        ("医保", ["shield", "heart", "cross"]),
        ("车险", ["car", "shield"]),
        ("人寿", ["shield", "heart"]),

        // 育儿
        ("育儿", ["figure.child", "teddybear"]),
        ("奶粉", ["figure.child", "cart"]),
        ("尿布", ["figure.child"]),
        ("玩具", ["gamecontroller", "teddybear"]),
        ("托管", ["figure.child"]),
        ("早教", ["book", "figure.child"]),

        // 宠物
        ("宠物", ["pawprint", "cat", "dog", "heart"]),
        ("猫", ["cat", "pawprint"]),
        ("狗", ["dog", "pawprint"]),
        ("兽医", ["pawprint", "cross"]),
        ("粮食", ["pawprint", "cart", "bag"]),

        // 美容
        ("美容", ["sparkles", "comb", "drop", "scissors"]),
        ("美发", ["comb", "scissors"]),
        ("护肤", ["drop", "sparkles"]),
        ("化妆", ["sparkles", "drop"]),
        ("美甲", ["sparkles", "hand"]),
        ("理发", ["scissors", "comb"]),

        // 健身
        ("健身", ["dumbbell", "figure", "sportscourt"]),
        ("运动", ["figure", "dumbbell", "sportscourt"]),
        ("游泳", ["figure", "drop"]),
        ("瑜伽", ["figure", "sportscourt"]),
        ("跑步", ["figure"]),

        // 装修
        ("装修", ["house", "paintbrush", "hammer", "wrench"]),
        ("家具", ["sofa", "house", "lamp"]),
        ("家电", ["tv", "washer", "lamp"]),
        ("窗帘", ["house", "curtain"]),
        ("灯具", ["lamp"]),

        // 水电煤
        ("水费", ["drop"]),
        ("电费", ["bolt"]),
        ("燃气费", ["flame"]),
        ("暖气", ["thermometer", "flame"]),

        // 人情
        ("红包", ["envelope", "gift"]),
        ("礼物", ["gift"]),
        ("送礼", ["gift"]),
        ("聚餐", ["fork.knife", "party"]),
        ("婚礼", ["heart", "gift", "party"]),
        ("过年", ["gift", "party"]),
        ("聚会", ["party"]),

        // 办公
        ("办公", ["laptop", "printer", "pencil", "desk"]),
        ("电脑", ["laptop", "desktop", "keyboard"]),
        ("打印", ["printer", "doc"]),
        ("耗材", ["printer", "cart"]),

        // 数码
        ("数码", ["desktop", "phone", "headphone", "camera"]),
        ("电子", ["desktop", "phone", "camera", "tv"]),
        ("耳机", ["headphone"]),
        ("相机", ["camera"]),
        ("平板", ["ipad"]),

        // 借贷
        ("借款", ["creditcard", "banknote", "arrow"]),
        ("还款", ["creditcard", "banknote", "arrow"]),
        ("信用卡", ["creditcard"]),
        ("贷款", ["building", "bank", "percent"]),
        ("花呗", ["creditcard"]),

        // 转账
        ("转账", ["arrow.left.arrow.right", "banknote"]),
        ("汇款", ["arrow.left.arrow.right", "banknote"]),
        ("提现", ["arrow", "banknote"]),
        ("充值", ["arrow", "phone", "banknote"]),

        // 税收
        ("税", ["doc", "building", "percent"]),
        ("个税", ["doc", "percent", "dollarsign"]),
        ("增值税", ["doc", "percent"]),
        ("报税", ["doc", "building"]),

        // 衣物
        ("衣服", ["tshirt"]),
        ("鞋", ["shoe"]),
        ("包", ["handbag", "bag"]),
        ("饰品", ["crown", "sparkles"]),
        ("眼镜", ["eyeglasses"]),
        ("帽子", ["crown"]),

        // 家居
        ("家居", ["house", "washer", "bed"]),
        ("清洁", ["washer", "trash", "spray"]),
        ("洗衣", ["washer"]),
        ("打扫", ["trash", "spray"]),

        // 捐赠
        ("捐赠", ["heart", "gift", "hands"]),
        ("慈善", ["heart", "hands"]),
        ("布施", ["heart", "hands"]),
        ("公益", ["heart", "hands"]),

        // 烟酒
        ("烟", ["smoke"]),
        ("酒", ["wineglass", "cup"]),
        ("茶叶", ["cup", "leaf"]),

        // 其他
        ("其他", ["ellipsis", "questionmark", "square"]),
        ("杂项", ["ellipsis", "square"]),
        ("未知", ["questionmark"]),
    ]

    // MARK: - SF Symbol 候选库

    private static let symbolLibrary: [String] = [
        // 餐饮
        "fork.knife", "fork.knife.circle", "fork.knife.circle.fill",
        "cup.and.saucer", "cup.and.saucer.fill", "mug.fill", "wineglass", "wineglass.fill",
        "cart.fill", "cart.circle", "cart.circle.fill",
        "basket.fill", "basket",
        "leaf.fill", "leaf.circle", "leaf.circle.fill",

        // 交通
        "car.fill", "car.circle", "car.circle.fill", "car.front.waves.up.fill",
        "bus.fill", "bus", "tram.fill", "tram",
        "fuelpump.fill", "fuelpump.circle", "fuelpump.circle.fill",
        "bicycle", "bicycle.circle", "bicycle.circle.fill",
        "scooter",

        // 住房
        "house.fill", "house.circle", "house.circle.fill", "house.lodge.fill",
        "building.2.fill", "building.columns.fill", "building.columns.circle.fill",
        "bed.double.fill", "bed.double.circle.fill",
        "wrench.fill", "wrench.adjustable.fill",
        "hammer.fill", "hammer.circle.fill",
        "paintbrush.fill", "paintbrush.pointed.fill",

        // 购物
        "bag.fill", "bag.circle", "bag.circle.fill",
        "storefront.fill", "storefront.circle.fill",

        // 娱乐
        "film.fill", "film.circle.fill",
        "gamecontroller.fill", "gamecontroller.circle.fill",
        "music.note", "music.note.list", "music.mic",
        "tv.fill", "tv.circle.fill",
        "theatre.fill", "theatre.circle.fill",

        // 旅行
        "airplane", "airplane.circle.fill",
        "suitcase.fill", "suitcase.rolling.fill",
        "map.fill", "map.circle.fill",
        "ticket.fill",
        "camera.fill", "camera.circle.fill",

        // 医疗
        "cross.case.fill", "cross.case.circle.fill", "cross.fill", "cross.circle.fill",
        "pill.fill", "pill.circle.fill",
        "stethoscope", "stethoscope.circle.fill",
        "heart.fill", "heart.circle.fill",
        "bandage.fill",

        // 教育
        "book.fill", "book.circle.fill", "books.vertical.fill",
        "graduationcap.fill", "graduationcap.circle.fill",
        "pencil", "pencil.circle", "pencil.circle.fill",
        "backpack.fill", "backpack.circle.fill",
        "rosette",

        // 通讯
        "wifi", "wifi.circle.fill",
        "phone.fill", "phone.circle.fill",
        "antenna.radiowaves.left.and.right",
        "shippingbox.fill", "shippingbox.circle.fill",

        // 收入/钱
        "dollarsign.circle", "dollarsign.circle.fill", "dollarsign.square.fill",
        "yensign.circle", "yensign.circle.fill",
        "banknote.fill",
        "chart.line.uptrend.xyaxis", "chart.bar.fill", "chart.pie.fill",
        "chart.xyaxis.line",
        "percent",
        "briefcase.fill", "briefcase.circle.fill",

        // 保险
        "shield.fill", "shield.checkered",
        "umbrella.fill",

        // 育儿/宠物
        "figure.child", "figure.child.circle.fill",
        "teddybear.fill",
        "pawprint.fill", "pawprint.circle.fill",

        // 美容
        "comb.fill",
        "scissors",

        // 健身
        "figure.run", "figure.run.circle.fill",
        "dumbbell.fill",

        // 水电煤
        "drop.fill", "drop.circle.fill",
        "bolt.fill", "bolt.circle.fill",
        "flame.fill", "flame.circle.fill",

        // 人情
        "gift.fill", "gift.circle.fill",
        "envelope.fill", "envelope.circle.fill",
        "party.popper.fill",

        // 办公/数码
        "laptopcomputer", "laptopcomputer.and.iphone",
        "desktopcomputer",
        "printer.fill", "printer.dotmatrix.fill",
        "keyboard.fill",
        "headphone", "headphone.circle.fill",
        "iphone", "iphone.circle.fill",

        // 借贷/银行
        "creditcard.fill", "creditcard.circle.fill",
        "arrow.left.arrow.right", "arrow.left.arrow.right.circle.fill",
        "arrow.up.right", "arrow.down.left",
        "arrow.up.arrow.down",

        // 衣物
        "tshirt.fill", "tshirt.circle.fill",
        "shoe.fill",
        "handbag.fill",
        "eyeglasses",

        // 家居
        "washer.fill",
        "trash.fill", "trash.circle.fill",
        "sofa.fill",
        "lamp.table.fill", "lamp.ceiling.fill",

        // 文档
        "doc.fill", "doc.circle.fill", "doc.text.fill",

        // 通用
        "ellipsis", "ellipsis.circle", "ellipsis.circle.fill",
        "questionmark.circle", "questionmark.circle.fill",
        "square.grid.2x2.fill",
        "star.fill", "star.circle.fill",
        "sparkles",
        "tag.fill", "tag.circle.fill",
        "checkmark.circle.fill",
    ]

    // MARK: - Public API

    /// 根据分类名称推荐图标，最多返回 `max` 个
    static func suggestIcons(for name: String, max: Int = 8) -> [String] {
        guard !name.isEmpty else { return [] }

        let q = name.lowercased()

        // 收集所有命中的搜索词（去重，保持优先级顺序）
        var searchTerms: [String] = []
        var seenTerms: Set<String> = []
        for (keyword, terms) in keywordMap {
            if q.contains(keyword) || keyword.contains(q) {
                for term in terms {
                    if seenTerms.insert(term).inserted {
                        searchTerms.append(term)
                    }
                }
            }
        }

        // 无命中时返回空
        guard !searchTerms.isEmpty else { return [] }

        // 在符号库中做子串匹配
        var results: [String] = []
        var seen: Set<String> = []
        for term in searchTerms {
            for symbol in symbolLibrary {
                if symbol.contains(term), seen.insert(symbol).inserted {
                    results.append(symbol)
                    if results.count >= max { return results }
                }
            }
        }

        return results
    }
}
