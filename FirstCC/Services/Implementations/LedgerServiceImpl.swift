import Foundation
@preconcurrency import CoreData

struct LedgerServiceImpl: LedgerServiceProtocol {
    func createLedger(name: String, type: LedgerType, currencyCode: String, context: NSManagedObjectContext) throws -> Ledger {
        let ledger = Ledger(name: name, type: type, defaultCurrencyCode: currencyCode, context: context)
        try context.save()
        return ledger
    }

    func fetchLedgers(context: NSManagedObjectContext) throws -> [Ledger] {
        let request = NSFetchRequest<Ledger>(entityName: "Ledger")
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        return try context.fetch(request)
    }

    func updateLedger(_ ledger: Ledger, context: NSManagedObjectContext) throws {
        try context.save()
    }

    func deleteLedger(_ ledger: Ledger, context: NSManagedObjectContext) throws {
        // Manual cascade: CloudKit mirroring can interfere with CoreData cascade rules.
        // Delete L2 children first (grandchildren), then L1, then ledger — all in one
        // pass per relationship to avoid double fault resolution.

        // Collect per relationship: grandchildren first, then the direct children
        var toDelete: [NSManagedObject] = []

        if let accounts = ledger.accounts {
            for a in accounts {
                if let stmts = a.creditCardStatements { toDelete.append(contentsOf: stmts) }
            }
            toDelete.append(contentsOf: accounts)
        }
        if let transactions = ledger.transactions {
            for tx in transactions {
                if let children = tx.splitChildren { toDelete.append(contentsOf: children) }
            }
            toDelete.append(contentsOf: transactions)
        }
        if let templates = ledger.templates {
            for t in templates {
                if let rule = t.recurringRule { toDelete.append(rule) }
            }
            toDelete.append(contentsOf: templates)
        }
        if let categories = ledger.categories {
            toDelete.append(contentsOf: flattenCategories(categories).reversed())
        }
        if let budgetBooks = ledger.budgetBooks {
            for b in budgetBooks {
                if let items = b.items { toDelete.append(contentsOf: items) }
            }
            toDelete.append(contentsOf: budgetBooks)
        }
        if let splitGroups = ledger.splitGroups {
            for g in splitGroups {
                if let entries = g.entries { toDelete.append(contentsOf: entries) }
            }
            toDelete.append(contentsOf: splitGroups)
        }

        if let members = ledger.members { toDelete.append(contentsOf: members) }
        if let creditCardStatements = ledger.creditCardStatements { toDelete.append(contentsOf: creditCardStatements) }
        if let memberContacts = ledger.memberContacts { toDelete.append(contentsOf: memberContacts) }
        if let merchants = ledger.merchants { toDelete.append(contentsOf: merchants) }
        if let projects = ledger.projects { toDelete.append(contentsOf: projects) }

        for obj in toDelete { context.delete(obj) }
        context.delete(ledger)

        do {
            try context.save()
            DiagnosticLog.log("LedgerService: deleted ledger \(ledger.name) with manual cascade")
        } catch {
            DiagnosticLog.log("LedgerService: delete FAILED \(error.localizedDescription)")
            throw error
        }
    }

    func switchToLedger(_ ledger: Ledger) {
        // Handled by AppContainer
    }
}

