import Foundation

enum CSVStorage {
    static func save(_ data: Data, statementId: UUID) -> String {
        let dir = documentsDir.appendingPathComponent("CSVData/\(statementId.uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let filename = "data.csv"
        try? data.write(to: dir.appendingPathComponent(filename))
        return "\(statementId.uuidString)/\(filename)"
    }

    static func load(path: String) -> Data? {
        try? Data(contentsOf: documentsDir.appendingPathComponent("CSVData/\(path)"))
    }

    static func delete(path: String) {
        try? FileManager.default.removeItem(
            at: documentsDir.appendingPathComponent("CSVData/\(path)")
        )
        let dirPath = documentsDir.appendingPathComponent(
            "CSVData/\(path.split(separator: "/").first ?? "")"
        )
        try? FileManager.default.removeItem(at: dirPath)
    }

    private static var documentsDir: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
}
