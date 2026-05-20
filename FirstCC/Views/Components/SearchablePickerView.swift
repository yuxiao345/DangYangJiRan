import SwiftUI

struct SearchablePickerView<Item: Identifiable & Hashable>: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let items: [Item]
    let itemLabel: (Item) -> String
    let itemIcon: (Item) -> String
    let itemColor: (Item) -> Color
    let recentKey: String
    @Binding var selection: Item?

    @State private var searchText = ""
    @State private var recentIDs: [String] = []

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

                Section(searchText.isEmpty ? "全部" : "搜索结果") {
                    ForEach(filteredItems) { item in
                        itemRow(item)
                    }
                }
            }
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "搜索")
            .navigationTitle(LocalizedStringKey(title))
            .navigationBarTitleDisplayMode(.inline)
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
        let filtered = searchText.isEmpty
            ? items
            : items.filter { itemLabel($0).localizedCaseInsensitiveContains(searchText) }
        let recentIDSet = Set(recentItems.map { $0.id })
        return filtered.filter { !recentIDSet.contains($0.id) }
    }

    @ViewBuilder
    private func itemRow(_ item: Item) -> some View {
        HStack {
            Image(systemName: itemIcon(item))
                .foregroundStyle(itemColor(item))
                .frame(width: 28)
            Text(itemLabel(item))
            Spacer()
            if item.id == selection?.id {
                Image(systemName: "checkmark")
                    .foregroundStyle(Color.designPrimaryContainer)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            selection = item
            saveRecent(item)
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
}

extension SearchablePickerView {
    init(
        title: String,
        items: [Item],
        itemLabel: @escaping (Item) -> String,
        itemIcon: @escaping (Item) -> String,
        recentKey: String,
        selection: Binding<Item?>
    ) {
        self.init(
            title: title,
            items: items,
            itemLabel: itemLabel,
            itemIcon: itemIcon,
            itemColor: { _ in .blue },
            recentKey: recentKey,
            selection: selection
        )
    }
}
