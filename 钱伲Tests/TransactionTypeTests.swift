import XCTest
@testable import 钱伲

/// TransactionType 单元测试
/// 重点：allowsTagFields 必须与各表单的渲染 guard 逐字一致
final class TransactionTypeTests: XCTestCase {

    /// 「调整」必须为 true —— 调整类型的记账表单**是**渲染 分类/成员/商家/项目 的。
    /// 若把判定写成「支出/收入」白名单，调整交易的这四个字段会被误清。
    func test_allowsTagFields_matchesFormRenderGuards() {
        XCTAssertTrue(TransactionType.expense.allowsTagFields)
        XCTAssertTrue(TransactionType.income.allowsTagFields)
        XCTAssertTrue(TransactionType.adjustment.allowsTagFields)

        XCTAssertFalse(TransactionType.transfer.allowsTagFields)
        XCTAssertFalse(TransactionType.lending.allowsTagFields)
    }
}
