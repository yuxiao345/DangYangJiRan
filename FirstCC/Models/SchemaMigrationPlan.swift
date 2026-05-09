import SwiftData

enum FirstCCSchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] = [
        Ledger.self, User.self, Account.self, Category.self,
        Transaction.self, TransactionTemplate.self, RecurringRule.self,
        SplitGroup.self, SplitEntry.self, BudgetBook.self, BudgetItem.self,
        InstallmentPlan.self,
        ExchangeRate.self, Member.self, Merchant.self, Project.self, CreditCardStatement.self
    ]
}

struct FirstCCMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] = [
        FirstCCSchemaV1.self
    ]

    static var stages: [MigrationStage] = []
}
