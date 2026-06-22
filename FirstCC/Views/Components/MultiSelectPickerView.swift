import SwiftUI

/// Multi-select picker sheet — modified from SearchablePickerView
/// Supports selecting multiple items (Set<UUID>) instead of single select.
struct MultiSelectPickerView<Item: Identifiable & Hashable>: View where Item.ID == UUID {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let items: [Item]
    let itemLabel: (Item) -> String
    let itemIcon: (Item) -> String
    let itemColor: (Item) -> Color
    let recentKey: String
    let indentLevel: ((Item) -> Int)?
    let childrenProvider: ((Item) -> [Item])?
    @Binding var selection: Set<UUID>

    @State private var localSelection: Set<UUID> = []
    @State private var searchText = ""

    init(
        title: String,
        items: [Item],
        itemLabel: @escaping (Item) -> String,
        itemIcon: @escaping (Item) -> String,
        itemColor: @escaping (Item) -> Color = { _ in .blue },
        recentKey: String,
        indentLevel: ((Item) -> Int)? = nil,
        childrenProvider: ((Item) -> [Item])? = nil,
        selection: Binding<Set<UUID>>
    ) {
        self.title = title
        self.items = items
        self.itemLabel = itemLabel
        self.itemIcon = itemIcon
        self.itemColor = itemColor
        self.recentKey = recentKey
        self.indentLevel = indentLevel
        self.childrenProvider = childrenProvider
        self._selection = selection
    }

    private var recentIDs: [String] {
        UserDefaults.standard.stringArray(forKey: recentKey) ?? []
    }

    private var recentItems: [Item] {
        recentIDs.compactMap { idStr in items.first { "\($0.id)" == idStr } }
    }

    private var filteredItems: [Item] {
        guard !searchText.isEmpty else { return [] }
        return items.filter { itemLabel($0).localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        NavigationStack {
            List {
                // Recent section
                if searchText.isEmpty && !recentItems.isEmpty {
                    Section("最近使用") {
                        ForEach(recentItems) { item in
                            selectionRow(for: item)
                        }
                    }
                }

                // Search results
                if !searchText.isEmpty {
                    Section("搜索结果") {
                        if filteredItems.isEmpty {
                            Text("无匹配结果").foregroundStyle(.secondary)
                        } else {
                            ForEach(filteredItems) { item in
                                selectionRow(for: item)
                            }
                        }
                    }
                }

                // All items
                if searchText.isEmpty {
                    Section("全部") {
                        ForEach(items) { item in
                            selectionRow(for: item)
                        }
                    }
                }
            }
            .searchable(text: $searchText)
            .navigationTitle(title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("确认") {
                        selection = localSelection
                        dismiss()
                    }
                }
                #if os(iOS)
                ToolbarItem(placement: .bottomBar) {
                    HStack {
                        Button("全选") {
                            localSelection = Set(items.map(\.id))
                        }
                        Spacer()
                        Button("清除") {
                            localSelection.removeAll()
                        }
                    }
                }
                #endif
            }
            .onAppear { localSelection = selection }
        }
    }

    // MARK: - Row

    private func selectionRow(for item: Item) -> some View {
        let isSelected = localSelection.contains(item.id)
        let indent = indentLevel?(item) ?? 0

        return Button {
            localSelection.toggle(item.id)
            if localSelection.contains(item.id) {
                saveRecent(item)
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: itemIcon(item))
                    .font(.system(size: 16))
                    .foregroundStyle(isSelected ? Color.designPrimaryFixedDim : itemColor(item))
                    .frame(width: 24)

                Text(LocalizedStringKey(itemLabel(item)))
                    .font(indent > 0 ? .designBodySmall : .designBodyMedium)
                    .foregroundStyle(isSelected
                        ? Color.designPrimaryFixedDim
                        : indent > 0 ? Color.designOnSurfaceVariant : .primary)

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(isSelected ? Color.designPrimaryFixedDim : Color.designOnSurfaceVariant.opacity(0.4))
            }
            .padding(.leading, CGFloat(indent) * 24)
        }
        .buttonStyle(.plain)
    }

    private func saveRecent(_ item: Item) {
        var ids = UserDefaults.standard.stringArray(forKey: recentKey) ?? []
        ids.removeAll { $0 == "\(item.id)" }
        ids.insert("\(item.id)", at: 0)
        UserDefaults.standard.set(Array(ids.prefix(8)), forKey: recentKey)
    }
}
