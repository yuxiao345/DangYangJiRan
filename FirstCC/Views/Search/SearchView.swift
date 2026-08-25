import SwiftUI
@preconcurrency import CoreData

struct SearchView: View {
    @Environment(AppContainer.self) private var appContainer
    @Environment(\.managedObjectContext) private var modelContext
    @State private var viewModel: SearchViewModel
    @FocusState private var isFocused: Bool
    @State private var showSaveAlert = false
    @State private var saveFilterName = ""

    init(viewModel: SearchViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            savedFiltersRow
            advancedFilterPanel
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
        .navigationDestination(for: NSManagedObjectID.self) { id in
            if let tx = modelContext.object(with: id) as? Transaction {
                TransactionDetailView(transaction: tx)
            }
        }
        .designScreen()
        .alert(String(localized: "保存筛选"), isPresented: $showSaveAlert) {
            TextField(String(localized: "名称"), text: $saveFilterName)
            Button(String(localized: "取消"), role: .cancel) {}
            Button(String(localized: "保存")) {
                let name = saveFilterName.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty { viewModel.saveCurrentFilter(name: name) }
                saveFilterName = ""
            }
        }
    }

    // MARK: - Saved Filters

    @ViewBuilder
    private var savedFiltersRow: some View {
        let filters = viewModel.savedFilters
        if !filters.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(filters) { filter in
                        HStack(spacing: 2) {
                            Button {
                                viewModel.applyFilter(filter)
                                viewModel.applyManualFilters(context: modelContext)
                            } label: {
                                Text(filter.name)
                                    .font(.caption)
                                    .padding(.leading, 10)
                                    .padding(.vertical, 5)
                            }
                            .buttonStyle(.plain)
                            Button {
                                viewModel.deleteFilter(id: filter.id)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 11))
                                    .padding(.trailing, 6)
                                    .padding(.vertical, 5)
                            }
                            .buttonStyle(.plain)
                        }
                        .background(Capsule().fill(Color.designPrimaryContainer.opacity(0.1)))
                        .overlay(Capsule().stroke(Color.designPrimaryContainer.opacity(0.3), lineWidth: 1))
                        .foregroundStyle(Color.designPrimaryContainer)
                    }
                }
                .padding(.horizontal, 12)
            }
            .padding(.top, 6)
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Color.designOnSurfaceVariant)

            TextField("搜索交易... 例如 2026 餐饮", text: $viewModel.searchText)
                .textFieldStyle(.plain)
                .focused($isFocused)
                .autocorrectionDisabled()
                .accessibilityIdentifier("search-field")

            if !viewModel.searchText.isEmpty {
                Button {
                    viewModel.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.designOnSurfaceVariant)
                }
                .accessibilityLabel(Text("清空搜索"))
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

    // MARK: - Advanced Filter Panel

    private var advancedFilterPanel: some View {
        AdvancedFilterPanel(
            isExpanded: $viewModel.isFilterPanelExpanded,
            selectedCategoryIDs: $viewModel.selectedCategoryIDs,
            selectedMemberIDs: $viewModel.selectedMemberIDs,
            selectedMerchantIDs: $viewModel.selectedMerchantIDs,
            selectedProjectIDs: $viewModel.selectedProjectIDs,
            dateFrom: $viewModel.dateFrom,
            dateTo: $viewModel.dateTo,
            amountMin: $viewModel.amountMin,
            amountMax: $viewModel.amountMax,
            keyword: $viewModel.manualKeyword,
            onApply: { viewModel.applyManualFilters(context: modelContext) },
            onSave: { showSaveAlert = true }
        )
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }

    // MARK: - Filter Chips

    @ViewBuilder
    private var filterChips: some View {
        let chips = viewModel.activeFilterChips
        if !chips.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(chips) { chip in
                        HStack(spacing: 4) {
                            Text(chip.label)
                                .font(.designBodySmall)
                            if chip.isManual, let clear = chip.clearAction {
                                Button(action: clear) {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 8, weight: .bold))
                                        .foregroundStyle(Color.designOnSurfaceVariant)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(Text("清除搜索"))
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background {
                            Capsule()
                                .fill(chip.isManual
                                    ? Color.designPrimaryFixedDim.opacity(0.15)
                                    : Color.designPrimaryContainer.opacity(0.1))
                        }
                        .overlay {
                            Capsule()
                                .stroke(chip.isManual
                                    ? Color.designPrimaryFixedDim.opacity(0.5)
                                    : Color.designPrimaryContainer.opacity(0.3),
                                    lineWidth: 1)
                        }
                        .foregroundStyle(chip.isManual
                            ? Color.designPrimaryFixedDim
                            : Color.designOnSurfaceVariant)
                    }
                }
                .padding(.horizontal, 12)
            }
            .padding(.top, 6)
        }
    }

    // MARK: - Summary Row

    private var summaryRow: some View {
        VStack(spacing: 4) {
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
                sortMenu
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
    }

    private var sortMenu: some View {
        Menu {
            Picker("排序", selection: $viewModel.sortOrder) {
                ForEach(SearchViewModel.SortOrder.allCases, id: \.self) { order in
                    Text(LocalizedStringKey(order.displayName)).tag(order)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            Image(systemName: "arrow.up.arrow.down")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Result List

    private var resultList: some View {
        List {
            ForEach(groupedResults, id: \.key) { group in
                Section(group.key) {
                    ForEach(group.value, id: \.objectID) { transaction in
                        NavigationLink(destination: TransactionDetailView(transaction: transaction)) {
                            TransactionRowView(transaction: transaction)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("search-result-cell")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .accessibilityIdentifier("search-results-list")
    }

    private var groupedResults: [(key: String, value: [Transaction])] {
        let sorted = viewModel.sortedResults
        let grouped = Dictionary(grouping: sorted) { t in
            t.date.formatted(date: .complete, time: .omitted)
        }
        return grouped.sorted { $0.key > $1.key }.map { ($0.key, $0.value.sorted { $0.date > $1.date }) }
    }

    // MARK: - Empty State

    private var emptyResult: some View {
        Group {
            if viewModel.hasManualFilters {
                ContentUnavailableView(
                    "未找到匹配的交易",
                    systemImage: "magnifyingglass",
                    description: Text("试试清除筛选条件，或者放宽日期/金额范围")
                )
            } else if !viewModel.searchText.isEmpty {
                ContentUnavailableView.search(text: viewModel.searchText)
            } else {
                ContentUnavailableView(
                    "无搜索结果",
                    systemImage: "magnifyingglass",
                    description: Text("试试换个关键词，例如 餐饮 或 2026")
                )
            }
        }
    }
}
