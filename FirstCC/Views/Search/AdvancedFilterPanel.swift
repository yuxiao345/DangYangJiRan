import SwiftUI
@preconcurrency import CoreData

/// Advanced filter panel with expandable sections
struct AdvancedFilterPanel: View {
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

    @State private var presentedSheet: FilterSheetType?

    // Shared numpad state
    @State private var showNumpad = false
    @State private var numpadText = ""
    @State private var activeAmountField: AmountFieldTarget?

    // Date sheet state
    @State private var showDateSheet = false
    @State private var activeDateTarget: DateTarget?
    @State private var dateSheetSelection = Date()

    private enum FilterSheetType: Identifiable {
        case category, member, merchant, project
        var id: Self { self }
    }

    private enum AmountFieldTarget {
        case min, max
    }

    private enum DateTarget {
        case from, to
    }

    var body: some View {
        VStack(spacing: 6) {
            // Header
            Button {
                if !isExpanded {
                    #if os(iOS)
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    #endif
                }
                withAnimation(.easeInOut(duration: 0.25)) { isExpanded.toggle() }
            } label: {
                HStack {
                    Label("高级筛选", systemImage: "line.3.horizontal.decrease")
                        .foregroundStyle(.secondary)
                    Spacer()
                    if !isExpanded {
                        activeSummary
                    }
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            // Expanded content
            if isExpanded {
                filterContent
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.designGlassBg)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
        )
        .onAppear { loadData() }
        .onChange(of: appContainer.currentLedger?.id) { _, _ in loadData() }
        .sheet(item: $presentedSheet) { sheet in
            switch sheet {
            case .category: categoryPicker
            case .member: memberPicker
            case .merchant: merchantPicker
            case .project: projectPicker
            }
        }
        .sheet(isPresented: $showDateSheet) {
            dateSheetView
                .presentationDetents([.medium])
        }
    }

    // MARK: - Filter Content

    private var filterContent: some View {
        VStack(spacing: 14) {
            // Date range
            dateRangeSection

            // Amount range — shared numpad
            amountRangeSection

            // Category
            if !categories.isEmpty {
                MultiSelectChipRow(
                    title: "分类",
                    items: categories,
                    itemIcon: { $0.iconName },
                    itemColor: { Color(hex: $0.colorHex) },
                    recentKey: "recent_category_filter",
                    selectedIDs: $selectedCategoryIDs,
                    onMore: { presentedSheet = .category }
                )
            }

            // Member
            if !members.isEmpty {
                MultiSelectChipRow(
                    title: "成员",
                    items: members,
                    itemIcon: { _ in "person.fill" },
                    itemColor: { _ in .designAccentGreen },
                    recentKey: "recent_member_filter",
                    selectedIDs: $selectedMemberIDs,
                    onMore: { presentedSheet = .member }
                )
            }

            // Merchant
            if !merchants.isEmpty {
                MultiSelectChipRow(
                    title: "商家",
                    items: merchants,
                    itemIcon: { _ in "storefront.fill" },
                    itemColor: { _ in .designAccentRed },
                    recentKey: "recent_merchant_filter",
                    selectedIDs: $selectedMerchantIDs,
                    onMore: { presentedSheet = .merchant }
                )
            }

            // Project
            if !projects.isEmpty {
                MultiSelectChipRow(
                    title: "项目",
                    items: projects,
                    itemIcon: { _ in "folder.fill" },
                    itemColor: { _ in .designAccentPurple },
                    recentKey: "recent_project_filter",
                    selectedIDs: $selectedProjectIDs,
                    onMore: { presentedSheet = .project }
                )
            }

            // Keyword
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("关键词", text: $keyword)
            }
            .padding(8)
            .background {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.designSurfaceContainer)
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
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.designErrorContainer)
                        )
                        .foregroundStyle(Color.designOnErrorContainer)
                }
                .buttonStyle(.plain)

                if let onSave = onSave {
                    Button {
                        onSave()
                    } label: {
                        Image(systemName: "bookmark")
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
        let today = Date()
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
            // Quick presets
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(datePresets, id: \.0) { preset in
                        let isActive = dateFrom == preset.1.lowerBound && dateTo == preset.1.upperBound
                        Button {
                            if isActive { dateFrom = nil; dateTo = nil }
                            else { dateFrom = preset.1.lowerBound; dateTo = preset.1.upperBound }
                        } label: {
                            Text(preset.0)
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
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
            // From / To
            HStack(spacing: 8) {
                dateButton(String(localized: "开始"), date: $dateFrom, target: .from)
                Text("至").font(.caption).foregroundStyle(.secondary)
                dateButton(String(localized: "结束"), date: $dateTo, target: .to)
            }
        }
    }

    private func dateButton(_ label: String, date: Binding<Date?>, target: DateTarget) -> some View {
        Button {
            if let d = date.wrappedValue { dateSheetSelection = d }
            activeDateTarget = target
            showDateSheet = true
        } label: {
            HStack {
                if let d = date.wrappedValue {
                    Text(d.formatted(date: .numeric, time: .omitted))
                        .font(.caption)
                        .foregroundStyle(.primary)
                } else {
                    Text(label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Image(systemName: "calendar")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(date.wrappedValue != nil
                        ? Color.designPrimaryFixedDim.opacity(0.08)
                        : Color.designSurfaceContainer)
            )
        }
        .buttonStyle(.plain)
    }

    private var dateSheetView: some View {
        NavigationStack {
            VStack {
                DatePicker("", selection: $dateSheetSelection, displayedComponents: [.date])
                    .datePickerStyle(.graphical)
                    .padding()
                Spacer()
            }
            .navigationTitle(activeDateTarget == .from ? String(localized: "开始日期") : String(localized: "结束日期"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { showDateSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("确认") {
                        switch activeDateTarget {
                        case .from: dateFrom = dateSheetSelection
                        case .to: dateTo = dateSheetSelection
                        case .none: break
                        }
                        showDateSheet = false
                    }
                }
            }
        }
    }

    // MARK: - Amount Section

    private var amountRangeSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("金额").font(.designLabel).foregroundStyle(Color.designPrimary.opacity(0.8))
            HStack(spacing: 8) {
                amountButton(String(localized: "最低"), value: $amountMin, target: .min)
                Text("至")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                amountButton(String(localized: "最高"), value: $amountMax, target: .max)
            }
        }
        .sheet(isPresented: $showNumpad) {
            sharedNumpadSheet
                .presentationDetents([.medium])
        }
    }

    private func amountButton(_ label: String, value: Binding<Decimal?>, target: AmountFieldTarget) -> some View {
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
                        Text(CurrencyFormatter.formatDecimal(amount: v, currencyCode: appContainer.currentCurrencyCode))
                            .font(.caption)
                            .foregroundStyle(.primary)
                    } else {
                        Text(label)
                            .font(.caption)
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

    private var sharedNumpadSheet: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Spacer()
                // Live display
                HStack {
                    Text("¥")
                        .foregroundStyle(.secondary)
                    Text(numpadText.isEmpty ? "0" : numpadText)
                        .font(.system(size: 32, weight: .medium, design: .monospaced))
                }
                .padding(.bottom, 8)
                // Shared NumpadGrid
                NumpadGrid(
                    onDigit: { appendNumpadDigit($0) },
                    onDot: appendNumpadDot,
                    onDelete: numpadBackspace
                )
                HStack(spacing: 12) {
                    Button {
                        numpadText = ""
                    } label: {
                        Text("清空")
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.designSurfaceContainer)
                            )
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)

                    Button {
                        if numpadText.hasPrefix("-") {
                            numpadText.removeFirst()
                        } else {
                            numpadText = "-" + numpadText
                        }
                    } label: {
                        Text("+/-")
                            .font(.system(size: 16, design: .monospaced))
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.designSurfaceContainer)
                            )
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal)
            }
            .navigationTitle(activeAmountField == .min ? String(localized: "最低金额") : String(localized: "最高金额"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { showNumpad = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("确认") {
                        let parsed = Decimal(string: numpadText.filter { $0.isNumber || $0 == "." || $0 == "-" }) ?? 0
                        switch activeAmountField {
                        case .min: amountMin = parsed
                        case .max: amountMax = parsed
                        case .none: break
                        }
                        showNumpad = false
                    }
                }
            }
        }
    }

    private func appendNumpadDigit(_ digit: Int) {
        if let dotIndex = numpadText.firstIndex(of: ".") {
            let decimals = numpadText[dotIndex...].dropFirst()
            if decimals.count >= 2 { return }
        }
        if numpadText == "0" { numpadText = "\(digit)" }
        else { numpadText += "\(digit)" }
    }

    private func appendNumpadDot() {
        if numpadText.contains(".") { return }
        if numpadText.isEmpty { numpadText = "0." }
        else { numpadText += "." }
    }

    private func numpadBackspace() {
        if numpadText.count <= 1 { numpadText = "" }
        else { numpadText.removeLast() }
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
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    // MARK: - Pickers

    private var categoryPicker: some View {
        MultiSelectPickerView(
            title: String(localized: "分类"), items: categories,
            itemLabel: { $0.name }, itemIcon: { $0.iconName },
            itemColor: { Color(hex: $0.colorHex) },
            recentKey: "recent_category_filter",
            indentLevel: { item in var d = 0; var p = item.parent; while p != nil { d += 1; p = p?.parent }; return d },
            childrenProvider: { Array($0.children ?? []) },
            selection: $selectedCategoryIDs
        )
    }

    private var memberPicker: some View {
        MultiSelectPickerView(
            title: String(localized: "成员"), items: members,
            itemLabel: { $0.name }, itemIcon: { _ in "person.fill" },
            itemColor: { _ in .designAccentGreen },
            recentKey: "recent_member_filter",
            selection: $selectedMemberIDs
        )
    }

    private var merchantPicker: some View {
        MultiSelectPickerView(
            title: String(localized: "商家"), items: merchants,
            itemLabel: { $0.name }, itemIcon: { _ in "storefront.fill" },
            itemColor: { _ in .designAccentRed },
            recentKey: "recent_merchant_filter",
            selection: $selectedMerchantIDs
        )
    }

    private var projectPicker: some View {
        MultiSelectPickerView(
            title: String(localized: "项目"), items: projects,
            itemLabel: { $0.name }, itemIcon: { _ in "folder.fill" },
            itemColor: { _ in .designAccentPurple },
            recentKey: "recent_project_filter",
            selection: $selectedProjectIDs
        )
    }

    // MARK: - Data Loading

    private func loadData() {
        guard let ledger = appContainer.currentLedger else { return }
        categories = (try? appContainer.categoryService.fetchCategories(for: ledger, type: nil, context: modelContext)) ?? []
        members = (try? appContainer.memberService.fetchMembers(for: ledger, context: modelContext))?.filter { $0.isActive } ?? []
        merchants = (try? appContainer.merchantService.fetchMerchants(for: ledger, context: modelContext))?.filter { $0.isActive } ?? []
        projects = (try? appContainer.projectService.fetchProjects(for: ledger, context: modelContext))?.filter { $0.isActive } ?? []
    }
}
