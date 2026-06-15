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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("分类管理").font(.headline).foregroundStyle(Color.designOnSurface)
                    Spacer()
                    Button { showAddSheet = true } label: {
                        Image(systemName: "plus").fontWeight(.semibold)
                    }
                    .buttonStyle(.borderless)
                }

                if !expenseCategories.isEmpty {
                    Text("支出分类").font(.caption).foregroundStyle(Color.designOnSurfaceVariant)
                    ForEach(flatExpense) { cat in
                        categoryRow(cat)
                    }
                }
                if !incomeCategories.isEmpty {
                    Text("收入分类").font(.caption).foregroundStyle(Color.designOnSurfaceVariant).padding(.top, 8)
                    ForEach(flatIncome) { cat in
                        categoryRow(cat)
                    }
                }
            }
            .padding(24).frame(maxWidth: 600)
        }
        .designScreen()
        .onAppear(perform: load)
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
            Text(LocalizedStringKey(cat.name)).font(.body)
            if cat.isSystem {
                Text("内置").font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { !cat.isHidden },
                set: { newVal in
                    cat.isHidden = !newVal
                    try? modelContext.save()
                    load()
                }
            ))
            .labelsHidden().scaleEffect(0.8)
        }
        .padding(.leading, cat.parent != nil ? 20 : 0)
        .contentShape(Rectangle())
        .onTapGesture { editingCategory = cat }
    }

    private func load() {
        guard let l = effectiveLedger else { return }
        incomeCategories = (try? appContainer.categoryService.fetchAllCategories(for: l, type: .income, context: modelContext)) ?? []
        expenseCategories = (try? appContainer.categoryService.fetchAllCategories(for: l, type: .expense, context: modelContext)) ?? []
    }
}

