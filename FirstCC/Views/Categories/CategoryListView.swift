import SwiftUI
@preconcurrency import CoreData

struct CategoryListView: View {
    @EnvironmentObject private var appContainer: AppContainer
    @Environment(\.managedObjectContext) private var modelContext
    @State private var incomeCategories: [Category] = []
    @State private var expenseCategories: [Category] = []
    @State private var showAddSheet = false
    @State private var editingCategory: Category?
    @State private var showConfirmAlert = false
    @State private var confirmHideParent: Category?
    @State private var listVersion = 0

    let ledger: Ledger?
    private var effectiveLedger: Ledger? { ledger ?? appContainer.currentLedger }

    private var flatExpense: [Category] { flattenTree(expenseCategories.filter { $0.parent == nil }) }
    private var flatIncome: [Category] { flattenTree(incomeCategories.filter { $0.parent == nil }) }

    init(ledger: Ledger? = nil) {
        self.ledger = ledger
    }

    var body: some View {
        List {
            Section("支出分类") {
                if flatExpense.isEmpty {
                    Text("暂无分类").foregroundStyle(.secondary)
                }
                ForEach(flatExpense) { category in
                    categoryItem(category)
                }
                .onMove { from, to in moveCategory(from: from, to: to, isExpense: true) }
            }
            Section("收入分类") {
                if flatIncome.isEmpty {
                    Text("暂无分类").foregroundStyle(.secondary)
                }
                ForEach(flatIncome) { category in
                    categoryItem(category)
                }
                .onMove { from, to in moveCategory(from: from, to: to, isExpense: false) }
            }
        }
        .id(listVersion)
        .navigationTitle("分类管理")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showAddSheet = true } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .environment(\.editMode, .constant(.active))
        .sheet(isPresented: $showAddSheet, onDismiss: { loadCategories() }) {
            AddEditCategoryView(ledger: effectiveLedger)
        }
        .sheet(item: $editingCategory, onDismiss: { loadCategories() }) { category in
            AddEditCategoryView(editing: category, ledger: effectiveLedger)
        }
        .alert("关闭父分类", isPresented: $showConfirmAlert) {
            Button("取消", role: .cancel) { confirmHideParent = nil }
            Button("确认关闭") {
                if let parent = confirmHideParent {
                    parent.isHidden = true
                    setDescendantsHidden(parent, isHidden: true)
                    try? modelContext.save()
                    loadCategories()
                }
                confirmHideParent = nil
            }
        } message: {
            if let parent = confirmHideParent {
                Text("关闭「\(parent.name)」将同时关闭其下的 \(childrenCount(of: parent)) 个子分类，确定要继续吗？")
            }
        }
        .onAppear(perform: loadCategories)
    }

    // MARK: - Row

    private func categoryItem(_ category: Category) -> some View {
        HStack {
            Image(systemName: category.iconName)
                .foregroundStyle(Color(hex: category.colorHex))
            Text(LocalizedStringKey(category.name))
                .foregroundStyle(category.isHidden ? .secondary : .primary)
            if category.isSystem {
                Text("内置")
                    .font(.designBodySmall)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { !category.isHidden },
                set: { newValue in
                    if !newValue {
                        toggleOff(category)
                    } else {
                        category.isHidden = false
                        try? modelContext.save()
                        loadCategories()
                    }
                }
            ))
            .labelsHidden()
            .scaleEffect(0.8)
        }
        .padding(.leading, category.parent != nil ? 24 : 0)
        .contentShape(Rectangle())
        .onTapGesture { editingCategory = category }
    }

    // MARK: - Toggle

    private func toggleOff(_ category: Category) {
        if category.parent == nil && !sortedChildren(of: category).isEmpty {
            confirmHideParent = category
            showConfirmAlert = true
        } else {
            category.isHidden = true
            try? modelContext.save()
            loadCategories()
        }
    }

    // MARK: - Flat tree (no hidden filter — show all)

    private func flattenTree(_ parents: [Category]) -> [Category] {
        var result: [Category] = []
        for parent in parents.sorted(by: { $0.sortOrder < $1.sortOrder }) {
            result.append(parent)
            for child in sortedChildren(of: parent) {
                result.append(child)
            }
        }
        return result
    }

    private func sortedChildren(of parent: Category) -> [Category] {
        (parent.children as? Set<Category> ?? [])
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    private func childrenCount(of parent: Category) -> Int {
        var count = 0
        for child in parent.children ?? [] {
            count += 1 + childrenCount(of: child)
        }
        return count
    }

    // MARK: - Move

    private func moveCategory(from: IndexSet, to destRaw: Int, isExpense: Bool) {
        let categories = isExpense ? expenseCategories : incomeCategories
        let flat = flattenTree(categories.filter { $0.parent == nil })
        guard let firstSource = from.first else { return }
        let movingItem = flat[firstSource]

        // Validate / snap destination.
        // `destRaw` is a pre-removal index (MutableCollection.move convention).
        var dest = destRaw
        if movingItem.parent == nil {
            let boundaries = parentBoundaries(flat)
            if !boundaries.contains(dest) {
                let leftBoundary = boundaries.last(where: { $0 <= dest }) ?? 0
                if leftBoundary == firstSource {
                    // Dropped within own group (between self and own children) → reject
                    listVersion += 1; return
                }
                // Dropped within another parent's group → snap below that group
                dest = boundaries.first(where: { $0 >= destRaw }) ?? flat.count
            }
        } else {
            let parentID = movingItem.parent!.id
            guard let parentIdx = flat.firstIndex(where: { $0.id == parentID }) else { return }
            let nextParentIdx = flat[parentIdx...].dropFirst().firstIndex(where: { $0.parent == nil }) ?? flat.count
            guard dest > parentIdx && dest <= nextParentIdx else { listVersion += 1; return }
        }

        // Expand: parent drags children along
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

        // Convert pre-removal destination to post-removal insert index
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

        // When snapping changed the destination, force List rebuild so
        // SwiftUI visual matches data (same workaround as early-return case).
        if dest != destRaw {
            listVersion += 1
        }
    }

    /// Valid insertion indices for a parent category
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

    // MARK: - Cascade hide

    private func setDescendantsHidden(_ category: Category, isHidden: Bool) {
        for child in category.children ?? [] {
            child.isHidden = isHidden
            setDescendantsHidden(child, isHidden: isHidden)
        }
    }

    // MARK: - Data

    private func loadCategories() {
        guard let ledger = effectiveLedger else { return }
        incomeCategories = (try? appContainer.categoryService.fetchAllCategories(for: ledger, type: .income, context: modelContext)) ?? []
        expenseCategories = (try? appContainer.categoryService.fetchAllCategories(for: ledger, type: .expense, context: modelContext)) ?? []
    }

}
