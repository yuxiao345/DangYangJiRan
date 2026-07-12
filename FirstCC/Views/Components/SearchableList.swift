import SwiftUI

/// 通用搜索列表包装组件 — 为管理页面（联系人/商家/项目）提供统一的搜索过滤能力。
/// 用法：将原有 `List { ForEach(items) }` 包在 `SearchableList` 内，用 `filteredItems` 替换 `items`。
///
/// 适用场景：扁平列表（Member、Merchant、Project）。分组列表（Account、Category）请直接使用 `.searchable`。
///
/// ```
/// SearchableList(items: members, searchKey: \.name) { filteredMembers, isSearching in
///     List {
///         if filteredMembers.isEmpty {
///             Text(isSearching ? "无匹配结果" : "暂无联系人")
///         }
///         ForEach(filteredMembers) { member in
///             // row content
///         }
///     }
///     .navigationTitle("联系人管理")
/// }
/// ```
struct SearchableList<Item: Identifiable, Content: View>: View {
    let items: [Item]
    let searchKey: KeyPath<Item, String>
    @ViewBuilder let content: ([Item], _ isSearching: Bool) -> Content

    @State private var searchText = ""

    private var filteredItems: [Item] {
        guard !searchText.isEmpty else { return items }
        return items.filter { $0[keyPath: searchKey].localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        content(filteredItems, !searchText.isEmpty)
            .searchable(text: $searchText, prompt: Text("搜索"))
    }
}
