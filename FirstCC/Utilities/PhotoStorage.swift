import Foundation

enum PhotoStorage {
    static func save(_ dataList: [Data], transactionId: UUID) -> [String] {
        let dir = documentsDir.appendingPathComponent("TransactionPhotos/\(transactionId.uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var paths: [String] = []
        for (index, data) in dataList.enumerated() {
            let filename = "\(index).jpg"
            try? data.write(to: dir.appendingPathComponent(filename))
            paths.append("\(transactionId.uuidString)/\(filename)")
        }
        return paths
    }

    static func load(paths: [String]) -> [Data] {
        paths.compactMap {
            try? Data(contentsOf: documentsDir.appendingPathComponent("TransactionPhotos/\($0)"))
        }
    }

    static func delete(paths: [String]) {
        for path in paths {
            try? FileManager.default.removeItem(
                at: documentsDir.appendingPathComponent("TransactionPhotos/\(path)")
            )
        }
        if let first = paths.first {
            let dirPath = documentsDir.appendingPathComponent(
                "TransactionPhotos/\(first.split(separator: "/").first ?? "")"
            )
            try? FileManager.default.removeItem(at: dirPath)
        }
    }

    private static var documentsDir: URL {
        URL.documentsDirectory
    }
}
