import Foundation

/// 中文转拼音搜索键，供选择器做拼音／首字母搜索。
///
/// 用 Foundation 内置的 `CFStringTransform` 实现，不引第三方拼音表（仓库本就无第三方依赖）：
/// 先 `kCFStringTransformToLatin` 转成带声调的拉丁串，再 `kCFStringTransformStripCombiningMarks`
/// 去掉声调符号。
///
/// 实测（2026-10-07，本机 swift 直跑）：
/// - `餐饮饮食` → 全拼 `canyinyinshi`、首字母 `cyys`
/// - `交通出行` → `jiaotongchuxing` / `jtcx`
/// - `café` → `cafe`（去声调对西文同样生效）
///
/// 已知边界：纯拉丁词会被当成**一个**音节（`ATM取款` → `ATM qu kuan`），
/// 首字母因此是 `aqk` 而非 `atmqk`；但全拼 `atmqukuan` 仍含 `atm`，
/// 走全拼子串命中这条路能覆盖。
enum PinyinHelper {
    /// 一次转换的预计算结果。列表每次按键都要过滤，转换本身不便宜，
    /// 所以由调用方缓存本结构，而不是每次过滤重跑 `CFStringTransform`。
    struct SearchKey: Sendable {
        /// 原文小写（中文原样保留，用于中文子串命中）
        let lowered: String
        /// 全拼，小写、无空格
        let full: String
        /// 每音节首字母，小写
        let initials: String

        init(_ text: String) {
            let latin = Self.latinized(text)
            self.lowered = text.lowercased()
            self.full = latin.replacingOccurrences(of: " ", with: "").lowercased()
            self.initials = latin
                .split(separator: " ")
                .compactMap(\.first)
                .map(String.init)
                .joined()
                .lowercased()
        }

        /// 中文原文 / 全拼 / 首字母 任一包含 query 即命中。query 需已小写并去掉首尾空白。
        func matches(_ query: String) -> Bool {
            guard !query.isEmpty else { return true }
            return lowered.contains(query) || full.contains(query) || initials.contains(query)
        }

        private static func latinized(_ text: String) -> String {
            let mutable = NSMutableString(string: text) as CFMutableString
            CFStringTransform(mutable, nil, kCFStringTransformToLatin, false)
            CFStringTransform(mutable, nil, kCFStringTransformStripCombiningMarks, false)
            return mutable as String
        }
    }
}
