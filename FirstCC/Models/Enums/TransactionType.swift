import Foundation

enum TransactionType: String, Codable, CaseIterable {
    case income = "收入"
    case expense = "支出"
    case transfer = "转账"
    case lending = "借贷"
    case adjustment = "调整"

    var displayName: String { NSLocalizedString(rawValue, comment: "") }

    var systemIcon: String {
        switch self {
        case .income: "arrow.down.circle"
        case .expense: "arrow.up.circle"
        case .transfer: "arrow.left.arrow.right.circle"
        case .lending: "arrow.triangle.swap"
        case .adjustment: "pencil.circle"
        }
    }

    /// 该类型是否使用 分类/成员/商家/项目 这四个字段。
    ///
    /// 转账和借贷不用它们：转账的一对账户本身就是语义（`createTransfer` 的参数里
    /// 没有这四个），借贷的对方由账户名表达。
    ///
    /// 判定必须与表单的渲染 guard 吻合：记账表单的 guard 是
    /// `!isSplit && type != .transfer && type != .lending`，所以用「支出/收入」白名单
    /// 会把「调整」误伤 —— 调整的表单**是**渲染这四个选择器的。模板和周期账表单的
    /// guard 只写了 `type != .transfer`（不含 lending），只因类型选择器不提供借贷才
    /// 没出问题；取值仍以此属性为准。
    ///
    /// 所有写入这四字段的地方都以此为准：记账表单、模板表单、周期账表单的保存，以及
    /// 从模板/周期账生成交易。避免把支出一侧的残留值带进转账/借贷记录 —— 这类值在
    /// UI 上不可见，用户也删不掉。
    var allowsTagFields: Bool { self != .transfer && self != .lending }
}
