import SwiftUI
@preconcurrency import CoreData

struct MacSearchView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var modelContext
    @Environment(AppContainer.self) private var appContainer
    @State private var viewModel: SearchViewModel
    @FocusState private var isFocused: Bool
    @State private var showSaveAlert = false
    @State private var saveFilterName = ""
    @State private var selectedTransaction: Transaction?

    init(ledger: Ledger, transactionService: TransactionServiceProtocol) {
        _viewModel = State(initialValue: SearchViewModel(ledger: ledger, transactionService: transactionService))
    }

    var body: some View {
        VStack(spacing: 0) {
            searchBar
                .padding(.horizontal, 24)
                .padding(.top, 16)

            savedFiltersRow
                .padding(.horizontal, 24)

            advancedFilterPanel
                .padding(.horizontal, 24)
                .padding(.top, 8)

            filterChips
                .padding(.horizontal, 24)

            if viewModel.isSearching {
                Spacer()
                ProgressView()
                Spacer()
            } else if viewModel.hasSearched && !viewModel.hasResults {
                emptyResult
            } else if viewModel.hasResults {
                summaryRow
                    .padding(.horizontal, 24)
                    .padding(.top, 10)
                resultList
            }
            Spacer(minLength: 0)
        }
        .macSheetFrame()
        .onAppear { isFocused = true }
        .onSubmit {
            viewModel.submitSearch(context: modelContext)
        }
        .toolbar { toolbarContent }
        .sheet(item: $selectedTransaction) { t in
            MacAddTransactionSheet(editing: t, displayMode: true)
        }
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

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("关闭") { dismiss() }
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Color.designOnSurfaceVariant)
                .font(.system(size: 16))

            TextField(String(localized: "搜索交易... 例如 2026 餐饮"), text: $viewModel.searchText)
                .textFieldStyle(.plain)
                .focused($isFocused)
                .autocorrectionDisabled()
                .font(.designBodyMedium)
                .accessibilityIdentifier("mac-search-field")

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
                                    .font(.designBodySmall)
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
            }
            .padding(.top, 6)
        }
    }

    // MARK: - Advanced Filter Panel

    private var advancedFilterPanel: some View {
        MacAdvancedFilterView(
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
            }
            .padding(.top, 6)
        }
    }

    // MARK: - Summary Row

    private var summaryRow: some View {
        HStack {
            Text(String(localized: "找到 \(viewModel.totalCount) 笔交易，合计"))
                .font(.designBodyMedium)
                .foregroundStyle(Color.designOnSurfaceVariant)
            CurrencyText(
                amount: viewModel.totalAmount,
                currencyCode: "",
                size: 15,
                foregroundColor: Color.designOnSurface
            )
            .fontWeight(.semibold)
            Spacer()
            sortMenu
        }
    }

    private var sortMenu: some View {
        Menu {
            ForEach(SearchViewModel.SortOrder.allCases, id: \.self) { order in
                Button {
                    viewModel.sortOrder = order
                } label: {
                    HStack {
                        Text(LocalizedStringKey(order.displayName))
                        if viewModel.sortOrder == order {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
    }

    // MARK: - Result List

    private var resultList: some View {
        ScrollView {
            VStack(spacing: 6) {
                ForEach(groupedResults, id: \.key) { group in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(group.key)
                            .font(.designBodyCaption)
                            .foregroundStyle(Color.designOnSurfaceVariant)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, 4)

                        ForEach(group.value, id: \.objectID) { t in
                            Button {
                                selectedTransaction = t
                            } label: {
                                TransactionRowView(transaction: t)
                                    .padding(.vertical, 2)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(12)
        }
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
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "magnifyingglass")
                .font(.system(size: 40))
                .foregroundStyle(Color.designOnSurfaceVariant)
            Text("未找到匹配的交易")
                .font(.designHeadlineMedium)
                .foregroundStyle(Color.designOnSurfaceVariant)
            if viewModel.hasManualFilters {
                Text("试试清除筛选条件，或者放宽日期/金额范围")
                    .font(.designBodyMedium)
                    .foregroundStyle(Color.designOnSurfaceVariant.opacity(0.5))
            } else {
                Text("试试换个关键词，例如 餐饮 或 2026")
                    .font(.designBodyMedium)
                    .foregroundStyle(Color.designOnSurfaceVariant.opacity(0.5))
            }
            Spacer()
        }
    }
}
