import Foundation
import CloudKit

enum CloudKitConfig {
    static let containerIdentifier = "iCloud.com.qianey"
    static let sharedScope = CKDatabase.Scope.shared
    static let privateScope = CKDatabase.Scope.private

    static let ledgerRecordType = "Ledger"
    static let transactionRecordType = "Transaction"
    static let accountRecordType = "Account"
    static let categoryRecordType = "Category"
}
