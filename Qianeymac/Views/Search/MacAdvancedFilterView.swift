import SwiftUI
@preconcurrency import CoreData

/// Mac-native advanced filter panel — popover-based pickers instead of iOS sheets
struct MacAdvancedFilterView: View {
    @Environment(AppContainer.self) private var appContainer
    @Environment(\.managedObjectContext) private var modelContext

    @Binding var isExpanded: Bool

    @Binding var selectedCategoryIDs: Set<UUID>
    @Binding var selectedMemberIDs: Set<UUID>
    @Binding var selectedMerchantIDs: Set<UUID>
    @Binding var selectedProjectIDs: Set<UUID>
    @Binding var dateFrom: Date?
    @Binding var dateTo: Date?
    @Binding var amountMin: Decimal?
    @Binding var amountMax: Decimal?
    @Binding var keyword: String

    var onApply: () -> Void
    var onSave: (() -> Void)?

    @State private var categories: [Category] = []
    @State private var members: [Member] = []
    @State private var merchants: [Merchant] = []
    @State private var projects: [Project] = []

    // Numpad state
    @State private var showNumpad = false
    @State private var numpadText = ""
    @State private var activeAmountField: AmountFieldTarget?
    @State private var amountError: String?
    @State private var showErrorAlert: Bool = false

    // Multi-select popover state — separate bool per type to avoid timing issues
    @State private var showCategoryPicker = false
    @State private var showMemberPicker = false
    @State private var showMerchantPicker = false
    @State private var showProjectPicker = false

    private enum AmountFieldTarget { case min, max }

    var body: some View {
        VStack(spacing: 6) {
            // Header
            Button {
                withAnimation(.easeInOut(duration: 0.25)) { isExpanded.toggle() }
            } label: {
                HStack {
                    Label(String(localized: "高级筛选"), systemImage: "line.3.horizontal.decrease")
                        .foregroundStyle(.secondary)
                        .font(.designBodyMedium)
                    Spacer()
                    if !isExpanded { activeSummary }
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                filterContent
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.designGlassBg)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
        }
        .onAppear { loadData() }
        .onChange(of: appContainer.currentLedger?.id) { _, _ in loadData() }
        .alert(amountError ?? "", isPresented: $showErrorAlert) {
        } message: {
            Text(amountError ?? "")
        }
        .popover(isPresented: $showCategoryPicker, arrowEdge: .bottom) {
            selectionPopover(title: String(localized: "选择分类"), items: categories, itemIcon: { $0.iconName }, itemColor: { Color(hex: $0.colorHex ?? "#999999") }, isSelected: { selectedCategoryIDs.contains($0.id) }, indent: { categoryIndent($0) }, onToggle: { selectedCategoryIDs.toggle($0.id) }, onClear: { selectedCategoryIDs.removeAll() }, onDismiss: { showCategoryPicker = false })
                .frame(width: 280, height: 400)
        }
        .popover(isPresented: $showMemberPicker, arrowEdge: .bottom) {
            selectionPopover(title: String(localized: "选择成员"), items: members, itemIcon: { $0.avatar }, itemColor: { _ in .designAccentGreen }, isSelected: { selectedMemberIDs.contains($0.id) }, indent: { _ in 0 }, onToggle: { selectedMemberIDs.toggle($0.id) }, onClear: { selectedMemberIDs.removeAll() }, onDismiss: { showMemberPicker = false })
                .frame(width: 280, height: 400)
        }
        .popover(isPresented: $showMerchantPicker, arrowEdge: .bottom) {
            selectionPopover(title: String(localized: "选择商家"), items: merchants, itemIcon: { _ in "bag.fill" }, itemColor: { _ in .orange }, isSelected: { selectedMerchantIDs.contains($0.id) }, indent: { _ in 0 }, onToggle: { selectedMerchantIDs.toggle($0.id) }, onClear: { selectedMerchantIDs.removeAll() }, onDismiss: { showMerchantPicker = false })
                .frame(width: 280, height: 400)
        }
        .popover(isPresented: $showProjectPicker, arrowEdge: .bottom) {
            selectionPopover(title: String(localized: "选择项目"), items: projects, itemIcon: { _ in "folder.fill" }, itemColor: { _ in .designAccentPurple }, isSelected: { selectedProjectIDs.contains($0.id) }, indent: { _ in 0 }, onToggle: { selectedProjectIDs.toggle($0.id) }, onClear: { selectedProjectIDs.removeAll() }, onDismiss: { showProjectPicker = false })
                .frame(width: 280, height: 400)
        }
    }

    // MARK: - Filter Content

    private var filterContent: some View {
        VStack(spacing: 14) {
            dateRangeSection
            amountRangeSection

            if !categories.isEmpty {
                MultiSelectChipRow(
                    title: "分类",
                    items: categories,
                    itemIcon: { $0.iconName },
                    itemColor: { Color(hex: $0.colorHex) },
                    recentKey: "recent_category_filter",
                    selectedIDs: $selectedCategoryIDs,
                    onMore: { showCategoryPicker = true }
                )
            }

            if !members.isEmpty {
                MultiSelectChipRow(
                    title: "成员",
                    items: members,
                    itemIcon: { _ in "person.fill" },
                    itemColor: { _ in .designAccentGreen },
                    recentKey: "recent_member_filter",
                    selectedIDs: $selectedMemberIDs,
                    onMore: { showMemberPicker = true }
                )
            }

            if !merchants.isEmpty {
                MultiSelectChipRow(
                    title: "商家",
                    items: merchants,
                    itemIcon: { _ in "bag.fill" },
                    itemColor: { _ in .orange },
                    recentKey: "recent_merchant_filter",
                    selectedIDs: $selectedMerchantIDs,
                    onMore: { showMerchantPicker = true }
                )
            }

            if !projects.isEmpty {
                MultiSelectChipRow(
                    title: "项目",
                    items: projects,
                    itemIcon: { _ in "folder.fill" },
                    itemColor: { _ in .designAccentPurple },
                    recentKey: "recent_project_filter",
                    selectedIDs: $selectedProjectIDs,
                    onMore: { showProjectPicker = true }
                )
            }

            // Keyword
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 12))
                TextField(String(localized: "关键词"), text: $keyword)
                    .textFieldStyle(.roundedBorder)
                    .font(.designBodySmall)
            }

            // Actions
            HStack(spacing: 12) {
                Button {
                    selectedCategoryIDs.removeAll()
                    selectedMemberIDs.removeAll()
                    selectedMerchantIDs.removeAll()
                    selectedProjectIDs.removeAll()
                    dateFrom = nil; dateTo = nil
                    amountMin = nil; amountMax = nil
                    keyword = ""
                    withAnimation(.easeInOut(duration: 0.25)) { isExpanded = false }
                    onApply()
                } label: {
                    Text("清除所有")
                        .font(.designBodyMedium)
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.designErrorContainer)
                        )
                        .foregroundStyle(Color.designOnErrorContainer)
                }
                .buttonStyle(.plain)

                if onSave != nil {
                    Button { onSave?() } label: {
                        Image(systemName: "bookmark")
                            .font(.system(size: 14))
                            .frame(width: 36, height: 36)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.designPrimaryContainer.opacity(0.1))
                            )
                            .foregroundStyle(Color.designPrimaryContainer)
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    withAnimation(.easeInOut(duration: 0.25)) { isExpanded = false }
                    onApply()
                } label: {
                    Text("应用")
                        .font(.designBodyMedium.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.designPrimaryContainer)
                        )
                        .foregroundStyle(Color.designOnPrimaryContainer)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Date Section

    private let datePresets: [(String, Range<Date>)] = {
        let cal = Calendar.current
        let today = Date.now
        let startOfToday = today.startOfDay
        let tomorrowStart = startOfToday.adding(.day, value: 1)
        return [
            (String(localized: "今天"), startOfToday..<tomorrowStart),
            (String(localized: "本周"), today.startOfWeek..<today.startOfWeek.adding(.day, value: 7)),
            (String(localized: "本月"), today.startOfMonth..<today.startOfMonth.adding(.month, value: 1)),
            (String(localized: "今年"), today.startOfYear..<today.startOfYear.adding(.year, value: 1)),
        ]
    }()

    private var dateRangeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("日期").font(.designLabel).foregroundStyle(Color.designPrimary.opacity(0.8))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(datePresets, id: \.0) { preset in
                        let isActive = dateFrom == preset.1.lowerBound && dateTo == preset.1.upperBound
                        Button {
                            if isActive { dateFrom = nil; dateTo = nil }
                            else { dateFrom = preset.1.lowerBound; dateTo = preset.1.upperBound }
                        } label: {
                            Text(preset.0)
                                .font(.designBodySmall)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(
                                    Capsule().fill(isActive ? Color.designPrimaryFixedDim.opacity(0.15) : Color.designSurfaceContainer)
                                )
                                .overlay(
                                    Capsule().stroke(isActive ? Color.designPrimaryFixedDim.opacity(0.5) : Color.clear, lineWidth: 1)
                                )
                                .foregroundStyle(isActive ? Color.designPrimaryFixedDim : .secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            HStack(spacing: 8) {
                optionalDatePicker(label: String(localized: "开始"), date: $dateFrom)
                Text("至").font(.designBodySmall).foregroundStyle(.secondary)
                optionalDatePicker(label: String(localized: "结束"), date: $dateTo)
            }
        }
    }

    @ViewBuilder
    private func optionalDatePicker(label: String, date: Binding<Date?>) -> some View {
        let proxyBinding = Binding<Date>(
            get: { date.wrappedValue ?? Date() },
            set: { date.wrappedValue = $0 }
        )
        HStack(spacing: 0) {
            DatePicker(
                label,
                selection: proxyBinding,
                displayedComponents: [.date]
            )
            .datePickerStyle(.field)
            .labelsHidden()
            .font(.designBodySmall)

            if date.wrappedValue != nil {
                Button {
                    date.wrappedValue = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 6)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Amount Section

    private var amountRangeSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("金额").font(.designLabel).foregroundStyle(Color.designPrimary.opacity(0.8))
            HStack(spacing: 8) {
                amountField(String(localized: "最低"), value: $amountMin, target: .min)
                Text("至")
                    .font(.designBodySmall)
                    .foregroundStyle(.secondary)
                amountField(String(localized: "最高"), value: $amountMax, target: .max)
            }

            // Inline numpad
            if showNumpad {
                VStack(spacing: 8) {
                    HStack {
                        Spacer()
                        Text("¥")
                            .foregroundStyle(.secondary)
                            .font(.designBodyMedium)
                        Text(numpadText.isEmpty ? "0" : numpadText)
                            .font(.system(size: 28, weight: .medium, design: .monospaced))
                            .foregroundStyle(.primary)
                    }

                    NumpadGrid(
                        onDigit: { appendDigit($0) },
                        onDot: appendDot,
                        onDelete: numpadBackspace,
                        onClear: { numpadText = "" }
                    )

                    Button("确认") {
                        let parsed = Decimal(string: numpadText.filter { $0.isNumber || $0 == "." || $0 == "-" }) ?? 0
                        switch activeAmountField {
                        case .min:
                            if let max = amountMax, parsed > max {
                                amountError = String(localized: "最低金额不能高于最高金额"); showErrorAlert = true; return
                            }
                            amountMin = parsed
                        case .max:
                            if let min = amountMin, parsed < min {
                                amountError = String(localized: "最高金额不能低于最低金额"); showErrorAlert = true; return
                            }
                            amountMax = parsed
                        case .none: break
                        }
                        showNumpad = false
                    }
                    .font(.designBodyMedium.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .background(Capsule().fill(Color.designPrimaryContainer.opacity(0.85)))
                    .foregroundStyle(Color.designOnPrimaryContainer)
                    .buttonStyle(.plain)
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.designSurfaceContainer.opacity(0.5))
                )
            }
        }
    }

    private func amountField(_ label: String, value: Binding<Decimal?>, target: AmountFieldTarget) -> some View {
        let hasValue = value.wrappedValue != nil && value.wrappedValue != 0
        return HStack(spacing: 0) {
            Button {
                activeAmountField = target
                let v = value.wrappedValue
                numpadText = (v != nil && v != 0) ? "\(v!)" : ""
                showNumpad = true
            } label: {
                HStack {
                    if let v = value.wrappedValue, v != 0 {
                        Text("¥\(v)")
                            .font(.designBodySmall)
                            .foregroundStyle(.primary)
                    } else {
                        Text(label)
                            .font(.designBodySmall)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)

            if hasValue {
                Button {
                    value.wrappedValue = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .padding(.trailing, 8)
                }
                .buttonStyle(.plain)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(hasValue ? Color.designPrimaryFixedDim.opacity(0.08) : Color.designSurfaceContainer)
        )
    }

    // Numpad digit helpers
    private func appendDigit(_ d: Int) {
        if let dotIdx = numpadText.firstIndex(of: ".") {
            let decimals = numpadText[dotIdx...].dropFirst()
            guard decimals.count < 2 else { return }
        }
        numpadText += "\(d)"
    }

    private func appendDot() {
        if !numpadText.contains(".") { numpadText += numpadText.isEmpty ? "0." : "." }
    }

    private func numpadBackspace() {
        if !numpadText.isEmpty { numpadText.removeLast() }
    }

    // MARK: - Selection Popover

    /// Generic multi-select popover content. Each popover uses its own items + selection bindings,
    /// avoiding the timing issue of a shared `activeMultiSelectType` state.
    private func selectionPopover<Item: Identifiable>(
        title: String,
        items: [Item],
        itemIcon: @escaping (Item) -> String,
        itemColor: @escaping (Item) -> Color,
        isSelected: @escaping (Item) -> Bool,
        indent: @escaping (Item) -> Int,
        onToggle: @escaping (Item) -> Void,
        onClear: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) -> some View where Item.ID == UUID {
        VStack(spacing: 0) {
            Text(title)
                .font(.designHeadlineMedium)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

            Divider()

            ScrollView {
                VStack(spacing: 2) {
                    ForEach(items) { item in
                        selectionRow(
                            icon: itemIcon(item),
                            name: nameOf(item),
                            color: itemColor(item),
                            isSelected: isSelected(item),
                            indent: indent(item)
                        ) {
                            onToggle(item)
                        }
                    }
                }
                .padding(8)
            }

            Divider()

            HStack {
                Button("清除") { onClear() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("完成") { onDismiss() }
                    .buttonStyle(.plain)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.designAccentGreen)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    /// Extract display name from item via NameProviding, falling back to "\(id)".
    private func nameOf<Item: Identifiable>(_ item: Item) -> String {
        if let np = item as? (any NameProviding) { return np.name }
        return "\(item.id)"
    }

    private func selectionRow(
        icon: String, name: String, color: Color,
        isSelected: Bool, indent: Int = 0,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.designAccentGreen : .secondary)
                    .font(.system(size: 14))
                Image(systemName: icon)
                    .foregroundStyle(color)
                    .frame(width: 20)
                Text(name)
                    .font(.designBodyMedium)
                    .foregroundStyle(.primary)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .padding(.leading, CGFloat(indent * 16))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func categoryIndent(_ cat: Category) -> Int {
        var d = 0
        var p = cat.parent
        while p != nil { d += 1; p = p?.parent }
        return d
    }

    // MARK: - Summary (collapsed)

    @ViewBuilder
    private var activeSummary: some View {
        let parts: [String] = {
            var p: [String] = []
            if dateFrom != nil || dateTo != nil { p.append(String(localized: "日期")) }
            if amountMin != nil || amountMax != nil { p.append(String(localized: "金额")) }
            if !selectedCategoryIDs.isEmpty { p.append(String(localized: "分类(\(selectedCategoryIDs.count))")) }
            if !selectedMemberIDs.isEmpty { p.append(String(localized: "成员(\(selectedMemberIDs.count))")) }
            if !selectedMerchantIDs.isEmpty { p.append(String(localized: "商家(\(selectedMerchantIDs.count))")) }
            if !selectedProjectIDs.isEmpty { p.append(String(localized: "项目(\(selectedProjectIDs.count))")) }
            if !keyword.isEmpty { p.append(String(localized: "关键词")) }
            return p
        }()

        if !parts.isEmpty {
            Text(parts.joined(separator: " · "))
                .font(.designBodySmall)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    // MARK: - Data Loading

    private func loadData() {
        guard let ledger = appContainer.currentLedger else { return }
        categories = (try? appContainer.categoryService.fetchCategories(for: ledger, type: nil, context: modelContext)) ?? []
        members = (try? appContainer.memberService.fetchMembers(for: ledger, context: modelContext))?.filter(\.isActive) ?? []
        merchants = (try? appContainer.merchantService.fetchMerchants(for: ledger, context: modelContext))?.filter(\.isActive) ?? []
        projects = (try? appContainer.projectService.fetchProjects(for: ledger, context: modelContext))?.filter(\.isActive) ?? []
    }
}
