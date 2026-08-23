import SwiftUI
import Charts

struct CategoryPieChartView: View {
    let categories: [CategoryExpenseItem]
    /// Optional: override donut data (e.g., aggregated for dimension overview). nil = use categories.
    var donutCategories: [CategoryExpenseItem]? = nil
    /// Optional: max visible items in list. Excess items hidden with "more" indicator.
    var maxListItems: Int? = nil
    let totalExpense: Decimal
    let centerTitle: String
    let isDrilledDown: Bool
    let onCategoryTap: (UUID) -> Void
    let onCenterTap: () -> Void
    let onSelectTransaction: ((Transaction) -> Void)?
    let transactions: [Transaction]?

    // MARK: - Member Split Support
    var memberSplits: [UUID: [CategoryMemberSplit]] = [:]
    var isMemberSplitOn: Binding<Bool>?
    var showMemberToggle: Bool = false
    var onToggleMemberSplit: (() -> Void)?
    var memberSplitDonutItems: [MemberSplitDonutItem] = []

    @State private var selectedAngle: Double?
    @State private var animationProgress: Double = 0
    @State private var barFillStep: Double = 0
    @State private var barAnimID = UUID()
    @State private var hasAppeared = false
    @State private var animationTask: Task<Void, Never>?
    /// 稳定后才更新给 Chart 的数据，避免快速切换时 Charts 收到变化中的数据触发断言
    @State private var stableCategories: [CategoryExpenseItem] = []
    @State private var chartID = UUID()

    private var memberSplitActive: Bool {
        isMemberSplitOn?.wrappedValue == true && showMemberToggle
    }

    var body: some View {
        VStack(spacing: 12) {
            if let txs = transactions, !txs.isEmpty, !memberSplitActive {
                transactionList(txs)
            } else {
                donutCard
                categoryList
            }
        }
        .onAppear {
            if stableCategories.isEmpty { stableCategories = categories }
        }
        .onChange(of: categories.map(\.id)) { _, _ in
            handleCategoriesChanged()
        }
        .onChange(of: isMemberSplitOn?.wrappedValue ?? false) { _, newVal in
            animationTask?.cancel()
            animationTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled else { return }
                stableCategories = categories
                chartID = UUID()
                try? await Task.sleep(for: .milliseconds(1))
                guard !Task.isCancelled else { return }
                animationProgress = 0
                withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                    animationProgress = 1.0
                }
                guard !Task.isCancelled else { return }
                runBarAnimation(delay: 0.1)
            }
        }
    }

    private func handleCategoriesChanged() {
        gradientLookup = buildGradientLookup()
        guard hasAppeared else { return }
        animationTask?.cancel()
        animationTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled else { return }
            stableCategories = categories
            chartID = UUID()
            try? await Task.sleep(for: .milliseconds(1))
            guard !Task.isCancelled else { return }
            animationProgress = 0
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                animationProgress = 1.0
            }
            guard !Task.isCancelled else { return }
            runBarAnimation(delay: 0.1)
        }
    }

    // MARK: - Donut Card

    private var donutCard: some View {
        VStack(spacing: 0) {
            donutChart
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .glassCard(cornerRadius: 24)
        .overlay(alignment: .bottomTrailing) {
            if showMemberToggle {
                memberToggleButton
            }
        }
        .padding(.horizontal, 12)
    }

    // MARK: - Member Toggle Button

    private var memberToggleButton: some View {
        Button {
            isMemberSplitOn?.wrappedValue.toggle()
            if isMemberSplitOn?.wrappedValue == true {
                onToggleMemberSplit?()
            }
        } label: {
            Image(systemName: "person.2.circle.fill")
                .font(.title)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(
                    memberSplitActive
                        ? Color.designAccentGreen
                        : Color.designOnSurfaceVariant
                )
        }
        .buttonStyle(.plain)
        .padding(8)
        .padding(.bottom, 0)
        .padding(.trailing, 0)
    }

    // MARK: - Donut Chart

    private var donutChart: some View {
        Group {
            DonutChartContent(
                categories: donutCategories ?? stableCategories,
                animationProgress: animationProgress,
                selectedAngle: $selectedAngle,
                gradientLookup: gradientLookup,
                fallbackGradient: fallbackGradient,
                onCategoryTap: memberSplitActive ? { _ in } : onCategoryTap
            )
            .id(chartID)
            .frame(height: 240)
            .shadow(color: .black.opacity(0.12), radius: 20, y: 8)
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    let frame = geometry[proxy.plotAreaFrame]
                    centerLabel
                        .position(x: frame.midX, y: frame.midY)
                }
            }
        }
        .onAppear {
            gradientLookup = buildGradientLookup()
            guard !hasAppeared else { return }
            hasAppeared = true
            withAnimation(.spring(response: 0.8, dampingFraction: 0.6)) {
                animationProgress = 1.0
            }
            runBarAnimation(delay: 0.3)
        }
    }

    // MARK: - Center Label

    private var centerLabel: some View {
        VStack(spacing: 2) {
            if isDrilledDown && !memberSplitActive {
                Button {
                    onCenterTap()
                } label: {
                    HStack(spacing: 2) {
                        Image(systemName: "chevron.left")
                            .font(.designBodySmall)
                        Text(centerTitle)
                            .font(.designBodySmall)
                    }
                    .foregroundStyle(Color.designAccentGreen)
                }
            } else if memberSplitActive {
                Text(centerTitle)
                    .font(.designBodySmall)
                    .foregroundStyle(Color.designOnSurfaceVariant)
            } else {
                Text(centerTitle)
                    .font(.designBodySmall)
                    .foregroundStyle(Color.designOnSurfaceVariant)
            }
            CurrencyText(
                amount: totalExpense,
                currencyCode: "",
                size: 18,
                foregroundColor: Color.designOnSurface,
                fractionDigits: 0
            )
            .bold()
        }
        .padding(12)
    }

    // MARK: - Gradient Helpers

    /// Pre-computed once per category set — prevents color flashing during animation.
    @State private var gradientLookup: [String: LinearGradient] = [:]

    private var fallbackGradient: LinearGradient {
        LinearGradient(colors: [.gray.opacity(0.5), .gray], startPoint: .top, endPoint: .bottom)
    }

    private func buildGradientLookup() -> [String: LinearGradient] {
        var map: [String: LinearGradient] = [:]
        func collect(_ items: [CategoryExpenseItem]) {
            for item in items {
                map[item.name] = gradientFor(hex: item.colorHex)
                collect(item.children)
            }
        }
        collect(categories)
        return map
    }

    private func gradientFor(hex: String) -> LinearGradient {
        let base = Color(hex: hex) ?? .gray
        let lighter = base.opacity(0.65)
        return LinearGradient(
            colors: [lighter, base],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    // MARK: - Category List

    private var categoryList: some View {
        let cap = maxListItems ?? categories.count
        let visible = Array(categories.prefix(cap).enumerated())
        let hiddenCount = categories.count - cap

        return VStack(spacing: 8) {
            ForEach(visible, id: \.element.id) { index, item in
                categoryRow(index: index, item: item)
            }

            if hiddenCount > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "ellipsis.circle")
                        .font(.designBodySmall)
                        .foregroundStyle(Color.designOnSurfaceVariant)
                    Text(String(localized: "还有\(hiddenCount)项未显示"))
                        .font(.designBodySmall)
                        .foregroundStyle(Color.designOnSurfaceVariant)
                    Spacer()
                }
                .padding(12)
                .glassCard(cornerRadius: 16)
                .opacity(animationProgress >= 1.0 ? 1 : 0)
            }
        }
        .padding(.horizontal, 12)
    }

    @ViewBuilder
    private func categoryRow(index: Int, item: CategoryExpenseItem) -> some View {
        Button {
            if !memberSplitActive {
                onCategoryTap(item.id)
            }
        } label: {
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color(hex: item.colorHex) ?? .gray)
                        .frame(width: 12, height: 12)

                    Text(item.name)
                        .font(.designBodyMedium)
                        .foregroundStyle(Color.designOnSurface)

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        CurrencyText(amount: item.amount, currencyCode: "", size: 15, foregroundColor: Color.designOnSurface)
                            .fontWeight(.medium)
                        Text(String(format: "%.1f%%", item.percentage * 100))
                            .font(.designMonoDataSmall)
                            .foregroundStyle(Color.designOnSurfaceVariant)
                    }

                    if !memberSplitActive {
                        Image(systemName: "chevron.right")
                            .font(.designBodySmall)
                            .foregroundStyle(Color.designOnSurfaceVariant.opacity(0.5))
                    }
                }

                // MARK: Member Split Sub-rows
                if memberSplitActive, let splits = memberSplits[item.id], !splits.isEmpty {
                    let catBarProgress = min(barFillStep, item.percentage * 16) / 16.0
                    PixelProgressBar(progress: catBarProgress, tint: Color(hex: item.colorHex) ?? .gray, totalBlocks: 16)

                    VStack(spacing: 6) {
                        ForEach(splits, id: \.memberID) { split in
                            let mIdx = splits.firstIndex(where: { $0.memberID == split.memberID }) ?? 0
                            VStack(spacing: 4) {
                                HStack(spacing: 4) {
                                    Circle()
                                        .fill(memberSplitColor(baseColorHex: item.colorHex, memberIndex: mIdx, totalMembers: splits.count))
                                        .frame(width: 6, height: 6)
                                    Text(split.memberName)
                                        .font(.designBodySmall)
                                        .foregroundStyle(Color.designOnSurfaceVariant)
                                    Spacer()
                                    CurrencyText(amount: split.amount, currencyCode: "", size: 12, foregroundColor: Color.designOnSurfaceVariant)
                                    Text(String(format: "%.1f%%", split.percentage * 100))
                                        .font(.designMonoDataSmall)
                                        .foregroundStyle(Color.designOnSurfaceVariant.opacity(0.6))
                                }
                                let memberBarProgress = min(barFillStep, split.percentage * 16) / 16.0
                                PixelProgressBar(
                                    progress: memberBarProgress,
                                    tint: memberSplitColor(baseColorHex: item.colorHex, memberIndex: mIdx, totalMembers: splits.count),
                                    totalBlocks: 12
                                )
                            }
                            .padding(.leading, 20)
                        }
                    }
                    .padding(.top, 2)
                } else {
                    let targetBlocks = item.percentage * 16
                    let displayProgress = min(barFillStep, targetBlocks) / 16.0
                    PixelProgressBar(progress: displayProgress, tint: Color(hex: item.colorHex) ?? .gray, totalBlocks: 16)
                }
            }
            .padding(12)
            .glassCard(cornerRadius: 16)
        }
        .buttonStyle(.plain)
        .opacity(animationProgress >= 1.0 ? 1 : 0)
        .offset(y: animationProgress >= 1.0 ? 0 : 20)
        .animation(
            .spring(response: 0.5, dampingFraction: 0.7)
            .delay(Double(index) * 0.06),
            value: animationProgress
        )
    }

    // MARK: - Member Split Color

    private func memberSplitColor(baseColorHex: String, memberIndex: Int, totalMembers: Int) -> Color {
        let base = baseColorHex.isEmpty ? Color.gray : Color(hex: baseColorHex)
        guard totalMembers > 1 else { return base }
        let fraction = Double(totalMembers - memberIndex) / Double(totalMembers)
        return base.opacity(max(0.3, fraction))
    }

    // MARK: - Bar Animation

    /// Steps through blocks one-by-one: 1 → 2 → 3 → ... → N, with a partial fill on the last block.
    private func runBarAnimation(delay: Double) {
        guard !categories.isEmpty else { return }
        let maxBlocks = categories.map { $0.percentage * 16.0 }.max() ?? 8.0
        let fullSteps = Int(floor(maxBlocks))
        guard fullSteps > 0 else { return }
        let remainder = maxBlocks - Double(fullSteps)
        let stepDuration = 0.2
        let thisID = UUID()
        barAnimID = thisID

        barFillStep = 0

        for i in 1...fullSteps {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay + Double(i) * stepDuration) {
                guard barAnimID == thisID else { return }
                withAnimation(.easeOut(duration: stepDuration * 0.6)) {
                    barFillStep = Double(i)
                }
            }
        }
        if remainder > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay + Double(fullSteps + 1) * stepDuration) {
                guard barAnimID == thisID else { return }
                withAnimation(.easeOut(duration: stepDuration * 0.6)) {
                    barFillStep = maxBlocks
                }
            }
        }
    }

    // MARK: - Transaction List

    private func transactionList(_ txs: [Transaction]) -> some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    onCenterTap()
                } label: {
                    HStack(spacing: 2) {
                        Image(systemName: "chevron.left")
                            .font(.designBodySmall.weight(.medium))
                        Text(centerTitle)
                            .font(.designBodyMedium.weight(.medium))
                    }
                    .foregroundStyle(Color.designAccentGreen)
                }
                .buttonStyle(.plain)

                Spacer()

                CurrencyText(amount: totalExpense, currencyCode: "", size: 15, foregroundColor: Color.designOnSurface)
                    .bold()
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)

            Divider()
                .padding(.bottom, 12)

            VStack(spacing: 12) {
                ForEach(txs.sorted(by: { $0.date > $1.date }), id: \.id) { tx in
                    Button {
                        onSelectTransaction?(tx)
                    } label: {
                        TransactionRowView(transaction: tx)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
