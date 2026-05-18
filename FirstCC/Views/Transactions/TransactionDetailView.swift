import SwiftUI
import SwiftData

struct TransactionDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appContainer: AppContainer

    let transaction: Transaction
    @State private var showEditSheet = false
    @State private var showDeleteAlert = false
    @State private var showSplitForm = false
    @State private var showRefundSheet = false
    @State private var photoDataList: [Data] = []
    @State private var selectedPhotoItem: PhotoItem?
    @State private var linkedRefunds: [Transaction] = []
    @State private var settledExpenses: [Transaction] = []
    @State private var settledLendingTransactions: [Transaction] = []

    var body: some View {
        List {
            Section {
                HStack(spacing: 12) {
                    Image(systemName: transaction.lendingDirection?.systemIcon ?? transaction.category?.iconName ?? transaction.type.systemIcon)
                        .font(.largeTitle)
                        .foregroundStyle(iconColor)
                        .frame(width: 44)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(LocalizedStringKey(titleText))
                            .font(.title3)
                        Text(LocalizedStringKey(subtitleText))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    amountView
                }
            }

            Section("账户") {
                if transaction.type == .transfer || transaction.type == .lending {
                    LabeledContent("转出") {
                        Text(LocalizedStringKey(transaction.account?.name ?? "—"))
                    }
                    LabeledContent("转入") {
                        Text(LocalizedStringKey(transaction.toAccount?.name ?? "—"))
                    }
                } else {
                    LabeledContent("账户") {
                        Text(LocalizedStringKey(transaction.account?.name ?? "—"))
                    }
                }
            }

            if transaction.type != .transfer && transaction.type != .lending, let category = transaction.category {
                Section("分类") {
                    Label(LocalizedStringKey(category.name), systemImage: category.iconName)
                        .foregroundStyle(Color(hex: category.colorHex))
                }
            }

            if transaction.type != .transfer && transaction.type != .lending {
                Section("更多信息") {
                    if let member = transaction.member {
                        LabeledContent("成员") { Text(LocalizedStringKey(member.name)) }
                    }
                    if let merchant = transaction.merchant {
                        LabeledContent("商家") { Text(LocalizedStringKey(merchant.name)) }
                    }
                    if let project = transaction.project {
                        LabeledContent("项目") { Text(LocalizedStringKey(project.name)) }
                    }
                }
            }

            if transaction.hasSplitChildren, let children = transaction.splitChildren {
                Section {
                    ForEach(children) { child in
                        HStack {
                            if let cat = child.category {
                                Image(systemName: cat.iconName)
                                    .foregroundStyle(Color(hex: cat.colorHex))
                                    .frame(width: 24)
                                Text(LocalizedStringKey(cat.name))
                                    .font(.body)
                            } else {
                                Image(systemName: "questionmark.circle")
                                    .foregroundStyle(.secondary)
                                    .frame(width: 24)
                                Text("未分类")
                                    .font(.body)
                                    .foregroundStyle(.secondary)
                            }
                            if let m = child.member {
                                Text(m.name)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            CurrencyText(amount: abs(child.amount), currencyCode: child.currencyCode, font: .body, foregroundColor: .red)
                        }
                    }
                } header: {
                    HStack {
                        Label("拆分明细", systemImage: "rectangle.split.2x2")
                        Spacer()
                        Text("共\(children.count)项")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let group = transaction.splitGroup {
                Section {
                    NavigationLink {
                        SplitDetailView(splitGroup: group)
                    } label: {
                        HStack {
                            Label("成员分摊", systemImage: "person.2.circle")
                            Spacer()
                            Text(group.settlementStatus.displayName)
                                .font(.caption)
                                .foregroundStyle(group.settlementStatus == .settled ? .green : .orange)
                        }
                    }
                } header: {
                    Text("成员分摊")
                }
            } else if transaction.type == .expense
                        && !transaction.isSplitParent
                        && !transaction.hasSplitChildren {
                Section {
                    Button {
                        showSplitForm = true
                    } label: {
                        Label("创建成员分摊", systemImage: "person.2.badge.plus")
                    }
                } header: {
                    Text("成员分摊")
                }
            }

            if transaction.refundGroupId != nil {
                Section("退款关联") {
                    LabeledContent("原交易退款") {
                        Text("已关联")
                            .foregroundStyle(.blue)
                    }
                }
            }

            if !linkedRefunds.isEmpty {
                Section("已退款") {
                    ForEach(linkedRefunds) { refund in
                        HStack {
                            LabeledContent("退款金额") {
                                CurrencyText(amount: abs(refund.amount), currencyCode: refund.currencyCode, font: .body, foregroundColor: .green)
                            }
                            Text(refund.date.formatted(date: .abbreviated, time: .omitted))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if transaction.isReimbursable {
                Section {
                    LabeledContent("报销状态") {
                        switch transaction.reimbursementStatus {
                        case .pending:
                            Text(ReimbursementStatus.pending.displayName).foregroundStyle(.orange)
                        case .reimbursed:
                            Text(ReimbursementStatus.reimbursed.displayName).foregroundStyle(.green)
                        default:
                            Text("—").foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if !settledExpenses.isEmpty {
                Section("报销结算") {
                    ForEach(settledExpenses) { expense in
                        HStack {
                            Text(LocalizedStringKey(expense.category?.name ?? ""))
                                .font(.body)
                            Spacer()
                            CurrencyText(amount: abs(expense.amount), currencyCode: expense.currencyCode, font: .body)
                        }
                    }
                }
            }

            if transaction.isLending {
                Section {
                    LabeledContent("借贷状态") {
                        switch transaction.lendingStatus {
                        case .pending:
                            if let d = transaction.lendingDirection {
                                Text(LocalizedStringKey(d.pendingLabel)).foregroundStyle(.orange)
                            }
                        case .settled:
                            Text(LendingStatus.settled.displayName).foregroundStyle(.green)
                        case .none:
                            Text("—").foregroundStyle(.secondary)
                        }
                    }
                }

                if !settledLendingTransactions.isEmpty {
                    Section("借贷结算") {
                        ForEach(settledLendingTransactions) { item in
                            HStack {
                                Text(LocalizedStringKey(item.lendingDirection?.displayName ?? ""))
                                    .font(.body)
                                Spacer()
                                CurrencyText(amount: abs(item.amount), currencyCode: item.currencyCode, font: .body)
                            }
                        }
                    }
                }
            }

            Section("详情") {
                if let note = transaction.note, !note.isEmpty {
                    LabeledContent("备注") { Text(note) }
                }
                LabeledContent("日期") {
                    Text(transaction.date.formatted(date: .long, time: .shortened))
                }
            }

            if !photoDataList.isEmpty {
                Section("照片") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Array(photoDataList.enumerated()), id: \.offset) { index, data in
                                if let uiImage = UIImage(data: data) {
                                    Button {
                                        selectedPhotoItem = PhotoItem(data: data)
                                    } label: {
                                        Image(uiImage: uiImage)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 100, height: 100)
                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
            }

            if !transaction.tags.isEmpty {
                Section("标签") {
                    FlowLayout(spacing: 6) {
                        ForEach(transaction.tags, id: \.self) { tag in
                            Text(tag)
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.blue.opacity(0.1))
                                .clipShape(Capsule())
                        }
                    }
                }
            }

            Section {
                Button { showEditSheet = true } label: {
                    Label("编辑", systemImage: "pencil")
                }
                if canRefund {
                    Button { showRefundSheet = true } label: {
                        Label("退款", systemImage: "arrow.uturn.backward")
                    }
                }
                Button(role: .destructive) { showDeleteAlert = true } label: {
                    Label("删除", systemImage: "trash")
                }
            }
        }
        .navigationTitle("交易详情")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if let paths = transaction.photoURLs, !paths.isEmpty {
                photoDataList = PhotoStorage.load(paths: paths)
            }
            loadLinkedRefunds()
            loadSettledExpenses()
            loadSettledLendingTransactions()
        }
        .sheet(item: $selectedPhotoItem) { item in
            FullScreenPhotoView(data: item.data)
        }
        .sheet(isPresented: $showEditSheet) {
            AddEditTransactionView(editing: transaction)
        }
        .sheet(isPresented: $showSplitForm) {
            if let ledger = transaction.ledger ?? appContainer.currentLedger {
                SplitFormView(transaction: transaction, ledger: ledger)
            }
        }
        .sheet(isPresented: $showRefundSheet) {
            RefundSheetView(original: transaction) {
                loadLinkedRefunds()
            }
        }
        .alert("确认删除", isPresented: $showDeleteAlert) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) { delete() }
        } message: {
            Text("此操作不可撤销，确定要删除此交易吗？")
        }
    }

    private var iconColor: Color {
        if let cat = transaction.category { return Color(hex: cat.colorHex) }
        if transaction.isLending {
            switch transaction.lendingDirection {
            case .lendOut, .repay: return .orange
            case .borrowIn, .collect: return .green
            case .none: return .orange
            }
        }
        switch transaction.type {
        case .income: return .green
        case .expense: return .red
        case .transfer: return .blue
        case .lending: break
        case .adjustment: return .purple
        }
        return .secondary
    }

    private var titleText: String {
        if let d = transaction.lendingDirection { return d.displayName }
        return transaction.category?.name ?? transaction.type.displayName
    }

    private var subtitleText: String {
        if transaction.isLending {
            let from = transaction.account?.name ?? "—"
            let to = transaction.toAccount?.name ?? "—"
            return "\(NSLocalizedString(from, comment: "")) → \(NSLocalizedString(to, comment: ""))"
        }
        return transaction.type.displayName
    }

    @ViewBuilder
    private var amountView: some View {
        switch transaction.type {
        case .income:
            CurrencyText(amount: transaction.amount, currencyCode: transaction.currencyCode, showSign: true, font: .title2, foregroundColor: .green)
        case .expense:
            CurrencyText(amount: transaction.amount, currencyCode: transaction.currencyCode, showSign: true, font: .title2, foregroundColor: .red)
        case .transfer:
            HStack(spacing: 0) {
                Text("↔").font(.title2)
                CurrencyText(amount: abs(transaction.amount), currencyCode: transaction.currencyCode, font: .title2, foregroundColor: .blue)
            }
        case .lending:
            CurrencyText(amount: transaction.amount, currencyCode: transaction.currencyCode, showSign: true, font: .title2, foregroundColor: transaction.amount >= 0 ? .green : .orange)
        case .adjustment:
            CurrencyText(amount: transaction.amount, currencyCode: transaction.currencyCode, showSign: true, font: .title2, foregroundColor: transaction.amount >= 0 ? .green : .red)
        }
    }

    private var canRefund: Bool {
        (transaction.type == .expense || transaction.type == .income)
            && transaction.refundGroupId == nil
    }

    private func loadLinkedRefunds() {
        let tid = transaction.id
        let descriptor = FetchDescriptor<Transaction>(
            predicate: #Predicate { $0.refundGroupId == tid }
        )
        linkedRefunds = (try? modelContext.fetch(descriptor)) ?? []
    }

    private func loadSettledExpenses() {
        let tid = transaction.id
        let descriptor = FetchDescriptor<Transaction>(
            predicate: #Predicate { $0.reimbursedById == tid }
        )
        settledExpenses = (try? modelContext.fetch(descriptor)) ?? []
    }

    private func loadSettledLendingTransactions() {
        let tid = transaction.id
        let descriptor = FetchDescriptor<Transaction>(
            predicate: #Predicate { $0.settledByLendingTransactionId == tid }
        )
        settledLendingTransactions = (try? modelContext.fetch(descriptor)) ?? []
    }

    private func delete() {
        if let paths = transaction.photoURLs, !paths.isEmpty {
            PhotoStorage.delete(paths: paths)
        }
        try? appContainer.transactionService.deleteTransaction(transaction, context: modelContext)
        dismiss()
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        layout(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(proposal: proposal, subviews: subviews)
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x, y: bounds.minY + result.positions[index].y), proposal: proposal)
        }
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        var positions: [CGPoint] = []

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += lineHeight + spacing
                lineHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }

        return (CGSize(width: maxWidth, height: y + lineHeight), positions)
    }
}
