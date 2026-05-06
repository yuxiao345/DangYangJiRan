import Foundation

protocol ExportServiceProtocol {
    func exportToCSV(transactions: [Transaction]) throws -> URL
    func exportToJSON(transactions: [Transaction]) throws -> URL
    func shareURL(_ url: URL)
}
