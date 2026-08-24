import SwiftUI
@preconcurrency import CoreData

struct MacCategoryListView: View {
    @Environment(AppContainer.self) private var appContainer
    @Environment(\.managedObjectContext) private var modelContext
    let ledger: Ledger?
    @State private var incomeCategories: [Category] = []
    @State private var expenseCategories: [Category] = []
    @State private var showAddSheet = false
    @State private var editingCategory: Category?
    @State private var listVersion = 0
    @State private var toggleRefresh = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("分类管理").font(.designHeadlineMedium).foregroundStyle(Color.designOnSurface)
                Spacer()
                Button { showAddSheet = true } label: {
                    Image(systemName: "plus").fontWeight(.semibold)
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 12)

            if flatExpense.isEmpty && flatIncome.isEmpty {
                ContentUnavailableView(
                    "暂无分类",
                    systemImage: "square.grid.2x2",
                    description: Text("点击右上角 + 添加分类")
                )
                .padding(24)
                .frame(maxWidth: .infinity)
            } else {
                List {
                    if !flatExpense.isEmpty {
                        Section {
                            ForEach(flatExpense) { cat in
                                categoryRow(cat)
                            }
                            .onMove { from, to in moveCategory(from: from, to: to, isExpense: true) }
                        } header: {
                            Text("支出分类")
                                .font(.designBodyLarge)
                                .foregroundStyle(Color.designPrimaryFixedDim)
                        }
                    }
                    if !flatIncome.isEmpty {
                        Section {
                            ForEach(flatIncome) { cat in
                                categoryRow(cat)
                            }
                            .onMove { from, to in moveCategory(from: from, to: to, isExpense: false) }
                        } header: {
                            Text("收入分类")
                                .font(.designBodyLarge)
                                .foregroundStyle(Color.designPrimaryFixedDim)
                        }
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
                .id(listVersion)
            }
        }
        .frame(minWidth: 420, maxWidth: 600, minHeight: 400)
        .designScreen()
        .onAppear(perform: load)
        .onChange(of: toggleRefresh) { _, _ in load() }
        .sheet(isPresented: $showAddSheet, onDismiss: { load() }) {
            MacCategoryEditSheet(ledger: effectiveLedger)
        }
        .sheet(item: $editingCategory, onDismiss: { load() }) { category in
            MacCategoryEditSheet(editing: category, ledger: effectiveLedger)
        }
    }

    private var effectiveLedger: Ledger? { ledger ?? appContainer.currentLedger }

    private var flatExpense: [Category] {
        flattenCategoryTree(expenseCategories.filter { $0.parent == nil })
    }
    private var flatIncome: [Category] {
        flattenCategoryTree(incomeCategories.filter { $0.parent == nil })
    }

    private func categoryRow(_ cat: Category) -> some View {
        HStack(spacing: 8) {
            Image(systemName: cat.iconName)
                .foregroundStyle(Color(hex: cat.colorHex))
            Text(LocalizedStringKey(cat.name)).font(.designBodyMedium)
            if cat.isSystem {
                Text("内置").font(.designBodyCaption).foregroundStyle(.secondary)
            }
            if cat.isHidden {
                Text("已隐藏").font(.designBodyCaption).foregroundStyle(Color.designOnSurfaceVariant.opacity(0.5))
            }
            Spacer()
            Button { editingCategory = cat } label: {
                Image(systemName: "pencil")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text("编辑分类"))

            Button {
                cat.isHidden = !cat.isHidden
                try? modelContext.save()
                toggleRefresh.toggle()
            } label: {
                Image(systemName: cat.isHidden ? "eye.slash" : "eye")
                    .font(.body)
                    .foregroundStyle(cat.isHidden ? Color.designOnSurfaceVariant.opacity(0.4) : Color.designPrimaryFixedDim)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text(cat.isHidden ? "显示分类" : "隐藏分类"))
        }
        .padding(.leading, cat.parent != nil ? 20 : 0)
    }

    private func load() {
        guard let l = effectiveLedger else { return }
        incomeCategories = (try? appContainer.categoryService.fetchAllCategories(for: l, type: .income, context: modelContext)) ?? []
        expenseCategories = (try? appContainer.categoryService.fetchAllCategories(for: l, type: .expense, context: modelContext)) ?? []
    }

    // MARK: - Drag Reorder

    private func moveCategory(from: IndexSet, to destRaw: Int, isExpense: Bool) {
        let categories = isExpense ? expenseCategories : incomeCategories
        let flat = flattenCategoryTree(categories.filter { $0.parent == nil })
        guard let firstSource = from.first else { return }
        let movingItem = flat[firstSource]

        var dest = destRaw

        if movingItem.parent == nil {
            let boundaries = parentBoundaries(flat)
            if !boundaries.contains(dest) {
                let leftBoundary = boundaries.last(where: { $0 <= dest }) ?? 0
                if leftBoundary == firstSource {
                    listVersion += 1; return
                }
                dest = boundaries.first(where: { $0 >= destRaw }) ?? flat.count
            }
        } else {
            let parentID = movingItem.parent!.id
            guard let parentIdx = flat.firstIndex(where: { $0.id == parentID }) else { return }
            let nextParentIdx = flat[parentIdx...].dropFirst().firstIndex(where: { $0.parent == nil }) ?? flat.count
            guard dest > parentIdx && dest <= nextParentIdx else { listVersion += 1; return }
        }

        var expandedFrom = IndexSet(from)
        if movingItem.parent == nil {
            for i in 0..<flat.count {
                if flat[i].parent?.id == movingItem.id {
                    expandedFrom.insert(i)
                }
            }
        }

        var mutableFlat = flat
        let removed = expandedFrom.sorted().map { mutableFlat[$0] }
        for idx in expandedFrom.sorted().reversed() {
            mutableFlat.remove(at: idx)
        }

        let removedBeforeDest = expandedFrom.filter { $0 < dest }.count
        let adjustedTo = dest - removedBeforeDest
        mutableFlat.insert(contentsOf: removed, at: min(adjustedTo, mutableFlat.count))
        reassignSortOrders(mutableFlat)

        if isExpense {
            expenseCategories = mutableFlat
        } else {
            incomeCategories = mutableFlat
        }
        try? modelContext.save()

        if dest != destRaw {
            listVersion += 1
        }
    }

    private func parentBoundaries(_ flat: [Category]) -> [Int] {
        var indices: [Int] = [0]
        for (i, item) in flat.enumerated() where item.parent == nil && i > 0 {
            indices.append(i)
        }
        indices.append(flat.count)
        return indices
    }

    private func reassignSortOrders(_ flat: [Category]) {
        var parentOrder: Int64 = 0
        var childCounters: [UUID: Int64] = [:]
        for item in flat {
            if let parent = item.parent {
                let idx = childCounters[parent.id] ?? 0
                item.sortOrder = idx
                childCounters[parent.id] = idx + 1
            } else {
                item.sortOrder = parentOrder
                parentOrder += 1
                childCounters[item.id] = 0
            }
        }
    }
}
