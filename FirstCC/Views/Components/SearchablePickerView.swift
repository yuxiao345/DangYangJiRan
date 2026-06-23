import SwiftUI

struct SearchablePickerView<Item: Identifiable & Hashable>: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let items: [Item]
    let itemLabel: (Item) -> String
    let itemIcon: (Item) -> String
    let itemColor: (Item) -> Color
    let recentKey: String
    let indentLevel: ((Item) -> Int)?
    let childrenProvider: ((Item) -> [Item])?
    let groupLabel: ((Item) -> String)?
    @Binding var selection: Item?

    @State private var searchText = ""
    @State private var recentIDs: [String] = []

    init(
        title: String,
        items: [Item],
        itemLabel: @escaping (Item) -> String,
        itemIcon: @escaping (Item) -> String,
        itemColor: @escaping (Item) -> Color = { _ in .blue },
        recentKey: String,
        indentLevel: ((Item) -> Int)? = nil,
        childrenProvider: ((Item) -> [Item])? = nil,
        groupLabel: ((Item) -> String)? = nil,
        selection: Binding<Item?>
    ) {
        self.title = title
        self.items = items
        self.itemLabel = itemLabel
        self.itemIcon = itemIcon
        self.itemColor = itemColor
        self.recentKey = recentKey
        self.indentLevel = indentLevel
        self.childrenProvider = childrenProvider
        self.groupLabel = groupLabel
        self._selection = selection
    }

    var body: some View {
        NavigationStack {
            List {
                if searchText.isEmpty && !recentItems.isEmpty {
                    Section("最近使用") {
                        ForEach(recentItems) { item in
                            itemRow(item)
                        }
                    }
                }

                if searchText.isEmpty, let gl = groupLabel {
                    let groups = groupedItems(using: gl)
                    ForEach(groups, id: \.label) { group in
                        Section(group.label) {
                            ForEach(group.items) { item in
                                itemRow(item)
                            }
                        }
                    }
                } else {
                    Section(searchText.isEmpty ? "全部" : "搜索结果") {
                        ForEach(filteredItems) { item in
                            itemRow(item)
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "搜索")
            .navigationTitle(LocalizedStringKey(title))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                if selection != nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("清除") { selection = nil; dismiss() }
                    }
                }
            }
            .onAppear { loadRecent() }
        }
    }

    private var recentItems: [Item] {
        recentIDs.compactMap { id in items.first { "\($0.id)" == id } }
    }

    private var filteredItems: [Item] {
        if searchText.isEmpty {
            return items
        }
        var matched = items.filter { itemLabel($0).localizedCaseInsensitiveContains(searchText) }
        if let provider = childrenProvider {
            var seen = Set(matched.map { $0.id })
            for item in matched {
                for child in provider(item) where !seen.contains(child.id) {
                    seen.insert(child.id)
                    matched.append(child)
                }
            }
        }
        return matched
    }

    @ViewBuilder
    private func itemRow(_ item: Item) -> some View {
        let level = min(indentLevel?(item) ?? 0, 2)
        let isSelected = item.id == selection?.id
        HStack {
            Image(systemName: itemIcon(item))
                .foregroundStyle(isSelected ? Color.designPrimaryContainer : itemColor(item))
                .frame(width: 28)
            Text(itemLabel(item))
                .font(level > 0 ? .designBodyMedium : nil)
                .foregroundStyle(isSelected ? Color.designPrimaryContainer : (level > 0 ? Color.designOnSurfaceVariant : .primary))
            Spacer()
            if isSelected {
                Image(systemName: "checkmark")
                    .foregroundStyle(Color.designPrimaryContainer)
            }
        }
        .padding(.leading, CGFloat(level) * 24)
        .contentShape(Rectangle())
        .onTapGesture {
            if isSelected {
                selection = nil
            } else {
                selection = item
                saveRecent(item)
            }
            dismiss()
        }
    }

    private func loadRecent() {
        recentIDs = UserDefaults.standard.stringArray(forKey: recentKey) ?? []
    }

    private func saveRecent(_ item: Item) {
        let id = "\(item.id)"
        var ids = recentIDs.filter { $0 != id }
        ids.insert(id, at: 0)
        recentIDs = Array(ids.prefix(8))
        UserDefaults.standard.set(recentIDs, forKey: recentKey)
    }

    /// Group items preserving the original sorted order (first-seen group wins ordering)
    private func groupedItems(using gl: (Item) -> String) -> [(label: String, items: [Item])] {
        var seen: [String] = []
        var dict: [String: [Item]] = [:]
        for item in items {
            let label = gl(item)
            if dict[label] == nil {
                seen.append(label)
            }
            dict[label, default: []].append(item)
        }
        return seen.map { (label: $0, items: dict[$0] ?? []) }
    }
}
