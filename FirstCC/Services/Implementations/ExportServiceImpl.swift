import Foundation
import SwiftUI

struct ExportServiceImpl: ExportServiceProtocol {

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    // MARK: - CSV

    func exportToCSV(transactions: [Transaction]) throws -> URL {
        let header = "日期,类型,币种,金额,分类,账户,商户,备注,标签,成员,项目,分摊成员,分摊金额,分摊状态"
        let rows = transactions.flatMap { csvRows(for: $0) }
        let csv = ([header] + rows).joined(separator: "\n")
        return try writeToTempFile(data: csv.data(using: .utf8)!, prefix: "export_", suffix: ".csv")
    }

    private func csvRows(for t: Transaction) -> [String] {
        // Expand split parent — prefer SplitGroup entries, then fall back to child transactions
        if t.isSplitParent {
            if let entries = t.splitGroup?.entries, !entries.isEmpty {
                return entries.map { entry in
                    let fields: [String] = [
                        dateFormatter.string(from: t.date),
                        t.type.displayName,
                        t.currencyCode,
                        abs(entry.amount).description,
                        t.category?.name ?? "",
                        t.account?.name ?? "",
                        t.merchant?.name ?? "",
                        t.note ?? "",
                        t.tags.joined(separator: "/"),
                        t.member?.name ?? "",
                        t.project?.name ?? "",
                        entry.member?.name ?? "",
                        abs(entry.amount).description,
                        entry.isPaid ? "已付" : "未付",
                    ]
                    return fields.map(escapeCSV).joined(separator: ",")
                }
            }
            if let children = t.splitChildren, !children.isEmpty {
                return children.map { child in
                    let fields: [String] = [
                        dateFormatter.string(from: t.date),
                        t.type.displayName,
                        t.currencyCode,
                        abs(child.amount).description,
                        child.category?.name ?? "",
                        t.account?.name ?? "",
                        child.merchant?.name ?? "",
                        child.note ?? "",
                        child.tags.joined(separator: "/"),
                        child.member?.name ?? "",
                        child.project?.name ?? "",
                        "", "", "",
                    ]
                    return fields.map(escapeCSV).joined(separator: ",")
                }
            }
        }
        // Regular transaction
        let fields: [String] = [
            dateFormatter.string(from: t.date),
            t.type.displayName,
            t.currencyCode,
            exportAmount(t),
            t.category?.name ?? "",
            t.account?.name ?? "",
            t.merchant?.name ?? "",
            t.note ?? "",
            t.tags.joined(separator: "/"),
            t.member?.name ?? "",
            t.project?.name ?? "",
            "", "", "",
        ]
        return [fields.map(escapeCSV).joined(separator: ",")]
    }

    private func escapeCSV(_ field: String) -> String {
        if field.contains(",") || field.contains("\"") || field.contains("\n") {
            let escaped = field.replacing("\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return field
    }

    // MARK: - JSON

    func exportToJSON(transactions: [Transaction]) throws -> URL {
        let items = transactions.flatMap { tx -> [[String: Any]] in
            // Expand split parent — prefer SplitGroup entries, then fall back to child transactions
            if tx.isSplitParent {
                if let entries = tx.splitGroup?.entries, !entries.isEmpty {
                    return entries.map { entry in
                        var json = baseJSON(for: tx)
                        json["amount"] = abs(entry.amount).description
                        json["splitMember"] = entry.member?.name ?? ""
                        json["splitPaid"] = entry.isPaid
                        return json
                    }
                }
                if let children = tx.splitChildren, !children.isEmpty {
                    return children.map { child in
                        var json = baseJSON(for: tx)
                        json["amount"] = abs(child.amount).description
                        json["category"] = child.category?.name ?? ""
                        json["merchant"] = child.merchant?.name ?? ""
                        json["member"] = child.member?.name ?? ""
                        json["project"] = child.project?.name ?? ""
                        json["note"] = child.note ?? ""
                        json["splitMember"] = ""
                        json["splitPaid"] = false
                        return json
                    }
                }
            }
            var json = baseJSON(for: tx)
            json["splitMember"] = ""
            json["splitPaid"] = false
            return [json]
        }
        let data = try JSONSerialization.data(withJSONObject: items, options: .prettyPrinted)
        return try writeToTempFile(data: data, prefix: "export_", suffix: ".json")
    }

    private func baseJSON(for t: Transaction) -> [String: Any] {
        [
            "id": t.id.uuidString,
            "date": dateFormatter.string(from: t.date),
            "type": t.type.rawValue,
            "currency": t.currencyCode,
            "amount": exportAmount(t),
            "category": t.category?.name ?? "",
            "account": t.account?.name ?? "",
            "merchant": t.merchant?.name ?? "",
            "note": t.note ?? "",
            "tags": t.tags,
            "member": t.member?.name ?? "",
            "project": t.project?.name ?? "",
        ]
    }

    // MARK: - Share

    func shareURL(_ url: URL) {
        #if os(iOS)
        let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)

        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first,
              let root = window.rootViewController else { return }

        if let presented = root.presentedViewController {
            presented.present(activityVC, animated: true)
        } else {
            root.present(activityVC, animated: true)
        }
        #else
        // macOS: sharing handled via NSSavePanel in the view layer
        #endif
    }

    // MARK: - Helpers

    /// Refund transactions show negative to offset the original in exports
    private func exportAmount(_ t: Transaction) -> String {
        let value = abs(t.amount)
        return t.refundGroupId != nil ? "-\(value)" : value.description
    }

    private func writeToTempFile(data: Data, prefix: String, suffix: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
        let filename = "\(prefix)\(Date().timeIntervalSince1970)\(suffix)"
        let url = dir.appendingPathComponent(filename)
        try data.write(to: url)
        return url
    }
}
