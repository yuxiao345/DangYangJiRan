import UIKit
import Vision
import PDFKit

final class BankOCRServiceImpl: BankOCRServiceProtocol {

    func recognizeTransactions(from image: UIImage) async throws -> [BankTransactionItem] {
        guard let cgImage = image.cgImage else {
            throw BankOCRError.invalidImage
        }
        return try await recognizeFromCGImage(cgImage)
    }

    func recognizeTransactions(fromPDF data: Data) async throws -> [BankTransactionItem] {
        guard let pdfDoc = PDFDocument(data: data) else {
            throw BankOCRError.invalidPDF
        }

        var allItems: [BankTransactionItem] = []
        var sortOffset = 0

        for pageIndex in 0..<pdfDoc.pageCount {
            guard let page = pdfDoc.page(at: pageIndex) else { continue }

            let pageRect = page.bounds(for: .mediaBox)
            let renderer = UIGraphicsImageRenderer(size: pageRect.size)
            let pageImage = renderer.image { ctx in
                UIColor.white.setFill()
                ctx.fill(pageRect)
                ctx.cgContext.translateBy(x: 0, y: pageRect.height)
                ctx.cgContext.scaleBy(x: 1.0, y: -1.0)
                page.draw(with: .mediaBox, to: ctx.cgContext)
            }

            guard let cgImage = pageImage.cgImage else { continue }

            do {
                let items = try await recognizeFromCGImage(cgImage, sortOffset: sortOffset)
                allItems.append(contentsOf: items)
                sortOffset += items.count
            } catch {
                // Skip pages with no recognizable transactions
            }
        }

        if allItems.isEmpty {
            throw BankOCRError.noTransactionsFound
        }

        return allItems
    }

    // MARK: - CSV Import

    func recognizeTransactions(fromCSV data: Data) -> [BankTransactionItem] {
        // Try UTF-8 first, then GB18030 for Chinese bank CSVs
        let gb18030 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
        guard let content = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: gb18030)
        else { return [] }

        let lines = content.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        guard lines.count >= 2 else { return [] }

        // Detect delimiter: comma or tab
        let delimiter = detectDelimiter(lines[0])

        // Parse header
        let headers = parseCSVLine(lines[0], delimiter: delimiter)
        guard !headers.isEmpty else { return [] }

        // Find column indices
        let dateIdx = headers.firstIndex(where: { $0.contains("消费日期") || $0.contains("交易日期") })
        let descIdx = headers.firstIndex(where: { $0.contains("交易说明") || $0.contains("说明") || $0.contains("描述") })
        let amountIdx = headers.firstIndex(where: { $0.contains("金额") })
        // Optional: 记账日期, 交易类别
        let postDateIdx = headers.firstIndex(where: { $0.contains("记账日期") })
        let categoryIdx = headers.firstIndex(where: { $0.contains("交易类别") || $0.contains("类别") })

        // Require at least date + amount
        guard dateIdx != nil || amountIdx != nil else { return [] }

        var items: [BankTransactionItem] = []

        for line in lines.dropFirst() {
            let fields = parseCSVLine(line, delimiter: delimiter)
            if fields.isEmpty || fields.allSatisfy({ $0.isEmpty }) { continue }

            let rawDate = dateIdx.flatMap { idx in idx < fields.count ? fields[idx] : nil } ?? ""
            let rawAmount = amountIdx.flatMap { idx in idx < fields.count ? fields[idx] : nil } ?? ""
            let desc = descIdx.flatMap { idx in idx < fields.count ? fields[idx] : nil }
            let postDateStr = postDateIdx.flatMap { idx in idx < fields.count ? fields[idx] : nil }
            let category = categoryIdx.flatMap { idx in idx < fields.count ? fields[idx] : nil }

            // Parse date
            let date = parseCSVDate(rawDate)

            // Skip summary row — check entire line for summary keywords
            let skipKeywords = ["合计", "总计", "汇总", "小计"]
            if skipKeywords.contains(where: { line.contains($0) }) { continue }

            // Parse amount
            guard let amount = parseCSVAmount(rawAmount) else { continue }

            // Build description with optional category
            var fullDesc = desc ?? ""
            if let cat = category?.trimmingCharacters(in: .whitespaces), !cat.isEmpty {
                fullDesc = fullDesc.isEmpty ? cat : "\(fullDesc)（\(cat)）"
            }

            // Prefer posting date if available, otherwise transaction date
            let effectiveDate: Date?
            if let pds = postDateStr, let pd = parseCSVDate(pds) {
                effectiveDate = pd
            } else {
                effectiveDate = date
            }

            let item = BankTransactionItem(
                transDate: effectiveDate,
                amount: amount,
                desc: fullDesc.isEmpty ? nil : fullDesc,
                rawLine: line,
                matchStatus: .unmatched,
                sortOrder: items.count
            )
            items.append(item)
        }

        return items
    }

    private func detectDelimiter(_ line: String) -> Character {
        let commas = line.filter { $0 == "," }.count
        let tabs = line.filter { $0 == "\t" }.count
        return tabs > commas ? "\t" : ","
    }

    private func parseCSVLine(_ line: String, delimiter: Character) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false

        for char in line {
            if char == "\"" {
                inQuotes.toggle()
            } else if char == delimiter && !inQuotes {
                fields.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                current.append(char)
            }
        }
        fields.append(current.trimmingCharacters(in: .whitespaces))
        return fields
    }

    private func parseCSVDate(_ raw: String) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        let patterns = [
            (#"(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})"#, true),   // 2025/05/07 or 2025-05-07
            (#"(\d{4})年(\d{1,2})月(\d{1,2})日"#, true),         // 2025年05月07日
            (#"(\d{1,2})[-/.](\d{1,2})"#, false),                // 05/07 (MM/DD)
            (#"(\d{4})(\d{2})(\d{2})"#, true),                    // 20250507 (YYYYMMDD)
        ]

        for (pattern, hasYear) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(trimmed.startIndex..., in: trimmed)
            guard let match = regex.firstMatch(in: trimmed, range: range) else { continue }

            if hasYear && match.numberOfRanges >= 4 {
                guard let yR = Range(match.range(at: 1), in: trimmed),
                      let mR = Range(match.range(at: 2), in: trimmed),
                      let dR = Range(match.range(at: 3), in: trimmed),
                      let y = Int(trimmed[yR]), let m = Int(trimmed[mR]), let d = Int(trimmed[dR]),
                      (1...12).contains(m), (1...31).contains(d) else { continue }
                var comps = DateComponents(year: y, month: m, day: d)
                comps.hour = 12
                return Calendar.current.date(from: comps)
            }

            if !hasYear && match.numberOfRanges >= 3 {
                guard let mR = Range(match.range(at: 1), in: trimmed),
                      let dR = Range(match.range(at: 2), in: trimmed),
                      let m = Int(trimmed[mR]), let d = Int(trimmed[dR]),
                      (1...12).contains(m), (1...31).contains(d) else { continue }
                let currentYear = Calendar.current.component(.year, from: Date())
                var comps = DateComponents(year: currentYear, month: m, day: d)
                comps.hour = 12
                return Calendar.current.date(from: comps)
            }
        }

        return nil
    }

    private func parseCSVAmount(_ raw: String) -> Decimal? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "¥", with: "")
            .replacingOccurrences(of: "￥", with: "")
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: " ", with: "")

        guard let value = Decimal(string: trimmed), value != 0 else { return nil }

        // Bank statements list debits as positive; convert to negative for expense convention
        return value > 0 ? -value : value
    }

    // MARK: - Core OCR Pipeline

    private func recognizeFromCGImage(_ cgImage: CGImage, sortOffset: Int = 0) async throws -> [BankTransactionItem] {
        let observations = try await performOCR(on: cgImage)
        let rows = groupObservationsIntoRows(observations)
        let items = parseTransactionRows(rows, sortOffset: sortOffset)

        if items.isEmpty {
            throw BankOCRError.noTransactionsFound
        }

        return items
    }

    // MARK: - Vision OCR

    private func performOCR(on cgImage: CGImage) async throws -> [VNRecognizedTextObservation] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["zh-Hans", "en-US"]
        request.usesLanguageCorrection = false

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])

        guard let results = request.results else {
            throw BankOCRError.noTextFound
        }

        return results
    }

    // MARK: - Spatial Row Grouping

    private func groupObservationsIntoRows(_ observations: [VNRecognizedTextObservation]) -> [String] {
        let sorted = observations.sorted { $0.boundingBox.midY > $1.boundingBox.midY }

        guard !sorted.isEmpty else { return [] }

        let avgHeight = sorted.map { $0.boundingBox.height }.reduce(0, +) / CGFloat(sorted.count)
        let rowThreshold = avgHeight * 0.5

        var rows: [[VNRecognizedTextObservation]] = []
        var currentRow: [VNRecognizedTextObservation] = [sorted[0]]
        var lastY = sorted[0].boundingBox.midY

        for obs in sorted.dropFirst() {
            let dy = abs(obs.boundingBox.midY - lastY)
            if dy < rowThreshold {
                currentRow.append(obs)
            } else {
                rows.append(currentRow)
                currentRow = [obs]
            }
            lastY = obs.boundingBox.midY
        }
        rows.append(currentRow)

        return rows.map { row in
            row.sorted { $0.boundingBox.midX < $1.boundingBox.midX }
                .compactMap { $0.topCandidates(1).first?.string }
                .joined(separator: " ")
        }
    }

    // MARK: - Transaction Parsing

    /// Keywords that indicate a header/info line rather than a transaction
    private let skipKeywords = ["发送", "收件人", "主题", "账单周期", "您好", "尊敬的", "信用卡", "对账单",
                                 "Statement", "From:", "To:", "Subject:", "Date:", "Page"]

    private func parseTransactionRows(_ rows: [String], sortOffset: Int = 0) -> [BankTransactionItem] {
        var items: [BankTransactionItem] = []

        // Skip the first few rows (typically headers) until we find a real transaction
        var headerSkipped = false
        let headerSkipCount = min(3, rows.count)

        for (index, row) in rows.enumerated() {
            // Skip header rows
            if index < headerSkipCount && !headerSkipped {
                if row.contains("交易") || row.contains("消费") || row.contains("支出") {
                    headerSkipped = true // Found the column header row, next rows are data
                }
                continue
            }

            // Skip non-transaction rows
            if shouldSkipRow(row) { continue }

            guard let item = parseRow(row, sortOrder: sortOffset + items.count) else { continue }
            items.append(item)
        }

        return items
    }

    private func shouldSkipRow(_ row: String) -> Bool {
        let lower = row.lowercased()
        for kw in skipKeywords {
            if lower.contains(kw.lowercased()) { return true }
        }
        // Skip rows that look like email headers (time pattern like "17:34")
        if row.contains(#/\d{1,2}:\d{2}/#) { return true }
        // Skip rows too short to be a transaction
        if row.count < 10 { return true }
        return false
    }

    private func parseRow(_ row: String, sortOrder: Int) -> BankTransactionItem? {
        guard let date = extractDate(from: row) else { return nil }
        guard let (amount, parsedAmountStr) = extractAmount(from: row) else { return nil }

        // Verify the amount is at the end of the row (bank statement convention)
        guard isAmountAtRowEnd(row, amountStr: parsedAmountStr) else { return nil }

        // Clean description
        var desc = row
        // Remove all date patterns
        let datePatterns = [
            #"\d{4}年\d{1,2}月\d{1,2}日"#,
            #"\d{4}[-/.]\d{1,2}[-/.]\d{1,2}"#,
            #"\b(?:20\d{2})(?:0[1-9]|1[0-2])(?:0[1-9]|[12]\d|3[01])\b"#, // YYYYMMDD
            #"\b(?:0[1-9]|1[0-2])(?:0[1-9]|[12]\d|3[01])\b"#, // MMDD
        ]
        for pattern in datePatterns {
            guard let dateRegex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(desc.startIndex..., in: desc)
            for match in dateRegex.matches(in: desc, range: range).reversed() {
                if let r = Range(match.range, in: desc) { desc.removeSubrange(r) }
            }
        }
        // Remove the parsed amount string
        if let range = desc.range(of: parsedAmountStr) {
            desc.removeSubrange(range)
        }
        // Remove leading row number / index
        desc = desc.replacingOccurrences(of: #"^\s*\d{1,3}\s+"#, with: "", options: .regularExpression)
        // Remove leftover ¥/￥ symbols
        desc = desc.replacingOccurrences(of: "¥", with: "")
        desc = desc.replacingOccurrences(of: "￥", with: "")
        desc = desc.trimmingCharacters(in: .whitespaces)

        return BankTransactionItem(
            transDate: date,
            amount: amount,
            desc: desc.isEmpty ? nil : desc,
            rawLine: row,
            sortOrder: sortOrder
        )
    }

    /// Check that the amount appears near the end of the row
    private func isAmountAtRowEnd(_ row: String, amountStr: String) -> Bool {
        guard let range = row.range(of: amountStr, options: .backwards) else { return false }
        let afterAmount = row[range.upperBound...].trimmingCharacters(in: .whitespaces)
        return afterAmount.count <= 3 // Allow trailing spaces, "元", etc.
    }

    // MARK: - Date Extraction

    private func extractDate(from text: String) -> Date? {
        let patterns: [(String, Bool)] = [
            // 2025年05月07日
            (#"(\d{4})年(\d{1,2})月(\d{1,2})日"#, true),
            // 2025/05/07 or 2025-05-07 or 2025.05.07
            (#"(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})"#, true),
            // 05/07 or 05-07 (month-day, infer year)
            (#"(?<!\d)(\d{1,2})[-/.](\d{1,2})(?!\d)"#, false),
            // 0507 (MMDD, 4 digits, infer year)
            (#"(?<!\d)(0[1-9]|1[0-2])(0[1-9]|[12]\d|3[01])(?!\d)"#, false),
            // 20250507 (YYYYMMDD, 8 digits)
            (#"(\d{4})(0[1-9]|1[0-2])(0[1-9]|[12]\d|3[01])"#, true),
        ]

        for (pattern, hasYear) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            // Pick the first match
            guard let match = matches.first else { continue }

            if hasYear && match.numberOfRanges >= 4 {
                guard let yRange = Range(match.range(at: 1), in: text),
                      let mRange = Range(match.range(at: 2), in: text),
                      let dRange = Range(match.range(at: 3), in: text),
                      let y = Int(text[yRange]), let m = Int(text[mRange]), let d = Int(text[dRange]),
                      (1...12).contains(m), (1...31).contains(d) else { continue }
                var comps = DateComponents(year: y, month: m, day: d)
                comps.hour = 12
                return Calendar.current.date(from: comps)
            }

            if !hasYear && match.numberOfRanges >= 3 {
                guard let mRange = Range(match.range(at: 1), in: text),
                      let dRange = Range(match.range(at: 2), in: text),
                      let m = Int(text[mRange]), let d = Int(text[dRange]),
                      (1...12).contains(m), (1...31).contains(d) else { continue }
                let currentYear = Calendar.current.component(.year, from: Date())
                var comps = DateComponents(year: currentYear, month: m, day: d)
                comps.hour = 12
                return Calendar.current.date(from: comps)
            }
        }

        return nil
    }

    // MARK: - Amount Extraction

    /// Returns (amount, matchedString). Amount is negative for debits/outflows.
    private func extractAmount(from text: String) -> (Decimal, String)? {
        let pattern = #"(?:¥|￥|CNY|USD|EUR)?\s*([-+])?\s*([\d,]+\.?\d{0,2})"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }

        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        // Take the last match — amounts appear at the end of bank statement rows
        guard let match = matches.last,
              let fullRange = Range(match.range, in: text),
              let numRange = Range(match.range(at: 2), in: text) else { return nil }

        let fullMatchStr = String(text[fullRange])
        var numStr = String(text[numRange]).replacingOccurrences(of: ",", with: "")

        let hasSign = match.range(at: 1).location != NSNotFound
        var isNegative = false
        if hasSign, let signRange = Range(match.range(at: 1), in: text) {
            isNegative = text[signRange] == "-"
        }

        guard let value = Decimal(string: numStr), value != 0 else { return nil }

        // Require currency prefix or value >= 1.0 to avoid picking up times, row numbers, etc.
        let hasCurrencyPrefix = fullMatchStr.contains("￥") || fullMatchStr.contains("¥")
            || fullMatchStr.contains("CNY") || fullMatchStr.contains("USD")
        if !hasCurrencyPrefix && abs(NSDecimalNumber(decimal: value).doubleValue) < 1.0 {
            return nil
        }

        // Credit card statement amounts default to debit (negative)
        if !isNegative {
            let contextEnd = min(text.count, match.range.location + match.range.length + 6)
            let contextStart = max(0, match.range.location - 6)
            let nearby = String(text[text.index(text.startIndex, offsetBy: contextStart)..<text.index(text.startIndex, offsetBy: contextEnd)])
            if nearby.contains("存入") || nearby.contains("收入") || nearby.contains("退款") || nearby.contains("退货") {
                // Keep positive
            } else {
                isNegative = true
            }
        }

        return (isNegative ? -value : value, fullMatchStr)
    }
}

enum BankOCRError: LocalizedError {
    case invalidImage
    case invalidPDF
    case noTextFound
    case noTransactionsFound

    var errorDescription: String? {
        switch self {
        case .invalidImage: return "无法读取图片"
        case .invalidPDF: return "无法读取PDF文件"
        case .noTextFound: return "图片中未识别到文字，请确保截图清晰"
        case .noTransactionsFound: return "未识别到银行交易明细，请确保截图中包含交易列表"
        }
    }
}
