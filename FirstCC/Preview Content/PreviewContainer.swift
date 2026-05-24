import SwiftUI
@preconcurrency import CoreData

@MainActor
enum PreviewContainer {
    static let context: NSManagedObjectContext = {
        guard let modelURL = Bundle.main.url(forResource: "FirstCC", withExtension: "momd"),
              let model = NSManagedObjectModel(contentsOf: modelURL) else {
            fatalError("PreviewContainer: Failed to load model")
        }

        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        do {
            try coordinator.addPersistentStore(ofType: NSInMemoryStoreType, configurationName: nil, at: nil)
        } catch {
            fatalError("PreviewContainer: Failed to add in-memory store: \(error)")
        }

        let ctx = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        ctx.persistentStoreCoordinator = coordinator

        // Seed sample data
        let ledger = Ledger(name: "预览账本", type: .family, context: ctx)

        CategorySeeder.seed(modelContext: ctx, ledger: ledger)

        // Sample accounts
        let cash = Account(name: "现金钱包", type: .cash, initialBalance: 5000, context: ctx)
        cash.ledger = ledger
        let debitCard = Account(name: "工资卡", type: .debitCard, initialBalance: 50000, context: ctx)
        debitCard.ledger = ledger
        let creditCard = Account(name: "招商信用卡", type: .creditCard, initialBalance: 0, creditLimit: 30000, context: ctx)
        creditCard.ledger = ledger
        let alipay = Account(name: "支付宝", type: .eWallet, initialBalance: 2000, context: ctx)
        alipay.ledger = ledger

        // Sample transactions
        let now = Date()
        let categories = (try? ctx.fetch(NSFetchRequest<Category>(entityName: "Category"))) ?? []

        let sampleTransactions: [(TransactionType, Decimal, Account, String)] = [
            (.income, 15000, debitCard, "本月工资"),
            (.expense, -3500, debitCard, "房租"),
            (.expense, -200, alipay, "午餐"),
            (.expense, -150, cash, "超市购物"),
            (.expense, -50, cash, "地铁通勤"),
            (.expense, -88, alipay, "电影票"),
            (.income, 500, alipay, "二手出售"),
            (.expense, -300, creditCard, "加油"),
        ]

        for (idx, (type, amount, account, note)) in sampleTransactions.enumerated() {
            let tx = Transaction(
                type: type,
                amount: amount,
                date: Calendar.current.date(byAdding: .day, value: -idx, to: now) ?? now,
                account: account,
                category: type == .income
                    ? categories.first(where: { $0.name == "工资" })
                    : categories[idx % categories.count],
                context: ctx
            )
            tx.note = note
            tx.ledger = ledger
        }

        try? ctx.save()
        return ctx
    }()
}
