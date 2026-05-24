import Foundation
@preconcurrency import CoreData

struct MemberServiceImpl: MemberServiceProtocol {
    func createMember(_ member: Member, ledger: Ledger, context: NSManagedObjectContext) throws {
        member.ledger = ledger
        try context.save()
    }

    func fetchMembers(for ledger: Ledger, context: NSManagedObjectContext) throws -> [Member] {
        let ledgerID = ledger.id
        let request = NSFetchRequest<Member>(entityName: "Member")
        request.predicate = NSPredicate(format: "ledger.id == %@", ledgerID as CVarArg)
        request.sortDescriptors = [NSSortDescriptor(key: "sortOrder", ascending: true), NSSortDescriptor(key: "name", ascending: true)]
        return try context.fetch(request)
    }

    func updateMember(_ member: Member, context: NSManagedObjectContext) throws {
        try context.save()
    }

    func deleteMember(_ member: Member, context: NSManagedObjectContext) throws {
        context.delete(member)
        try context.save()
    }
}
