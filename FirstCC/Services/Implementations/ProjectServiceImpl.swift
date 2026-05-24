import Foundation
@preconcurrency import CoreData

struct ProjectServiceImpl: ProjectServiceProtocol {
    func createProject(_ project: Project, ledger: Ledger, context: NSManagedObjectContext) throws {
        project.ledger = ledger
        try context.save()
    }

    func fetchProjects(for ledger: Ledger, context: NSManagedObjectContext) throws -> [Project] {
        let ledgerID = ledger.id
        let request = NSFetchRequest<Project>(entityName: "Project")
        request.predicate = NSPredicate(format: "ledger.id == %@", ledgerID as CVarArg)
        request.sortDescriptors = [NSSortDescriptor(key: "sortOrder", ascending: true), NSSortDescriptor(key: "name", ascending: true)]
        return try context.fetch(request)
    }

    func updateProject(_ project: Project, context: NSManagedObjectContext) throws {
        try context.save()
    }

    func deleteProject(_ project: Project, context: NSManagedObjectContext) throws {
        context.delete(project)
        try context.save()
    }
}
