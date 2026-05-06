import Foundation
import SwiftData

protocol MemberServiceProtocol {
    func createMember(_ member: Member, ledger: Ledger, context: ModelContext) throws
    func fetchMembers(for ledger: Ledger, context: ModelContext) throws -> [Member]
    func updateMember(_ member: Member, context: ModelContext) throws
    func deleteMember(_ member: Member, context: ModelContext) throws
}
