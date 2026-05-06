import Foundation
import SwiftData

protocol ProjectServiceProtocol {
    func createProject(_ project: Project, ledger: Ledger, context: ModelContext) throws
    func fetchProjects(for ledger: Ledger, context: ModelContext) throws -> [Project]
    func updateProject(_ project: Project, context: ModelContext) throws
    func deleteProject(_ project: Project, context: ModelContext) throws
}
