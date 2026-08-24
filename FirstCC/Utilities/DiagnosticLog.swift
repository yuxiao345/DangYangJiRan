import Foundation

/// Writes diagnostic logs to a file in the app's Documents directory.
/// Use alongside Logger for capturing share-flow diagnostics.
/// In Release builds, only prints to console — no file on disk.
enum DiagnosticLog {
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

#if DEBUG
    private static var logFileURL: URL? {
        URL.documentsDirectory.appending(path: "sharing_diag.log")
    }
#endif

    static func log(_ message: String) {
        let timestamp = formatter.string(from: .now)
        print("[Diag] \(timestamp) \(message)")
#if DEBUG
        let line = "[\(timestamp)] \(message)\n"
        guard let url = logFileURL else { return }
        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: url.path) {
                if let fh = try? FileHandle(forWritingTo: url) {
                    fh.seekToEndOfFile()
                    fh.write(data)
                    try? fh.close()
                }
            } else {
                try? data.write(to: url, options: .atomic)
            }
        }
#endif
    }

#if DEBUG
    static func clear() {
        guard let url = logFileURL else { return }
        try? "".write(to: url, atomically: true, encoding: .utf8)
    }

    static func startSession(_ title: String) {
        clear()
        log("===== \(title) =====")
    }

    static func read() -> String {
        guard let url = logFileURL, FileManager.default.fileExists(atPath: url.path) else {
            return "(no diagnostic log)"
        }
        return (try? String(contentsOf: url, encoding: .utf8)) ?? "(unreadable)"
    }
#else
    static func clear() {}
    static func startSession(_ title: String) {}
    static func read() -> String { "" }
#endif
}
