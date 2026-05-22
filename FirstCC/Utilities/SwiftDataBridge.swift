import SwiftData
import CoreData

extension ModelContext {
    var coreDataContext: NSManagedObjectContext? {
        findNSManagedObjectContext(in: self)
    }
}

/// Recursively search for NSManagedObjectContext using Swift Mirror reflection.
/// ModelContext is a pure Swift object (not NSObject), so KVC does not work.
private func findNSManagedObjectContext(in object: Any, depth: Int = 0) -> NSManagedObjectContext? {
    guard depth < 5 else { return nil }

    if let context = object as? NSManagedObjectContext {
        return context
    }

    let mirror = Mirror(reflecting: object)
    for child in mirror.children {
        if let context = child.value as? NSManagedObjectContext {
            return context
        }
    }
    for child in mirror.children {
        if let found = findNSManagedObjectContext(in: child.value, depth: depth + 1) {
            return found
        }
    }
    return nil
}
