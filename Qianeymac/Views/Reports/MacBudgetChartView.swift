import SwiftUI
import Charts

// MARK: - Budget Card Hover State

@Observable
private final class CardHoverState {
    var mouseOffset: CGPoint = .zero
    var isHovering = false
}

// MARK: - Reusable Hover Tilt Modifier

private struct HoverTiltModifier: ViewModifier {
    @State private var hover = CardHoverState()

    func body(content: Content) -> some View {
        content
            .rotation3DEffect(
                .degrees(hover.isHovering ? 3 : 0),
                axis: (x: -hover.mouseOffset.y / 30, y: hover.mouseOffset.x / 30, z: 0)
            )
            .offset(x: hover.isHovering ? hover.mouseOffset.x / 25 : 0,
                    y: hover.isHovering ? hover.mouseOffset.y / 25 : 0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: hover.isHovering)
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    if !hover.isHovering { hover.isHovering = true }
                    hover.mouseOffset = location
                case .ended:
                    hover.isHovering = false
                    hover.mouseOffset = .zero
                }
            }
    }
}

private extension View {
    func hoverTilt() -> some View {
        modifier(HoverTiltModifier())
    }
}

// MARK: - Flip Indicator (hover to reveal)

private struct FlipIndicatorModifier: ViewModifier {
    let showOnHover: Bool
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .topTrailing) {
                if showOnHover ? isHovering : true {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 9))
                        .foregroundStyle(Color.designOnSurfaceVariant.opacity(showOnHover ? (isHovering ? 0.6 : 0) : 0.4))
                        .padding(12)
                }
            }
            .onContinuousHover { phase in
                switch phase {
                case .active:
                    withAnimation(.easeInOut(duration: 0.15)) { isHovering = true }
                case .ended:
                    withAnimation(.easeInOut(duration: 0.15)) { isHovering = false }
                }
            }
    }
}

private extension View {
    func flipIndicator(showOnHover: Bool = false) -> some View {
        modifier(FlipIndicatorModifier(showOnHover: showOnHover))
    }
}

struct MacBudgetChartView: View {
    let items: [BudgetItemData]
    let books: [BudgetBook]
    let overviewSummary: BudgetOverviewSummary?
    let dailyTrendByCategory: [UUID: [DailySpendingPoint]]
    let burnRateData: [BurnRateBucket]
    @Binding var selectedBookID: UUID?
    @Binding var dimension: BudgetViewDimension

    @State private var expandedCardIDs: Set<UUID> = []
    @State private var animTimeProgress: Double = 0
    @State private var animBudgetProgress: Double = 0
    @State private var burnRateRevealProgress: Double = 0
    @State private var isBurnRateFlipped = false

    var body: some View {
        bodyContent
            .onChange(of: dimension) { _, _ in animateProgress(reset: true) }
            .onChange(of: overviewSummary?.timeProgress) { _, _ in animateProgress() }
            .task { animateProgress() }
    }

    private func animateProgress(reset: Bool = false) {
        if reset { animTimeProgress = 0; animBudgetProgress = 0 }
        withAnimation(.spring(response: 0.8, dampingFraction: 0.65)) {
            animTimeProgress = overviewSummary?.timeProgress ?? 0
            animBudgetProgress = overviewSummary?.budgetProgress ?? 0
        }
    }

    private var bodyContent: some View {
        VStack(spacing: 0) {
            if books.isEmpty {
                emptyView
            } else {
                if items.isEmpty {
                    emptyBudgetView
                } else {
                    // Summary card: fixed at top, NOT in the ScrollView
                    summaryCard
                        .padding(.horizontal, 24)
                        .padding(.top, 12)

                    // Budget item list: scrolls BEHIND the summary card
                    ScrollView {
                        flatItemList
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                    }
                }
            }
        }
    }

    // MARK: - Empty

    private var emptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "gauge.with.dots.needle.33percent")
                .font(.system(size: 40))
                .foregroundStyle(Color.designOnSurfaceVariant.opacity(0.4))
            Text("暂无预算数据")
                .font(.designBodyMedium)
                .foregroundStyle(Color.designOnSurfaceVariant)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyBudgetView: some View {
        VStack(spacing: 12) {
            Image(systemName: "gauge.with.dots.needle.33percent")
                .font(.system(size: 40))
                .foregroundStyle(Color.designOnSurfaceVariant.opacity(0.4))
            Text("该预算计划无预算项")
                .font(.designBodyMedium)
                .foregroundStyle(Color.designOnSurfaceVariant)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 60)
    }

    // MARK: - Computed

    private var totals: (budget: Decimal, spent: Decimal) {
        items.reduce(into: (Decimal(0), Decimal(0))) { acc, item in
            acc.0 += item.budgetAmount
            acc.1 += item.spentAmount
        }
    }
    private var totalRemaining: Decimal { totals.budget - totals.spent }

    /// 超前 / 可控分类
    private var aheadItems: [BudgetItemData] { items.filter { !$0.isOnTrack && $0.spentAmount > 0 } }
    private var controlledItems: [BudgetItemData] { items.filter { $0.isOnTrack || $0.spentAmount == 0 } }

    // MARK: - Summary Card

    @ViewBuilder
    private var summaryCard: some View {
        if let summary = overviewSummary {
            overviewSummaryCard(summary)
        } else {
            HStack(spacing: 16) {
                summaryCell(label: String(localized: "总预算"), amount: totals.budget, color: Color.designPrimaryFixedDim)
                summaryCell(label: String(localized: "已花费"), amount: totals.spent, color: Color.designAccentRed)
                summaryCell(label: String(localized: "剩余"), amount: totalRemaining, color: totalRemaining >= 0 ? .blue : Color.designAccentRed)
            }
        }
    }

    // MARK: - Overview Summary (整体预算) — 进度 50% + 超前 25% + 可控 25%

    private func overviewSummaryCard(_ s: BudgetOverviewSummary) -> some View {
        HStack(alignment: .top, spacing: 8) {
            progressCard(s)
                .frame(maxWidth: .infinity)

            VStack(spacing: 8) {
                HStack(alignment: .top, spacing: 8) {
                    aheadCard.frame(maxWidth: .infinity)
                    controlledCard.frame(maxWidth: .infinity)
                }
                burnRateCard
                    .frame(height: 87)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func progressCard(_ s: BudgetOverviewSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // 总支出
            Text(String(localized: "总支出"))
                .font(.designBodyCaption)
                .foregroundStyle(Color.designOnSurfaceVariant)
            CurrencyText(amount: s.totalSpent, currencyCode: "", showSign: false, size: 20, foregroundColor: Color.designAccentRed, fractionDigits: 0)
                .bold()

            overviewTimeBar(s)
            overviewBudgetBar(s)
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .glassCard(cornerRadius: 14)
        .hoverTilt()
    }

    private var aheadCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: "hare.fill").font(.system(size: 9)).foregroundStyle(Color.designAccentRed)
                Text(String(localized: "超前花费")).font(.system(size: 9, weight: .semibold)).foregroundStyle(Color.designAccentRed)
            }
            Text("\(aheadItems.count) \(String(localized: "项"))")
                .font(.system(size: 18, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.designAccentRed)
            if aheadItems.isEmpty {
                Text(String(localized: "暂无")).font(.system(size: 9)).foregroundStyle(Color.designOnSurfaceVariant.opacity(0.4))
            } else {
                Text(aheadItems.prefix(3).map(\.name).joined(separator: "、"))
                    .font(.system(size: 8)).foregroundStyle(Color.designOnSurfaceVariant).lineLimit(2)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 87)
        .glassCard(cornerRadius: 14)
        .hoverTilt()
    }

    private var controlledCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: "tortoise.fill").font(.system(size: 9)).foregroundStyle(Color.blue)
                Text(String(localized: "节奏可控")).font(.system(size: 9, weight: .semibold)).foregroundStyle(Color.blue)
            }
            Text("\(controlledItems.count) \(String(localized: "项"))")
                .font(.system(size: 18, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.blue)
            if controlledItems.isEmpty {
                Text(String(localized: "暂无")).font(.system(size: 9)).foregroundStyle(Color.designOnSurfaceVariant.opacity(0.4))
            } else {
                Text(controlledItems.prefix(3).map(\.name).joined(separator: "、"))
                    .font(.system(size: 8)).foregroundStyle(Color.designOnSurfaceVariant).lineLimit(2)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 87)
        .glassCard(cornerRadius: 14)
        .hoverTilt()
    }

    // MARK: - Burn Rate Card (📶 消耗速率，支持翻转)

    private var burnRateCard: some View {
        ZStack {
            if isBurnRateFlipped {
                burnRateBack
                    .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
            } else {
                burnRateFront
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .rotation3DEffect(.degrees(isBurnRateFlipped ? 180 : 0), axis: (x: 0, y: 1, z: 0))
        .animation(.spring(response: 0.5, dampingFraction: 0.7), value: isBurnRateFlipped)
        .onTapGesture { withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) { isBurnRateFlipped.toggle() } }
    }

    private var burnRateFront: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(String(localized: "消耗速率"))
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Color.designOnSurfaceVariant)

            if burnRateData.isEmpty {
                Text(String(localized: "暂无数据"))
                    .font(.system(size: 9))
                    .foregroundStyle(Color.designOnSurfaceVariant.opacity(0.4))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            } else {
                BurnRateBarChart(data: burnRateData, progress: burnRateRevealProgress)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassCard(cornerRadius: 14)
        .flipIndicator(showOnHover: true)
        .task {
            burnRateRevealProgress = 0
            DispatchQueue.main.async {
                withAnimation(.easeOut(duration: 4.0)) { burnRateRevealProgress = 1 }
            }
        }
        .onChange(of: burnRateData.map(\.id)) { _, _ in
            burnRateRevealProgress = 0
            DispatchQueue.main.async {
                withAnimation(.easeOut(duration: 4.0)) { burnRateRevealProgress = 1 }
            }
        }
    }

    private var burnRateBack: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(String(localized: "消耗分析"))
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Color.designOnSurfaceVariant)

            if burnRateData.isEmpty {
                Text(String(localized: "暂无数据"))
                    .font(.system(size: 9))
                    .foregroundStyle(Color.designOnSurfaceVariant.opacity(0.4))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                burnRateAnalysisContent
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassCard(cornerRadius: 14)
        .flipIndicator(showOnHover: true)
    }

    // MARK: - Burn Rate Analysis Content

    private var burnRateAnalysisContent: some View {
        let analysis = BurnRateAnalysis(buckets: burnRateData)
        return VStack(alignment: .leading, spacing: 6) {
            // 第一行：峰值区间 + 整体节奏（左右结构）
            HStack(alignment: .top, spacing: 8) {
                if let peak = analysis.peakBucket {
                    analysisRow(
                        icon: "exclamationmark.triangle.fill",
                        iconColor: peakColor(peak),
                        title: String(localized: "峰值区间"),
                        body: peakLabel(peak)
                    )
                }

                analysisRow(
                    icon: analysis.isAccelerating ? "arrow.up.right" : "arrow.down.right",
                    iconColor: analysis.isAccelerating ? Color.designAccentRed : .blue,
                    title: String(localized: "整体节奏"),
                    body: analysis.rhythmText
                )
            }

            // 第二行：建议（单独一行）
            if !analysis.suggestion.isEmpty {
                analysisRow(
                    icon: "lightbulb.fill",
                    iconColor: Color.designPrimaryFixedDim,
                    title: String(localized: "建议"),
                    body: analysis.suggestion
                )
            }

            Spacer(minLength: 0)
        }
    }

    private func analysisRow(icon: String, iconColor: Color, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 9))
                .foregroundStyle(iconColor)
                .frame(width: 12)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.designOnSurfaceVariant)
                Text(body)
                    .font(.system(size: 9))
                    .foregroundStyle(Color.designOnSurface.opacity(0.85))
                    .lineLimit(3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func peakLabel(_ peak: BurnRateBucket) -> String {
        let df = DateFormatter()
        df.dateFormat = "M/d"
        let start = df.string(from: peak.startDate)
        let end = df.string(from: peak.endDate)
        let amount = CurrencyFormatter.formatDecimal(amount: peak.amount, fractionDigits: 0)
        return "\(start)-\(end) 消耗\(amount)，为周期最高"
    }

    private func peakColor(_ peak: BurnRateBucket) -> Color {
        let ratio = peak.maxAmount > 0 ? CGFloat(truncating: (peak.amount / peak.maxAmount) as NSNumber) : 0
        let hue = (1.0 - ratio) * 0.33
        return Color(hue: hue, saturation: 0.75, brightness: 0.85)
    }

    // MARK: - Overview progress bars (左半部分)

    private func overviewTimeBar(_ s: BudgetOverviewSummary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(String(localized: "时间进度"))
                    .font(.designBodyCaption)
                    .foregroundStyle(Color.designOnSurfaceVariant)
                Spacer()
                Text(String(format: "%.1f%%", s.timeProgress * 100))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Color.designPrimaryFixedDim)
            }
            PixelProgressBar(progress: min(animTimeProgress, 1.0), tint: Color.designPrimaryFixedDim.opacity(0.5), totalBlocks: 16)
            Text("\(s.elapsedDays) / \(s.totalDays) \(String(localized: "天"))")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(Color.designOnSurfaceVariant.opacity(0.5))
        }
    }

    private func overviewBudgetBar(_ s: BudgetOverviewSummary) -> some View {
        let spentStr = CurrencyFormatter.formatDecimal(amount: s.totalSpent, fractionDigits: 0)
        let budgetStr = CurrencyFormatter.formatDecimal(amount: s.totalBudget, fractionDigits: 0)
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(String(localized: "预算使用"))
                    .font(.designBodyCaption)
                    .foregroundStyle(Color.designOnSurfaceVariant)
                Spacer()
                Text(String(format: "%.1f%%", s.budgetProgress * 100))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(s.isOnTrack ? Color.blue : Color.designAccentRed)
            }
            PixelProgressBar(progress: min(animBudgetProgress, 1.0), tint: s.isOnTrack ? .blue : Color.designAccentRed)
            Text("\(spentStr) / \(budgetStr)")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(Color.designOnSurfaceVariant.opacity(0.5))
        }
    }

    private func summaryCell(label: String, amount: Decimal, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.designBodyCaption)
                .foregroundStyle(Color.designOnSurfaceVariant)
            CurrencyText(amount: amount, currencyCode: "", showSign: false, size: 18, foregroundColor: color, fractionDigits: 0)
                .bold()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .glassCard(cornerRadius: 12)
    }

    // MARK: - Grid

    private let gridColumns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]

    // MARK: - Item List

    private var flatItemList: some View {
        LazyVGrid(columns: gridColumns, spacing: 12) {
            ForEach(items) { item in
                BudgetCardView(
                    item: item,
                    trendData: dailyTrendByCategory[item.id] ?? [],
                    isExpanded: expandedCardIDs.contains(item.id),
                    dimension: dimension,
                    onTap: { toggleCard(item.id) }
                )
            }
        }
    }

    private func toggleCard(_ id: UUID) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
            if expandedCardIDs.contains(id) {
                expandedCardIDs.remove(id)
            } else {
                expandedCardIDs.insert(id)
            }
        }
    }

}

// MARK: - Budget Card View (通用组件，支持翻转查看趋势)

private struct BudgetCardView: View {
    let item: BudgetItemData
    let trendData: [DailySpendingPoint]
    let isExpanded: Bool
    let dimension: BudgetViewDimension
    let onTap: () -> Void

    @State private var isFlipped = false
    @State private var animTime: Double = 0
    @State private var animBudget: Double = 0
    @State private var trendLineProgress: CGFloat = 0
    @State private var trendAreaProgress: CGFloat = 0

    private let cardHeight: CGFloat = 172

    var body: some View {
        ZStack {
            if isFlipped {
                trendBack
                    .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
            } else {
                budgetFront
            }
        }
        .frame(height: cardHeight)
        .rotation3DEffect(.degrees(isFlipped ? 180 : 0), axis: (x: 0, y: 1, z: 0))
        .animation(.spring(response: 0.5, dampingFraction: 0.7), value: isFlipped)
        .onTapGesture { withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) { isFlipped.toggle() } }
        .onChange(of: isFlipped) { _, flipped in
            if flipped { startTrendAnimation() } else { animateIn() }
        }
        .task { animateIn() }
        .onChange(of: item.id) { _ in animateIn() }
        .onChange(of: item.timeProgress) { _, _ in animateIn() }
        .onChange(of: item.percentage) { _, _ in animateIn() }
        .onChange(of: dimension) { _, _ in animateIn() }
    }

    private func animateIn() {
        animTime = 0
        animBudget = 0
        withAnimation(.spring(response: 0.7, dampingFraction: 0.65)) {
            animTime = item.timeProgress
            animBudget = item.percentage
        }
    }

    private func startTrendAnimation() {
        trendLineProgress = 0
        trendAreaProgress = 0
        withAnimation(.easeOut(duration: 1.2)) { trendLineProgress = 1 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation(.easeOut(duration: 0.6)) { trendAreaProgress = 1 }
        }
    }

    // MARK: - Front: Budget Info

    private var budgetFront: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(hex: item.colorHex) ?? .gray)
                    .frame(width: 10, height: 10)
                Text(item.name)
                    .font(.designBodySmall)
                    .foregroundStyle(Color.designOnSurface)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }

            CurrencyText(
                amount: item.spentAmount, currencyCode: "",
                size: 16,
                foregroundColor: item.isOverBudget ? Color.designAccentRed : Color.designOnSurface
            )
            .bold()

            HStack(spacing: 4) {
                Text(item.period.displayName)
                    .font(.designBodyCaption)
                    .foregroundStyle(Color.designOnSurfaceVariant)
                CurrencyText(amount: item.periodAmount, currencyCode: "", size: 10,
                    foregroundColor: Color.designOnSurfaceVariant.opacity(0.5), fractionDigits: 0)
                Text("· 总")
                    .font(.designBodyCaption).foregroundStyle(Color.designOnSurfaceVariant.opacity(0.3))
                CurrencyText(amount: item.budgetAmount, currencyCode: "", size: 10,
                    foregroundColor: Color.designOnSurfaceVariant.opacity(0.7), fractionDigits: 0)
                Spacer(minLength: 4)
                Text(String(format: "%.0f%%", item.percentage * 100))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(item.isOverBudget ? Color.designAccentRed : Color.designOnSurfaceVariant)
            }

            cardTimeBar
            cardBudgetBar
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassCard(cornerRadius: 14)
        .hoverTilt()
        .flipIndicator(showOnHover: true)
    }

    // MARK: - Back: Trend Chart + Pace

    private var trendBack: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Category header
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(hex: item.colorHex) ?? .gray)
                    .frame(width: 10, height: 10)
                Text(item.name)
                    .font(.designBodySmall)
                    .foregroundStyle(Color.designOnSurface)
                    .lineLimit(1)
                Spacer()
                Text(String(localized: "趋势"))
                    .font(.system(size: 9)).foregroundStyle(Color.designOnSurfaceVariant.opacity(0.5))
            }

            // Mini trend chart (rolling average, animated)
            if !trendData.isEmpty {
                let smoothed = rollingAverage(trendData)
                let maxAmt = smoothed.map(\.amount).max() ?? 1
                Chart(smoothed) { point in
                    AreaMark(
                        x: .value("Date", point.date),
                        yStart: .value("Base", 0),
                        yEnd: .value("Amount", Double(truncating: point.amount as NSNumber) * trendAreaProgress)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.designAccentRed.opacity(0.2), Color.designAccentRed.opacity(0.02)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.catmullRom)

                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Amount", Double(truncating: point.amount as NSNumber))
                    )
                    .foregroundStyle(Color.designAccentRed.opacity(0.5))
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 1))
                }
                .chartYScale(domain: 0...(maxAmt * 1.2))
                .mask(alignment: .leading) {
                    Rectangle().scaleEffect(x: trendLineProgress, y: 1, anchor: .leading)
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
            } else {
                VStack(spacing: 4) {
                    Image(systemName: "chart.line.uptrend.xyaxis").font(.system(size: 24)).opacity(0.2)
                    Text(String(localized: "暂无趋势数据")).font(.system(size: 9)).foregroundStyle(Color.designOnSurfaceVariant.opacity(0.4))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            // Pace section (moved from expand)
            paceSection
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassCard(cornerRadius: 14)
    }

    // MARK: - Time bar (ghost style, subtle)

    private var cardTimeBar: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(String(localized: "时间")).font(.system(size: 9)).foregroundStyle(Color.designOnSurfaceVariant.opacity(0.6))
                Spacer()
                Text(String(format: "%.0f%%", item.timeProgress * 100))
                    .font(.system(size: 9, design: .monospaced)).foregroundStyle(Color.designPrimaryFixedDim.opacity(0.6))
            }
            PixelProgressBar(progress: min(animTime, 1.0), tint: Color.designPrimaryFixedDim.opacity(0.4), totalBlocks: 12)
        }
    }

    // MARK: - Budget bar (solid, prominent)

    private var cardBudgetBar: some View {
        let spentStr = CurrencyFormatter.formatDecimal(amount: item.spentAmount, fractionDigits: 0)
        let budgetStr = CurrencyFormatter.formatDecimal(amount: item.budgetAmount, fractionDigits: 0)
        return VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(String(localized: "预算")).font(.system(size: 9)).foregroundStyle(Color.designOnSurfaceVariant.opacity(0.6))
                Spacer()
                Text("\(spentStr) / \(budgetStr)")
                    .font(.system(size: 9, design: .monospaced)).foregroundStyle(Color.designOnSurfaceVariant.opacity(0.6))
            }
            PixelProgressBar(progress: min(animBudget, 1.0),
                tint: item.isOverBudget ? Color.designAccentRed : (Color(hex: item.colorHex) ?? .gray))
        }
    }

    // MARK: - Pace Section

    private var paceSection: some View {
        let isOnTrack = item.isOnTrack
        let iconName = isOnTrack ? "tortoise.fill" : "hare.fill"

        return HStack(spacing: 4) {
            Image(systemName: iconName)
                .font(.system(size: 9))
                .foregroundStyle(isOnTrack ? Color.blue : Color.designAccentRed)
            Text(item.paceLabel)
                .font(.system(size: 9))
                .foregroundStyle(isOnTrack ? Color.blue : Color.designAccentRed)
            Spacer(minLength: 4)
            Text(item.suggestionText)
                .font(.system(size: 9))
                .foregroundStyle(Color.designOnSurfaceVariant.opacity(0.7))
                .lineLimit(1)
        }
    }
}

// MARK: - Rolling Average Trend Helper

/// Rolling average: distributes each transaction's amount evenly across `windowDays` centered on the transaction day.
/// This flattens sparse spikes (e.g. monthly ¥128 subscription → ¥30/day for 7 days)
/// while preserving the total. Each day's amount = sum of all transaction contributions that day.
private func rollingAverage(_ daily: [DailySpendingPoint], windowDays: Int = 7) -> [DailySpendingPoint] {
    guard !daily.isEmpty else { return [] }
    let cal = Calendar.current

    // Build a daily map: date → total amount per day
    var dailyTotals: [Date: Decimal] = [:]
    for point in daily {
        let day = cal.startOfDay(for: point.date)
        dailyTotals[day, default: .zero] += point.amount
    }

    guard let minDay = dailyTotals.keys.min(), let maxDay = dailyTotals.keys.max() else { return [] }

    var result: [DailySpendingPoint] = []
    var current = minDay
    while current <= maxDay {
        // For each past transaction within windowDays-1 days, compute decay contribution
        // Transaction on day t with amount A:
        //   current==t        → A (100%)
        //   current==t+1      → A × (windowDays-1)/windowDays
        //   current==t+2      → A × (windowDays-2)/windowDays
        //   ...
        //   current==t+windowDays-1 → A × 1/windowDays
        var rolling: Decimal = .zero
        for daysAgo in 0..<windowDays {
            if let txDay = cal.date(byAdding: .day, value: -daysAgo, to: current),
               let amt = dailyTotals[txDay] {
                let decay = Decimal(windowDays - daysAgo) / Decimal(windowDays)
                rolling += amt * decay
            }
        }
        if rolling > 0 || result.isEmpty {
            result.append(DailySpendingPoint(date: current, amount: rolling))
        }
        current = cal.date(byAdding: .day, value: 1, to: current) ?? current
    }

    return result
}

/// Legacy weekly aggregation — kept for reference, replaced by rollingAverage above.
private func weeklySmoothed(_ daily: [DailySpendingPoint]) -> [DailySpendingPoint] {
    guard !daily.isEmpty else { return [] }
    let cal = Calendar.current
    var result: [DailySpendingPoint] = []
    var weekStart = cal.startOfDay(for: daily.first!.date)
    var weekTotal = Decimal(0)
    var weekEnd = cal.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart

    for point in daily {
        if point.date > weekEnd {
            result.append(DailySpendingPoint(date: weekStart, amount: weekTotal))
            weekStart = cal.date(byAdding: .day, value: 1, to: weekEnd) ?? point.date
            weekEnd = cal.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
        }
        weekTotal += point.amount
    }
    result.append(DailySpendingPoint(date: weekStart, amount: weekTotal))
    return result
}

// MARK: - Burn Rate Analysis

/// 根据 BurnRateBucket 数据生成分析结论
private struct BurnRateAnalysis {
    let buckets: [BurnRateBucket]

    /// 消耗最高的桶
    var peakBucket: BurnRateBucket? {
        buckets.max(by: { $0.amount < $1.amount })
    }

    /// 是否加速中（后半段均值 > 前半段均值）
    var isAccelerating: Bool {
        guard buckets.count >= 2 else { return false }
        let mid = buckets.count / 2
        let firstHalf = buckets.prefix(mid).map(\.amount)
        let secondHalf = buckets.suffix(buckets.count - mid).map(\.amount)
        let firstAvg = firstHalf.reduce(0, +) / Decimal(firstHalf.count)
        let secondAvg = secondHalf.reduce(0, +) / Decimal(secondHalf.count)
        return secondAvg > firstAvg
    }

    /// 整体节奏描述
    var rhythmText: String {
        guard buckets.count >= 2 else { return String(localized: "数据不足") }
        let mid = buckets.count / 2
        let firstHalf = Array(buckets.prefix(mid))
        let secondHalf = Array(buckets.suffix(buckets.count - mid))
        let firstAvg = firstHalf.map(\.amount).reduce(0, +) / Decimal(max(1, firstHalf.count))
        let secondAvg = secondHalf.map(\.amount).reduce(0, +) / Decimal(max(1, secondHalf.count))
        let df = DateFormatter()
        df.dateFormat = "M/d"
        let firstStart = df.string(from: firstHalf.first?.startDate ?? Date())
        let firstEnd = df.string(from: firstHalf.last?.endDate ?? Date())
        let secondStart = df.string(from: secondHalf.first?.startDate ?? Date())
        let secondEnd = df.string(from: secondHalf.last?.endDate ?? Date())
        let ratio = firstAvg > 0 ? secondAvg / firstAvg : 0
        if secondAvg > firstAvg * Decimal(1.2) {
            return String(localized: "后半段（\(secondStart)-\(secondEnd)）消耗明显加快，约为前半段\(String(format: "%.0f", Double(truncating: ratio as NSNumber) * 100))%")
        } else if secondAvg < firstAvg * Decimal(0.8) {
            return String(localized: "后半段（\(secondStart)-\(secondEnd)）消耗放缓，约为前半段\(String(format: "%.0f", Double(truncating: ratio as NSNumber) * 100))%")
        } else {
            return String(localized: "节奏平稳，前后两段消耗接近")
        }
    }

    /// 建议文字
    var suggestion: String {
        guard let peak = peakBucket else { return "" }
        let ratio = peak.maxAmount > 0 ? Double(truncating: (peak.amount / peak.maxAmount) as NSNumber) : 0
        if ratio >= 0.85 {
            let df = DateFormatter()
            df.dateFormat = "M/d"
            let start = df.string(from: peak.startDate)
            let end = df.string(from: peak.endDate)
            return String(localized: "近期消耗强度极高（\(start)-\(end)），建议关注该区间的支出项目")
        } else if isAccelerating {
            return String(localized: "消耗呈上升趋势，建议留意近期预算执行情况")
        } else {
            return String(localized: "整体节奏可控，保持当前消费习惯")
        }
    }
}

// MARK: - Burn Rate Bar Chart (多米诺骨牌动画，Animatable 驱动)

struct BurnRateBarChart: View, Animatable {
    let data: [BurnRateBucket]
    var progress: Double  // 父 View 驱动，Animatable 逐帧插值

    private let maxH: CGFloat = 44
    private let minH: CGFloat = 3

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(data) { bucket in
                RoundedRectangle(cornerRadius: 2)
                    .fill(barColor(bucket))
                    .frame(width: nil, height: animatedHeight(bucket))
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(minHeight: maxH)
    }

    private func animatedHeight(_ bucket: BurnRateBucket) -> CGFloat {
        let baseH = bucket.maxAmount > 0
            ? max(minH, CGFloat(truncating: (bucket.amount / bucket.maxAmount) as NSNumber) * maxH)
            : minH
        let count = max(1, data.count)
        let step = 1.0 / Double(count)
        let barStart = Double(bucket.index) * step
        let barProgress = max(0.0, min(1.0, (progress - barStart) / step))
        return baseH * barProgress
    }

    private func barColor(_ bucket: BurnRateBucket) -> Color {
        if bucket.amount <= 0 { return Color.designOnSurfaceVariant.opacity(0.12) }
        let ratio = bucket.maxAmount > 0 ? CGFloat(truncating: (bucket.amount / bucket.maxAmount) as NSNumber) : 0
        let hue = (1.0 - ratio) * 0.33
        return Color(hue: hue, saturation: 0.75, brightness: 0.85)
            .opacity(0.35 + ratio * 0.45)
    }
}
