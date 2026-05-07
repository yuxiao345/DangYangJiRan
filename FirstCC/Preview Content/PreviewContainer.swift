import SwiftUI
import SwiftData

@MainActor
enum PreviewContainer {
    static let shared: ModelContainer = {
        let schema = Schema([
            Ledger.self, User.self, Account.self, Category.self,
            Transaction.self, TransactionTemplate.self, RecurringRule.self,
            SplitGroup.self, SplitEntry.self, BudgetBook.self, BudgetItem.self,
            InstallmentPlan.self,
            ExchangeRate.self
        ])

        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container: ModelContainer

        do {
            container = try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Preview container failed: \(error)")
        }

        // Seed sample data
        let context = container.mainContext
        let ledger = Ledger(name: "预览账本", type: .family)
        context.insert(ledger)

        CategorySeeder.seed(modelContext: context, ledger: ledger)

        // Sample accounts
        let cash = Account(name: "现金钱包", type: .cash, initialBalance: 5000)
        cash.ledger = ledger
        let debitCard = Account(name: "工资卡", type: .debitCard, initialBalance: 50000)
        debitCard.ledger = ledger
        let creditCard = Account(name: "招商信用卡", type: .creditCard, initialBalance: 0, creditLimit: 30000)
        creditCard.ledger = ledger
        let alipay = Account(name: "支付宝", type: .eWallet, initialBalance: 2000)
        alipay.ledger = ledger

        context.insert(cash)
        context.insert(debitCard)
        context.insert(creditCard)
        context.insert(alipay)

        // Sample transactions
        let now = Date()
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

        let categories = (try? context.fetch(FetchDescriptor<Category>())) ?? []
        for (idx, (type, amount, account, note)) in sampleTransactions.enumerated() {
            let tx = Transaction(
                type: type,
                amount: amount,
                date: Calendar.current.date(byAdding: .day, value: -idx, to: now) ?? now,
                account: account,
                category: type == .income
                    ? categories.first(where: { $0.name == "工资" })
                    : categories[idx % categories.count]
            )
            tx.note = note
            tx.ledger = ledger
            context.insert(tx)
        }

        try? context.save()
        return container
    }()
}
