import UIKit
import SwiftUI

struct BankLogoPreset: Identifiable, Hashable {
    let id: String
    let name: String
    let shortName: String
    let colorHex: String
    let category: BankCategory

    enum BankCategory: String, CaseIterable {
        case stateOwned = "国有银行"
        case nationalCommercial = "全国股份制"
        case cityCommercial = "城市商业银行"
        case rural = "农商行"
        case foreign = "外资银行"
        case online = "互联网银行"
    }

    var logoImage: UIImage {
        if let cached = BankLogoPresets.imageCache[id] { return cached }
        let img = BankLogoPresets.generateLogo(shortName: shortName, colorHex: colorHex)
        BankLogoPresets.imageCache[id] = img
        return img
    }

    var logoData: Data? { logoImage.pngData() }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: BankLogoPreset, rhs: BankLogoPreset) -> Bool { lhs.id == rhs.id }
}

enum BankLogoPresets {
    static var imageCache: [String: UIImage] = [:]

    static let all: [BankLogoPreset] = stateOwned + nationalCommercial + cityCommercial + rural + foreign + online

    static let stateOwned: [BankLogoPreset] = [
        BankLogoPreset(id: "icbc", name: "中国工商银行", shortName: "工行", colorHex: "#CC0000", category: .stateOwned),
        BankLogoPreset(id: "abc", name: "中国农业银行", shortName: "农行", colorHex: "#009B77", category: .stateOwned),
        BankLogoPreset(id: "boc", name: "中国银行", shortName: "中行", colorHex: "#B81C30", category: .stateOwned),
        BankLogoPreset(id: "ccb", name: "中国建设银行", shortName: "建行", colorHex: "#004B8D", category: .stateOwned),
        BankLogoPreset(id: "bocom", name: "交通银行", shortName: "交行", colorHex: "#004A91", category: .stateOwned),
        BankLogoPreset(id: "psbc", name: "中国邮政储蓄银行", shortName: "邮储", colorHex: "#009944", category: .stateOwned),
    ]

    static let nationalCommercial: [BankLogoPreset] = [
        BankLogoPreset(id: "cmb", name: "招商银行", shortName: "招商", colorHex: "#C41230", category: .nationalCommercial),
        BankLogoPreset(id: "spdb", name: "浦发银行", shortName: "浦发", colorHex: "#004A8E", category: .nationalCommercial),
        BankLogoPreset(id: "cib", name: "兴业银行", shortName: "兴业", colorHex: "#004C97", category: .nationalCommercial),
        BankLogoPreset(id: "cmbc", name: "民生银行", shortName: "民生", colorHex: "#009B6B", category: .nationalCommercial),
        BankLogoPreset(id: "citic", name: "中信银行", shortName: "中信", colorHex: "#CC0000", category: .nationalCommercial),
        BankLogoPreset(id: "ceb", name: "光大银行", shortName: "光大", colorHex: "#903596", category: .nationalCommercial),
        BankLogoPreset(id: "hxb", name: "华夏银行", shortName: "华夏", colorHex: "#CC0000", category: .nationalCommercial),
        BankLogoPreset(id: "gdb", name: "广发银行", shortName: "广发", colorHex: "#CC0000", category: .nationalCommercial),
        BankLogoPreset(id: "pab", name: "平安银行", shortName: "平安", colorHex: "#E55934", category: .nationalCommercial),
        BankLogoPreset(id: "boh", name: "渤海银行", shortName: "渤海", colorHex: "#004B8D", category: .nationalCommercial),
        BankLogoPreset(id: "hkb", name: "恒丰银行", shortName: "恒丰", colorHex: "#003F80", category: .nationalCommercial),
        BankLogoPreset(id: "cgb", name: "浙商银行", shortName: "浙商", colorHex: "#C41230", category: .nationalCommercial),
    ]

    static let cityCommercial: [BankLogoPreset] = [
        BankLogoPreset(id: "bob", name: "北京银行", shortName: "北京", colorHex: "#CC0000", category: .cityCommercial),
        BankLogoPreset(id: "bos", name: "上海银行", shortName: "上海", colorHex: "#004C97", category: .cityCommercial),
        BankLogoPreset(id: "njcb", name: "南京银行", shortName: "南京", colorHex: "#009B77", category: .cityCommercial),
        BankLogoPreset(id: "nbcb", name: "宁波银行", shortName: "宁波", colorHex: "#F58220", category: .cityCommercial),
        BankLogoPreset(id: "jsb", name: "江苏银行", shortName: "江苏", colorHex: "#004C97", category: .cityCommercial),
        BankLogoPreset(id: "hzb", name: "杭州银行", shortName: "杭州", colorHex: "#009B6B", category: .cityCommercial),
        BankLogoPreset(id: "sdb", name: "深圳发展银行", shortName: "深发", colorHex: "#004B8D", category: .cityCommercial),
        BankLogoPreset(id: "cdb", name: "成都银行", shortName: "成都", colorHex: "#CC0000", category: .cityCommercial),
        BankLogoPreset(id: "tccb", name: "天津银行", shortName: "天津", colorHex: "#004C97", category: .cityCommercial),
    ]

    static let rural: [BankLogoPreset] = [
        BankLogoPreset(id: "bjrcb", name: "北京农商银行", shortName: "京农商", colorHex: "#009944", category: .rural),
        BankLogoPreset(id: "shrcb", name: "上海农商银行", shortName: "沪农商", colorHex: "#004C97", category: .rural),
        BankLogoPreset(id: "grcb", name: "广州农商银行", shortName: "穗农商", colorHex: "#009B77", category: .rural),
        BankLogoPreset(id: "crcb", name: "重庆农商银行", shortName: "渝农商", colorHex: "#CC0000", category: .rural),
    ]

    static let foreign: [BankLogoPreset] = [
        BankLogoPreset(id: "hsbc", name: "汇丰银行", shortName: "汇丰", colorHex: "#CC0000", category: .foreign),
        BankLogoPreset(id: "citi", name: "花旗银行", shortName: "花旗", colorHex: "#004B87", category: .foreign),
        BankLogoPreset(id: "sc", name: "渣打银行", shortName: "渣打", colorHex: "#009639", category: .foreign),
        BankLogoPreset(id: "hs", name: "恒生银行", shortName: "恒生", colorHex: "#00945E", category: .foreign),
        BankLogoPreset(id: "boc", name: "东亚银行", shortName: "东亚", colorHex: "#CC0000", category: .foreign),
    ]

    static let online: [BankLogoPreset] = [
        BankLogoPreset(id: "webank", name: "微众银行", shortName: "微众", colorHex: "#9040E0", category: .online),
        BankLogoPreset(id: "mybank", name: "网商银行", shortName: "网商", colorHex: "#FF6600", category: .online),
    ]

    static func generateLogo(shortName: String, colorHex: String) -> UIImage {
        let size = CGSize(width: 80, height: 80)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            let rect = CGRect(origin: .zero, size: size)
            let color = UIColor(hex: colorHex) ?? .systemBlue

            // Rounded rect background
            let path = UIBezierPath(roundedRect: rect, cornerRadius: 16)
            color.setFill()
            path.fill()

            // Text
            let text = shortName.count > 2 ? String(shortName.prefix(2)) : shortName
            let fontSize: CGFloat = shortName.count > 2 ? 28 : 32
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: fontSize, weight: .bold),
                .foregroundColor: UIColor.white
            ]
            let textSize = text.size(withAttributes: attrs)
            let textRect = CGRect(
                x: (size.width - textSize.width) / 2,
                y: (size.height - textSize.height) / 2,
                width: textSize.width,
                height: textSize.height
            )
            text.draw(in: textRect, withAttributes: attrs)
        }
    }
}

private extension UIColor {
    convenience init?(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b, a: UInt64
        switch hex.count {
        case 6:
            (r, g, b, a) = ((int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF, 255)
        case 8:
            (r, g, b, a) = ((int >> 24) & 0xFF, (int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default: return nil
        }
        self.init(red: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: CGFloat(a) / 255)
    }
}
