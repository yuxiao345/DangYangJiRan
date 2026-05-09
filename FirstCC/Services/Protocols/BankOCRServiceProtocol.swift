import UIKit

protocol BankOCRServiceProtocol {
    /// Run OCR on a UIImage (screenshot, photo) to extract bank transaction line items
    func recognizeTransactions(from image: UIImage) async throws -> [BankTransactionItem]

    /// Run OCR on a PDF document to extract bank transaction line items from all pages
    func recognizeTransactions(fromPDF data: Data) async throws -> [BankTransactionItem]

    /// Parse CSV/Excel data with columns: 消费日期, 记账日期, 交易说明, 交易类别, 金额
    func recognizeTransactions(fromCSV data: Data) -> [BankTransactionItem]
}
