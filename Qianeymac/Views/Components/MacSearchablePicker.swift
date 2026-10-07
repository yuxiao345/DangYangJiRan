import SwiftUI

/// Mac 记账表单统一的选择器：原生 `NSPopUpButton` 外壳 + 弹出的搜索列表。
///
/// **为什么不让原生菜单直接展开**：原生菜单结构上放不下输入框，条目一多只能靠滚动翻找。
/// 这里保留弹出按钮的外壳（边框、箭头、按下反馈、深浅色全由 AppKit 画），
/// 点击被拦下改为呈现 `.popover`：列表用 `depth` 缩进保留层级，
/// 搜索命中 中文子串 / 本地化名（英文）子串 / 全拼 / 首字母。
///
/// 层级字段（分类）传 `depth` + `parentId`，得到缩进与「最近使用」按家族归并；
/// 扁平字段（账户/成员/商家/项目）不传，即 depth 恒 0、无父子关系。
/// 已选值只喂 `selection`，与「无」行（清除）互斥。
struct MacSearchablePicker<T: Identifiable & Hashable>: View {
    @Binding var selection: T?
    let items: [T]
    /// 原始名。显示时是否查表由 `localizesName` 决定；拼音搜索键始终由它生成
    /// （查表会把中文名换成英文，拼音就无从谈起了）。
    let name: (T) -> String
    /// 是否把 `name` 当 String Catalog 的 key 查表后再显示。**默认 false。**
    ///
    /// 只有内置分类名同时是 catalog 的 key（`餐饮` → "Dining"）。账户/成员/商家/项目的
    /// 名字全是用户数据，一旦查表就会撞上同名 UI 标签——账户取名「现金」在英文环境下
    /// 会显示成 "Cash"，商家取名「红包」会显示成 "Red Envelope"，都是用户没打过的名字。
    let localizesName: Bool
    let icon: (T) -> String
    let color: (T) -> Color
    let depth: (T) -> Int
    let parentId: (T) -> T.ID?
    let recentKey: String?
    let onSelect: (T) -> Void

    @State private var isPresented = false
    @State private var searchText = ""
    @State private var highlightIndex = 0
    @State private var recentIDs: [String] = []
    /// 拼音搜索键缓存：过滤每次按键都跑，转换本身不便宜，所以只建一次。
    @State private var searchKeys: [T.ID: PinyinHelper.SearchKey] = [:]
    @FocusState private var searchFocused: Bool

    init(
        selection: Binding<T?>,
        items: [T],
        name: @escaping (T) -> String,
        localizesName: Bool = false,
        icon: @escaping (T) -> String,
        color: @escaping (T) -> Color = { _ in .secondary },
        depth: @escaping (T) -> Int = { _ in 0 },
        parentId: @escaping (T) -> T.ID? = { _ in nil },
        recentKey: String? = nil,
        onSelect: @escaping (T) -> Void = { _ in }
    ) {
        self._selection = selection
        self.items = items
        self.name = name
        self.localizesName = localizesName
        self.icon = icon
        self.color = color
        self.depth = depth
        self.parentId = parentId
        self.recentKey = recentKey
        self.onSelect = onSelect
    }

    // MARK: - Body

    var body: some View {
        // 触发按钮是**原生 NSPopUpButton**（见 `SearchablePopUpButton`）：只借它的外壳，
        // 点击被拦下、不弹菜单，由下面的 popover 呈现可搜索列表。
        // 外壳因此与同表单「成员/商家/项目」源自同一控件，不存在调参对齐问题。
        SearchablePopUpButtonView(
            title: selection.map(displayName) ?? String(localized: "无"),
            icon: selection.map { (name: icon($0), color: color($0)) },
            onActivate: { isPresented = true }
        )
        .popover(isPresented: $isPresented) { popoverContent }
    }

    // MARK: - Popover

    private var popoverContent: some View {
        VStack(spacing: 0) {
            searchBar
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(rows) { row in rowView(row) }
                    }
                    .padding(.vertical, 4)
                }
                .frame(height: 320)
                .onChange(of: highlightIndex) { _, new in
                    guard rows.indices.contains(new) else { return }
                    withAnimation(.easeOut(duration: 0.12)) {
                        proxy.scrollTo(rows[new].id, anchor: .center)
                    }
                }
            }
        }
        .frame(width: 300)
        .onAppear(perform: prepareForPresentation)
        // 只在原高亮项已被过滤掉时才移动。无条件归零会把 prepareForPresentation 里
        // 刚设好的「高亮当前已选项」冲掉（清空 searchText 本身就会触发本回调），
        // 结果重开时高亮落在「无」上而不是当前分类。
        .onChange(of: searchText) { _, _ in
            let navigable = navigableRowIDs()
            if !navigable.contains(highlightIndex) {
                highlightIndex = navigable.first ?? 0
            }
        }
        .onKeyPress(.upArrow) { move(-1); return .handled }
        .onKeyPress(.downArrow) { move(1); return .handled }
        .onKeyPress(.escape) { isPresented = false; return .handled }
    }

    private var searchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            TextField("搜索", text: $searchText)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .onSubmit { commitHighlighted() }
                .onKeyPress(.upArrow) { move(-1); return .handled }
                .onKeyPress(.downArrow) { move(1); return .handled }
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    // MARK: - Rows

    private struct PickerRow: Identifiable {
        enum Kind {
            case header(LocalizedStringKey)
            case none
            case item(T)
            case empty
        }
        let id: Int
        let kind: Kind
    }

    private var rows: [PickerRow] {
        var result: [PickerRow] = []
        func append(_ kind: PickerRow.Kind) {
            result.append(PickerRow(id: result.count, kind: kind))
        }
        append(.none)
        if searchText.isEmpty {
            let recent = recentItems
            if !recent.isEmpty {
                append(.header("最近使用"))
                for item in recent { append(.item(item)) }
            }
            append(.header("全部"))
            for item in filteredItems { append(.item(item)) }
        } else {
            append(.header("搜索结果"))
            if filteredItems.isEmpty {
                append(.empty)
            } else {
                for item in filteredItems { append(.item(item)) }
            }
        }
        return result
    }

    @ViewBuilder
    private func rowView(_ row: PickerRow) -> some View {
        switch row.kind {
        case .header(let title):
            MacSearchablePickerSectionHeader(title: title)
        case .empty:
            Text(String(localized: "无匹配结果"))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
        case .none:
            MacSearchablePickerRow<T>(
                item: nil, displayName: displayName, icon: icon, color: color, depth: depth,
                isSelected: selection == nil, isHighlighted: highlightIndex == row.id
            ) { commit(nil) }
        case .item(let item):
            MacSearchablePickerRow<T>(
                item: item, displayName: displayName, icon: icon, color: color, depth: depth,
                isSelected: item.id == selection?.id, isHighlighted: highlightIndex == row.id
            ) { commit(item) }
        }
    }

    // MARK: - Filtering

    private var filteredItems: [T] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return items }
        var included = Set(items.filter { matches($0, query) }.map(\.id))
        // 命中的父分类要带上子分类，否则搜到「餐饮饮食」却看不到它下面的具体分类
        // （与 iOS `SearchablePickerView.filteredItems` 同一语义）
        for item in items where included.contains(item.id) {
            for child in items where parentId(child) == item.id {
                included.insert(child.id)
            }
        }
        return items.filter { included.contains($0.id) }
    }

    private func matches(_ item: T, _ query: String) -> Bool {
        if displayName(item).localizedStandardContains(query) { return true }
        if let key = searchKeys[item.id] { return key.matches(query) }
        return name(item).lowercased().contains(query)
    }

    /// 最近使用：按 `recentIDs` 的最近顺序逐项带出，且**整家族**带出
    /// （父分类先出，再出它的后代）——子分类单独出现时缩进无从解释。
    ///
    /// 注意顺序是「最近优先」而不是「层级位置优先」：家族一大（≥4 个子分类）时，
    /// 若按位置截断，用户刚点过的那一项会被挤到第 5 位之后截掉，
    /// 「最近使用」会显示一堆没用过的兄弟分类，唯独没有用过的那一个。
    private var recentItems: [T] {
        guard !recentIDs.isEmpty, !items.isEmpty else { return [] }
        let byID = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var rootOf: [T.ID: T.ID] = [:]
        for item in items {
            var current = item
            var hops = 0
            while let parent = parentId(current), let parentItem = byID[parent], hops <= 8 {
                current = parentItem  // hops 上限防御环：CoreData 关系理论上无环，出错时不要死循环
                hops += 1
            }
            rootOf[item.id] = current.id
        }

        var result: [T] = []
        var emitted = Set<T.ID>()
        for id in recentIDs {
            guard let picked = items.first(where: { "\($0.id)" == id }),
                  let root = rootOf[picked.id] else { continue }
            let family = items.filter { rootOf[$0.id] == root }
            for item in family.filter({ $0.id == root }) + family.filter({ $0.id != root })
            where !emitted.contains(item.id) {
                result.append(item)
                emitted.insert(item.id)
            }
            if result.count >= recentLimit { break }
        }
        return Array(result.prefix(recentLimit))
    }

    private let recentLimit = 5

    // MARK: - Highlight & Commit

    private func navigableRowIDs() -> [Int] {
        rows.compactMap { row in
            if case .header = row.kind { return nil }
            if case .empty = row.kind { return nil }
            return row.id
        }
    }

    private func move(_ delta: Int) {
        let nav = navigableRowIDs()
        guard !nav.isEmpty else { return }
        guard let position = nav.firstIndex(of: highlightIndex) else {
            highlightIndex = delta < 0 ? nav[nav.count - 1] : nav[0]
            return
        }
        highlightIndex = nav[(position + delta + nav.count) % nav.count]
    }

    private func commitHighlighted() {
        guard rows.indices.contains(highlightIndex) else { return }
        switch rows[highlightIndex].kind {
        case .item(let item): commit(item)
        case .none: commit(nil)
        case .header, .empty: break
        }
    }

    private func commit(_ item: T?) {
        selection = item
        if let item {
            saveRecent(item)
            onSelect(item)
        }
        isPresented = false
    }

    // MARK: - Presentation Lifecycle

    private func prepareForPresentation() {
        searchText = ""
        loadRecent()
        buildSearchKeysIfNeeded()
        let selectedRow = selection.flatMap { sel in rows.first { row in
            if case .item(let item) = row.kind { return item.id == sel.id }
            return false
        } }
        highlightIndex = selectedRow?.id ?? rows.first?.id ?? 0
        searchFocused = true
    }

    private func buildSearchKeysIfNeeded() {
        guard !items.isEmpty else { return }
        // 不能只判 `isEmpty`：用户先开「支出」再切成「收入」时 items 换了一批，
        // 只补空缺会让新列表的拼音搜索静默退化成中文子串匹配。
        guard items.contains(where: { searchKeys[$0.id] == nil }) else { return }
        let liveIDs = Set(items.map(\.id))
        var keys = searchKeys.filter { liveIDs.contains($0.key) }  // 丢弃上一批的 key
        for item in items where keys[item.id] == nil {
            keys[item.id] = PinyinHelper.SearchKey(name(item))
        }
        searchKeys = keys
    }

    private func loadRecent() {
        guard let recentKey else { return }
        recentIDs = UserDefaults.standard.stringArray(forKey: recentKey) ?? []
    }

    private func saveRecent(_ item: T) {
        guard let recentKey else { return }
        let id = "\(item.id)"
        var ids = recentIDs.filter { $0 != id }
        ids.insert(id, at: 0)
        recentIDs = Array(ids.prefix(8))
        UserDefaults.standard.set(recentIDs, forKey: recentKey)
    }

    private func displayName(_ item: T) -> String {
        localizesName ? NSLocalizedString(name(item), comment: "") : name(item)
    }
}
