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

enum FirstCCSchemaV2: VersionedSchema {
    static var versionIdentifier = Schema.Version(2, 0, 0)

    static var models: [any PersistentModel.Type] = [
        Ledger.self, User.self, Account.self, Category.self,
        Transaction.self, TransactionTemplate.self, RecurringRule.self,
        SplitGroup.self, SplitEntry.self, BudgetBook.self, BudgetItem.self,
        InstallmentPlan.self,
        ExchangeRate.self, Member.self, Merchant.self, Project.self, CreditCardStatement.self
    ]
}

enum FirstCCSchemaV3: VersionedSchema {
    static var versionIdentifier = Schema.Version(3, 0, 0)

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
        FirstCCSchemaV1.self,
        FirstCCSchemaV2.self,
        FirstCCSchemaV3.self
    ]

    static var stages: [MigrationStage] = [
        MigrationStage.lightweight(fromVersion: FirstCCSchemaV1.self, toVersion: FirstCCSchemaV2.self),
        MigrationStage.lightweight(fromVersion: FirstCCSchemaV2.self, toVersion: FirstCCSchemaV3.self)
    ]
}
