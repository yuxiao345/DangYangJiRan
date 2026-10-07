import Foundation
import Testing
@testable import Qianeymac

/// 期望值来自 2026-10-07 用 `swift` 直跑 `CFStringTransform` 的实测输出，
/// 不是照着印象写的。
struct PinyinHelperTests {
    @Test func fullPinyin_stripsSpacesAndLowercases() {
        #expect(PinyinHelper.SearchKey("餐饮饮食").full == "canyinyinshi")
        #expect(PinyinHelper.SearchKey("交通出行").full == "jiaotongchuxing")
    }

    @Test func initials_takeFirstLetterPerSyllable() {
        #expect(PinyinHelper.SearchKey("餐饮饮食").initials == "cyys")
        #expect(PinyinHelper.SearchKey("交通出行").initials == "jtcx")
    }

    @Test func latinText_isLeftAloneButFoldedToLowercase() {
        #expect(PinyinHelper.SearchKey("Alipay").full == "alipay")
        #expect(PinyinHelper.SearchKey("café").full == "cafe")
    }

    /// 已知边界的固化：整词拉丁前缀被当成一个音节，首字母取不到完整的 `atm`，
    /// 但全拼子串仍能命中——正好锁住文档注释里那条「走全拼命中」的说法。
    @Test func mixedLatinAndHan_initialsLoseWholeWordButFullPinyinKeepsIt() {
        let key = PinyinHelper.SearchKey("ATM取款")
        #expect(key.initials == "aqk")
        #expect(key.full == "atmqukuan")
        #expect(key.matches("atm"))
    }

    @Test func matches_hitsChineseSubstring() {
        #expect(PinyinHelper.SearchKey("餐饮饮食").matches("餐饮"))
        // 是子串匹配、不是子序列匹配：「餐」「食」在原名里不连续，不命中
        #expect(PinyinHelper.SearchKey("餐饮饮食").matches("餐食") == false)
    }

    @Test func matches_hitsPinyinAndInitials() {
        let key = PinyinHelper.SearchKey("交通出行")
        #expect(key.matches("jiaotong"))
        #expect(key.matches("jtcx"))
        #expect(key.matches("chuxing"))
    }

    @Test func matches_missesUnrelatedQuery() {
        #expect(PinyinHelper.SearchKey("餐饮饮食").matches("jiaotong") == false)
    }

    /// 空查询视为全命中（调用方在空搜索时直接返回全量，这里是兜底语义）
    @Test func matches_emptyQueryAlwaysTrue() {
        #expect(PinyinHelper.SearchKey("餐饮饮食").matches(""))
    }
}
