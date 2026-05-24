import Foundation
@preconcurrency import CoreData

protocol MemberServiceProtocol {
    func createMember(_ member: Member, ledger: Ledger, context: NSManagedObjectContext) throws
    func fetchMembers(for ledger: Ledger, context: NSManagedObjectContext) throws -> [Member]
    func updateMember(_ member: Member, context: NSManagedObjectContext) throws
    func deleteMember(_ member: Member, context: NSManagedObjectContext) throws
}
