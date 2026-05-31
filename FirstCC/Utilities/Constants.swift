import Foundation

enum Constants {
    static let appName = "钱伲"
    static let bundleIdentifier = "com.qianey.app"
    static let defaultCurrency = "CNY"
    static let defaultLocale = "zh_CN"

    static let maxPhotoAttachments = 5
    static let maxTagsPerTransaction = 10
    static let recentTransactionsLimit = 10

    static let budgetAlertThresholdDefault = 0.8
}

extension Notification.Name {
    static let transactionDidChange = Notification.Name("FirstCC.transactionDidChange")
}
