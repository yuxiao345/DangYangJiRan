import SwiftUI

struct SearchView: View {
    @Environment(\.managedObjectContext) private var modelContext
    @State private var viewModel: SearchViewModel
    @FocusState private var isFocused: Bool

    init(viewModel: SearchViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            filterChips
            if viewModel.hasSearched && !viewModel.hasResults {
                emptyResult
            } else if viewModel.hasResults {
                summaryRow
                resultList
            }
            Spacer(minLength: 0)
        }
        .navigationTitle("搜索")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            isFocused = true
        }
        .onChange(of: viewModel.searchText) { _, _ in
            viewModel.scheduleSearch(context: modelContext)
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Color.designOnSurfaceVariant)

            TextField("搜索交易...", text: $viewModel.searchText)
                .textFieldStyle(.plain)
                .focused($isFocused)
                .autocorrectionDisabled()

            if !viewModel.searchText.isEmpty {
                Button {
                    viewModel.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.designOnSurfaceVariant)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.designGlassBg)
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }

    // MARK: - Filter Chips

    @ViewBuilder
    private var filterChips: some View {
        let filters = viewModel.activeFilters
        if !filters.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(filters, id: \.self) { chip in
                        Text(chip)
                            .font(.designBodySmall)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background {
                                Capsule()
                                    .fill(Color.designPrimaryContainer.opacity(0.1))
                            }
                            .overlay {
                                Capsule()
                                    .stroke(Color.designPrimaryContainer.opacity(0.3), lineWidth: 1)
                            }
                    }
                }
                .padding(.horizontal, 12)
            }
            .padding(.top, 6)
        }
    }

    // MARK: - Summary Row

    private var summaryRow: some View {
        HStack {
            Text("找到 \(viewModel.totalCount) 笔交易，合计 ")
                .font(.designBodyMedium)
                .foregroundStyle(Color.designOnSurfaceVariant)
            CurrencyText(
                amount: viewModel.totalAmount,
                currencyCode: "",
                size: 15,
                foregroundColor: viewModel.totalAmount >= 0 ? Color.designOnSurface : Color.designAccentRed
            )
            .fontWeight(.semibold)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - Result List

    private var resultList: some View {
        List {
            ForEach(groupedResults, id: \.key) { group in
                Section(group.key) {
                    ForEach(group.value, id: \.id) { transaction in
                        NavigationLink(destination: TransactionDetailView(transaction: transaction)) {
                            TransactionRowView(transaction: transaction)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private var groupedResults: [(key: String, value: [Transaction])] {
        let grouped = Dictionary(grouping: viewModel.searchResults) { t in
            t.date.formatted(date: .complete, time: .omitted)
        }
        return grouped.sorted { $0.key > $1.key }.map { ($0.key, $0.value.sorted { $0.date > $1.date }) }
    }

    // MARK: - Empty State

    private var emptyResult: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "magnifyingglass")
                .font(.system(size: 40))
                .foregroundStyle(Color.designOnSurfaceVariant)
            Text("未找到匹配的交易")
                .font(.designHeadlineMedium)
                .foregroundStyle(Color.designOnSurfaceVariant)
            Text("尝试调整搜索关键词")
                .font(.designBodyMedium)
                .foregroundStyle(Color.designOnSurfaceVariant.opacity(0.5))
            Spacer()
        }
    }
}
