import Foundation
import os

enum Logger {
    static let main = OSLog(
        subsystem: Constants.bundleIdentifier,
        category: "main"
    )

    static let sync = OSLog(
        subsystem: Constants.bundleIdentifier,
        category: "sync"
    )

    static let data = OSLog(
        subsystem: Constants.bundleIdentifier,
        category: "data"
    )

    static func debug(_ message: String, log: OSLog = main) {
        os_log(.debug, log: log, "%{public}@", message)
    }

    static func error(_ message: String, log: OSLog = main) {
        os_log(.error, log: log, "%{public}@", message)
    }

    static func info(_ message: String, log: OSLog = main) {
        os_log(.info, log: log, "%{public}@", message)
    }
}
