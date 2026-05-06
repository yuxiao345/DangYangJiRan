import Foundation
import SwiftData

struct ProjectServiceImpl: ProjectServiceProtocol {
    func createProject(_ project: Project, ledger: Ledger, context: ModelContext) throws {
        project.ledger = ledger
        context.insert(project)
        try context.save()
    }

    func fetchProjects(for ledger: Ledger, context: ModelContext) throws -> [Project] {
        let ledgerID = ledger.id
        let descriptor = FetchDescriptor<Project>(
            predicate: #Predicate { $0.ledger?.id == ledgerID },
            sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.name)]
        )
        return try context.fetch(descriptor)
    }

    func updateProject(_ project: Project, context: ModelContext) throws {
        try context.save()
    }

    func deleteProject(_ project: Project, context: ModelContext) throws {
        context.delete(project)
        try context.save()
    }
}
