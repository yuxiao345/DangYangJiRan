import SwiftUI
import PhotosUI
import PDFKit
import UniformTypeIdentifiers

struct OCRTestView: View {
    @Environment(AppContainer.self) private var appContainer

    /// If provided, CSV results can be sent to reconciliation
    let account: Account?

    @State private var selectedPhoto: PhotosPickerItem?
    @State private var image: UIImage?
    @State private var pdfData: Data?
    @State private var csvData: Data?
    @State private var pdfPageCount: Int = 0
    @State private var csvFileName: String = ""
    @State private var inputMode: InputMode = .csv
    @State private var showFileImporter = false

    @State private var isProcessing = false
    @State private var errorMessage: String?
    @State private var items: [BankTransactionItem] = []
    @State private var rawRows: [String] = []

    init(account: Account? = nil) {
        self.account = account
    }

    enum InputMode: String, CaseIterable {
        case csv = "CSV"
        case image = "图片"
        case pdf = "PDF"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Picker("来源", selection: $inputMode) {
                    ForEach(InputMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                sourceSection

                if hasInput {
                    Button(action: runOCR) {
                        HStack {
                            if isProcessing {
                                ProgressView()
                                    .tint(.white)
                            }
                            Text(isProcessing ? "识别中…" : "开始OCR识别")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .disabled(isProcessing)
                    .padding(.horizontal)
                }

                if let error = errorMessage {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.designBodySmall)
                        .padding(.horizontal)
                }

                if !items.isEmpty {
                    resultsSection
                }

                if !rawRows.isEmpty {
                    rawTextSection
                }
            }
            .padding(.vertical)
        }
        .navigationTitle("OCR 识别测试")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: {
            inputMode == .csv
                ? [.commaSeparatedText, .tabSeparatedText, UTType(filenameExtension: "csv") ?? .data]
                : [.pdf]
        }()) { result in
            switch result {
            case .success(let url):
                guard url.startAccessingSecurityScopedResource() else { return }
                defer { url.stopAccessingSecurityScopedResource() }
                let data = try? Data(contentsOf: url)
                if inputMode == .csv {
                    csvData = data
                    csvFileName = url.lastPathComponent
                    pdfData = nil
                } else {
                    pdfData = data
                    pdfPageCount = PDFDocument(data: data ?? Data())?.pageCount ?? 0
                    csvData = nil
                }
                image = nil
                selectedPhoto = nil
                clearResults()
            case .failure:
                break
            }
        }
        .onChange(of: selectedPhoto) { _, newValue in
            Task {
                if let data = try? await newValue?.loadTransferable(type: Data.self),
                   let img = UIImage(data: data) {
                    image = img
                    pdfData = nil
                    csvData = nil
                    clearResults()
                }
            }
        }
        .onChange(of: inputMode) { _, _ in
            image = nil
            selectedPhoto = nil
            pdfData = nil
            csvData = nil
            clearResults()
        }
    }

    private var hasInput: Bool {
        switch inputMode {
        case .image: return image != nil
        case .pdf: return pdfData != nil
        case .csv: return csvData != nil
        }
    }

    // MARK: - Source Section

    @ViewBuilder
    private var sourceSection: some View {
        switch inputMode {
        case .image:
            if let img = image {
                previewBox {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 300)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            } else {
                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    emptyPicker("选择银行账单截图", hint: "支持信用卡账单、银行App截图")
                }
            }
        case .pdf:
            if let _ = pdfData {
                previewBox {
                    VStack(spacing: 12) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 48))
                            .foregroundStyle(Color.designPrimaryContainer)
                        Text("PDF 已加载（\(pdfPageCount) 页）")
                            .font(.designHeadlineMedium)
                    }
                    .frame(height: 200)
                }
            } else {
                Button {
                    showFileImporter = true
                } label: {
                    emptyPicker("选择银行账单PDF", hint: "支持信用卡银行的电子账单PDF")
                }
            }
        case .csv:
            if let _ = csvData {
                previewBox {
                    VStack(spacing: 12) {
                        Image(systemName: "tablecells")
                            .font(.system(size: 48))
                            .foregroundStyle(.green)
                        Text("CSV 已加载")
                            .font(.designHeadlineMedium)
                        Text(csvFileName)
                            .font(.designBodySmall)
                            .foregroundStyle(.secondary)
                    }
                    .frame(height: 200)
                }
            } else {
                Button {
                    showFileImporter = true
                } label: {
                    emptyPicker("选择CSV文件", hint: "列格式：消费日期,记账日期,交易说明,交易类别,金额")
                }
            }
        }
    }

    @ViewBuilder
    private func previewBox(@ViewBuilder content: () -> some View) -> some View {
        content()
            .overlay(alignment: .topTrailing) {
                Button {
                    image = nil
                    selectedPhoto = nil
                    pdfData = nil
                    clearResults()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.white)
                        .shadow(radius: 2)
                }
                .padding(8)
            }
            .padding(.horizontal)
    }

    private func emptyPicker(_ title: String, hint: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: inputMode == .pdf ? "doc.text.viewfinder" : "doc.text.viewfinder")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(title)
                .foregroundStyle(.secondary)
            Text(hint)
                .font(.designBodySmall)
                .foregroundStyle(Color.designOnSurfaceVariant.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
        .frame(height: 200)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [6]))
                .foregroundStyle(.secondary.opacity(0.3))
        )
        .padding(.horizontal)
    }

    // MARK: - Results

    private var resultsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("识别结果（\(items.count) 笔）")
                .font(.designHeadlineMedium)
                .padding(.horizontal)

            ForEach(items.indices, id: \.self) { i in
                let item = items[i]
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        if let date = item.transDate {
                            Text(date, format: .dateTime.year().month(.twoDigits).day(.twoDigits))
                                .font(.designBodyMedium)
                                .fontWeight(.medium)
                        }
                        Spacer()
                        if let amount = item.amount {
                            Text(amount, format: .number.precision(.fractionLength(2)))
                                .font(.designBodyMedium)
                                .fontWeight(.bold)
                                .foregroundStyle(amount < 0 ? .red : .green)
                        }
                    }
                    if let desc = item.desc, !desc.isEmpty {
                        Text(desc)
                            .font(.designBodySmall)
                            .foregroundStyle(Color.designOnSurface)
                    }
                    if let raw = item.rawLine {
                        Text("OCR原文: \(raw)")
                            .font(.designBodySmall)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 6)
                Divider().padding(.horizontal)
            }
        }
    }

    private var rawTextSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("OCR原始行文本（\(rawRows.count) 行）")
                    .font(.designHeadlineMedium)
                Spacer()
                Button {
                    UIPasteboard.general.string = rawRows.joined(separator: "\n")
                } label: {
                    Label("复制", systemImage: "doc.on.doc")
                        .font(.designBodySmall)
                }
            }
            .padding(.horizontal)

            ForEach(rawRows.indices, id: \.self) { i in
                Text(rawRows[i])
                    .font(.designBodySmall)
                    .monospaced()
                    .padding(.horizontal)
                Divider().padding(.horizontal)
            }
        }
    }

    // MARK: - Actions

    private func clearResults() {
        items = []
        rawRows = []
        errorMessage = nil
    }

    private func runOCR() {
        isProcessing = true
        errorMessage = nil
        items = []
        rawRows = []

        let currentImage = image
        let currentPDFData = pdfData
        let currentCSVData = csvData

        Task {
            do {
                let result: [BankTransactionItem]
                if let csv = currentCSVData {
                    result = appContainer.bankOCRService.recognizeTransactions(fromCSV: csv)
                    if result.isEmpty {
                        errorMessage = "CSV解析失败，请检查文件格式"
                        isProcessing = false
                        return
                    }
                } else if let img = currentImage {
                    result = try await appContainer.bankOCRService.recognizeTransactions(from: img)
                } else if let pdf = currentPDFData {
                    result = try await appContainer.bankOCRService.recognizeTransactions(fromPDF: pdf)
                } else {
                    isProcessing = false
                    return
                }
                items = result
                rawRows = result.compactMap { $0.rawLine }
            } catch {
                errorMessage = error.localizedDescription
            }
            isProcessing = false
        }
    }
}
