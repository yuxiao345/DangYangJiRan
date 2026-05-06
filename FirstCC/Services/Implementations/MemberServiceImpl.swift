import Foundation
import SwiftData

struct MemberServiceImpl: MemberServiceProtocol {
    func createMember(_ member: Member, ledger: Ledger, context: ModelContext) throws {
        member.ledger = ledger
        context.insert(member)
        try context.save()
    }

    func fetchMembers(for ledger: Ledger, context: ModelContext) throws -> [Member] {
        let ledgerID = ledger.id
        let descriptor = FetchDescriptor<Member>(
            predicate: #Predicate { $0.ledger?.id == ledgerID },
            sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.name)]
        )
        return try context.fetch(descriptor)
    }

    func updateMember(_ member: Member, context: ModelContext) throws {
        try context.save()
    }

    func deleteMember(_ member: Member, context: ModelContext) throws {
        context.delete(member)
        try context.save()
    }
}
