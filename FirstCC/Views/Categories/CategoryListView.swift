import SwiftUI
import SwiftData

struct CategoryListView: View {
    @EnvironmentObject private var appContainer: AppContainer
    @Environment(\.modelContext) private var modelContext
    @State private var incomeCategories: [Category] = []
    @State private var expenseCategories: [Category] = []
    @State private var showAddSheet = false
    @State private var editingCategory: Category?

    var body: some View {
        List {
            Section("支出分类") {
                ForEach(expenseCategories.filter { $0.parent == nil }) { category in
                    categoryRow(category)
                }
            }
            Section("收入分类") {
                ForEach(incomeCategories.filter { $0.parent == nil }) { category in
                    categoryRow(category)
                }
            }
        }
        .navigationTitle("分类管理")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showAddSheet = true } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddEditCategoryView()
        }
        .sheet(item: $editingCategory) { category in
            AddEditCategoryView(editing: category)
        }
        .onAppear(perform: loadCategories)
    }

    private func categoryRow(_ category: Category) -> some View {
        DisclosureGroup {
            ForEach(category.children ?? []) { child in
                HStack {
                    Image(systemName: child.iconName)
                        .foregroundStyle(Color(hex: child.colorHex))
                    Text(LocalizedStringKey(child.name))
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { !child.isHidden },
                        set: { newValue in
                            child.isHidden = !newValue
                            try? modelContext.save()
                        }
                    ))
                    .labelsHidden()
                    .scaleEffect(0.8)
                }
                .contentShape(Rectangle())
                .onTapGesture { editingCategory = child }
            }
            if !category.isSystem {
                Button(role: .destructive) {
                    deleteCategory(category)
                } label: {
                    Label("删除「\(category.name)」", systemImage: "trash")
                }
            }
        } label: {
            HStack {
                Image(systemName: category.iconName)
                    .foregroundStyle(Color(hex: category.colorHex))
                Text(LocalizedStringKey(category.name))
                if category.isSystem {
                    Text("内置")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { !category.isHidden },
                    set: { newValue in
                        category.isHidden = !newValue
                        try? modelContext.save()
                    }
                ))
                .labelsHidden()
                .scaleEffect(0.8)
            }
        }
    }

    private func loadCategories() {
        guard let ledger = appContainer.currentLedger else { return }
        incomeCategories = (try? appContainer.categoryService.fetchAllCategories(for: ledger, type: .income, context: modelContext)) ?? []
        expenseCategories = (try? appContainer.categoryService.fetchAllCategories(for: ledger, type: .expense, context: modelContext)) ?? []
    }

    private func deleteCategory(_ category: Category) {
        try? appContainer.categoryService.deleteCategory(category, context: modelContext)
        loadCategories()
    }
}
