import Foundation
@preconcurrency import CoreData

protocol ProjectServiceProtocol {
    func createProject(_ project: Project, ledger: Ledger, context: NSManagedObjectContext) throws
    func fetchProjects(for ledger: Ledger, context: NSManagedObjectContext) throws -> [Project]
    func updateProject(_ project: Project, context: NSManagedObjectContext) throws
    func deleteProject(_ project: Project, context: NSManagedObjectContext) throws
}
