import SwiftUI
import Charts
#if canImport(AppKit)
import AppKit
#endif

// MARK: - Waterfall Item

private struct WaterfallItem: Identifiable {
    let id = UUID()
    /// 唯一 X 分类值：避免同名类型（资产/负债两侧）挤到同一 X 位置
    let axisKey: String
    let label: String   // X 轴显示名
    let amount: Decimal
    let runningStart: Decimal
    let runningEnd: Decimal
    let isAsset: Bool
    let isSummary: Bool
}

// MARK: - Main View

struct MacAssetAllocationView: View {
    let items: [AccountAllocationItem]
    let netWorth: Decimal
    @Binding var filter: AllocationFilter

    @State private var animTrigger = false
    @State private var barProgress: Double = 0
    @State private var hoveredBar: String?
    /// 瀑布图下钻目标（nil = L1 类型聚合视图；非 nil = L2 该类型账户明细）
    @State private var drilled: DrillKey?

    private var currencyCode: String { "CNY" }

    // MARK: - Drill-down Model

    /// 下钻/聚合节点类型别名：直接复用共享层 AccountAllocationItem.AllocationNode
    private typealias AllocationNode = AccountAllocationItem.AllocationNode
    private typealias DrillKey = AccountAllocationItem.DrillKey

    /// L1：按 (具体类型, 侧) 聚合（共享 helper）
    private func aggregatedNodes() -> [AllocationNode] { AllocationAggregator.aggregate(items) }

    private var l1AssetNodes: [AllocationNode] { aggregatedNodes().filter { !$0.isLiability } }
    private var l1LiabilityNodes: [AllocationNode] { aggregatedNodes().filter { $0.isLiability } }

    /// L2：下钻后该类型该侧的账户明细
    private var drillNodes: [AllocationNode] {
        guard let key = drilled else { return [] }
        return AllocationAggregator.drillDown(items, to: key)
    }

    private var totalAssets: Decimal {
        items.filter { !$0.isLiability }.reduce(0) { $0 + $1.balance }
    }

    private var totalLiabilities: Decimal {
        items.filter { $0.isLiability }.reduce(0) { $0 + abs($1.balance) }
    }

    // MARK: - Waterfall Data

    private var waterfallData: [WaterfallItem] {
        if drilled != nil { return buildDrillWaterfall() }
        switch filter {
        case .all: return buildAllWaterfall()
        case .assets: return buildAssetsWaterfall()
        case .liabilities: return buildLiabilitiesWaterfall()
        }
    }

    /// Minimum visual bar height to keep tiny amounts visible. 必须按**当前显示的侧**取量纲，
    /// 否则 `.liabilities` 视图下会被 `.all` 全局最大值（通常总资产远大于总负债）压得所有小柱同高。
    private var minBarHeight: Decimal {
        let scale: Decimal
        if drilled != nil {
            scale = drillNodes.reduce(Decimal.zero) { $0 + abs($1.balance) }
        } else {
            switch filter {
            case .all:        scale = max(totalAssets, totalLiabilities)
            case .assets:     scale = totalAssets
            case .liabilities: scale = totalLiabilities
            }
        }
        return scale > 0 ? scale / 50 : 0
    }

    /// Clamp small bars to a visible height; the logical `end` is returned separately
    private func clampedVisual(start: Decimal, logicalEnd: Decimal) -> (visualEnd: Decimal, logical: Decimal) {
        let height = abs(logicalEnd - start)
        if height > 0 && height < minBarHeight {
            return (logicalEnd > start ? start + minBarHeight : start - minBarHeight, logicalEnd)
        }
        return (logicalEnd, logicalEnd)
    }

    private func buildAllWaterfall() -> [WaterfallItem] {
        var result: [WaterfallItem] = []
        let assets = l1AssetNodes
        let liabilities = l1LiabilityNodes

        // 1. Build up: each asset account accumulates left → right
        var running = Decimal.zero
        for item in assets {
            let logicalEnd = running + item.balance
            let (visual, _) = clampedVisual(start: running, logicalEnd: logicalEnd)
            result.append(WaterfallItem(
                axisKey: item.id, label: item.name, amount: item.balance,
                runningStart: running, runningEnd: visual,
                isAsset: true, isSummary: false
            ))
            running = logicalEnd
        }

        // 2. Total assets summary bar
        result.append(WaterfallItem(
            axisKey: "summary|assets", label: String(localized: "总资产"), amount: totalAssets,
            runningStart: 0, runningEnd: totalAssets,
            isAsset: true, isSummary: true
        ))

        // 3. Deduct each liability from running total
        running = totalAssets
        for item in liabilities {
            let absBal = abs(item.balance)
            let logicalEnd = running - absBal
            let (visual, _) = clampedVisual(start: running, logicalEnd: logicalEnd)
            result.append(WaterfallItem(
                axisKey: item.id, label: item.name, amount: -absBal,
                runningStart: running, runningEnd: visual,
                isAsset: false, isSummary: false
            ))
            running = logicalEnd
        }

        // 4. Net worth summary
        result.append(WaterfallItem(
            axisKey: "summary|net", label: String(localized: "净资产"), amount: netWorth,
            runningStart: 0, runningEnd: netWorth,
            isAsset: netWorth >= 0, isSummary: true
        ))

        return result
    }

    private func buildAssetsWaterfall() -> [WaterfallItem] {
        var result: [WaterfallItem] = []
        let assets = l1AssetNodes

        var running = Decimal.zero
        for item in assets {
            let logicalEnd = running + item.balance
            let (visual, _) = clampedVisual(start: running, logicalEnd: logicalEnd)
            result.append(WaterfallItem(
                axisKey: item.id, label: item.name, amount: item.balance,
                runningStart: running, runningEnd: visual,
                isAsset: true, isSummary: false
            ))
            running = logicalEnd
        }

        result.append(WaterfallItem(
            axisKey: "summary|assets", label: String(localized: "总资产"), amount: totalAssets,
            runningStart: 0, runningEnd: totalAssets,
            isAsset: true, isSummary: true
        ))

        return result
    }

    private func buildLiabilitiesWaterfall() -> [WaterfallItem] {
        var result: [WaterfallItem] = []
        let liabilities = l1LiabilityNodes

        // Cascading waterfall: each liability starts from where the previous one ended
        var running = Decimal.zero
        for item in liabilities {
            let absBal = abs(item.balance)
            let logicalEnd = running - absBal
            let (visual, _) = clampedVisual(start: running, logicalEnd: logicalEnd)
            result.append(WaterfallItem(
                axisKey: item.id, label: item.name, amount: -absBal,
                runningStart: running, runningEnd: visual,
                isAsset: false, isSummary: false
            ))
            running = logicalEnd
        }

        result.append(WaterfallItem(
            axisKey: "summary|liab", label: String(localized: "总负债"), amount: totalLiabilities,
            runningStart: 0, runningEnd: -totalLiabilities,
            isAsset: false, isSummary: true
        ))

        return result
    }

    /// L2：下钻某类型后，展开该类型内各账户的瀑布，末尾附该类型小计条
    private func buildDrillWaterfall() -> [WaterfallItem] {
        guard let key = drilled else { return [] }
        var result: [WaterfallItem] = []
        let nodes = drillNodes

        if key.isLiability {
            var running = Decimal.zero
            for node in nodes {
                let absBal = abs(node.balance)
                let logicalEnd = running - absBal
                let (visual, _) = clampedVisual(start: running, logicalEnd: logicalEnd)
                result.append(WaterfallItem(
                    axisKey: node.id, label: node.name, amount: -absBal,
                    runningStart: running, runningEnd: visual,
                    isAsset: false, isSummary: false
                ))
                running = logicalEnd
            }
            let subtotal = nodes.reduce(Decimal.zero) { $0 + abs($1.balance) }
            result.append(WaterfallItem(
                axisKey: "summary|drill", label: key.displayName, amount: subtotal,
                runningStart: 0, runningEnd: -subtotal,
                isAsset: false, isSummary: true
            ))
        } else {
            var running = Decimal.zero
            for node in nodes {
                let logicalEnd = running + node.balance
                let (visual, _) = clampedVisual(start: running, logicalEnd: logicalEnd)
                result.append(WaterfallItem(
                    axisKey: node.id, label: node.name, amount: node.balance,
                    runningStart: running, runningEnd: visual,
                    isAsset: true, isSummary: false
                ))
                running = logicalEnd
            }
            let subtotal = nodes.reduce(Decimal.zero) { $0 + $1.balance }
            result.append(WaterfallItem(
                axisKey: "summary|drill", label: key.displayName, amount: subtotal,
                runningStart: 0, runningEnd: subtotal,
                isAsset: true, isSummary: true
            ))
        }

        return result
    }

    /// Thin dashed connector line data — traces the running total across non-summary bars
    private struct ConnectorPoint: Identifiable {
        let id = UUID()
        let axisKey: String
        let value: Decimal
    }

    private var connectorData: [ConnectorPoint] {
        waterfallData.filter { !$0.isSummary }.map {
            ConnectorPoint(axisKey: $0.axisKey, value: $0.runningEnd)
        }
    }

    /// axisKey → 显示名映射，供 X 轴标签渲染（BarMark 用唯一 axisKey 定位，标签显示 label）
    private var axisLabelMap: [String: String] {
        Dictionary(waterfallData.map { ($0.axisKey, $0.label) }, uniquingKeysWith: { first, _ in first })
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            if items.isEmpty {
                emptyView
            } else {
                waterfallSection
                treemapSection
            }
        }
        .onAppear(perform: triggerAnimations)
        .onChange(of: items.map(\.id)) { _, _ in drilled = nil; triggerAnimations() }
        .onChange(of: filter) { _, _ in drilled = nil; triggerAnimations() }
        .onChange(of: drilled) { _, _ in triggerAnimations() }
    }

    /// L1 点选类型柱 → 下钻；汇总条/叶子账户柱不响应。
    /// hoveredBar 由 chartOverlay 的 onContinuousHover 提供，值为柱子的唯一 axisKey。
    private func handleSelection(_ axisKey: String?) {
        guard drilled == nil, let axisKey else { return }
        if let node = aggregatedNodes().first(where: { $0.id == axisKey && $0.drillKey != nil }) {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                drilled = node.drillKey
            }
        }
    }

    private var emptyView: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.bar.fill")
                .font(.system(size: 40))
                .foregroundStyle(Color.designOnSurfaceVariant.opacity(0.4))
            Text(String(localized: "暂无账户数据"))
                .font(.designBodyMedium)
                .foregroundStyle(Color.designOnSurfaceVariant)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Waterfall Chart

    private var waterfallSection: some View {
        VStack(spacing: 0) {
            summaryBar
                .padding(.horizontal, 24)
                .padding(.bottom, 8)

            Chart {
                ForEach(Array(waterfallData.enumerated()), id: \.element.id) { i, item in
                    waterfallBar(i: i, item: item)
                }

                // Connector: dashed brand-colored running-total trace
                ForEach(connectorData) { point in
                    LineMark(
                        x: .value("", point.axisKey),
                        y: .value("", point.value)
                    )
                }
                .foregroundStyle(Color.designPrimaryFixedDim.opacity(0.25))
                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [3, 6]))

                // Zero baseline: thicker anchor line to ground the waterfall
                RuleMark(y: .value("Zero", 0))
                    .foregroundStyle(Color.designOnSurfaceVariant.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
            }
            .chartOverlay { proxy in
                GeometryReader { geo in
                    Color.clear
                        .contentShape(Rectangle())
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let location):
                                if let key = proxy.value(atX: location.x, as: String.self) {
                                    hoveredBar = key
                                }
                            case .ended:
                                hoveredBar = nil
                            }
                        }
                        .onTapGesture {
                            handleSelection(hoveredBar)
                        }
                }
            }
            .chartBackground { _ in
                LinearGradient(
                    stops: [
                        .init(color: Color.designOnSurfaceVariant.opacity(0.04), location: 0),
                        .init(color: .clear, location: 0.5)
                    ],
                    startPoint: .bottom, endPoint: .top
                )
            }
            .chartXAxis {
                AxisMarks(values: .automatic) { value in
                    AxisValueLabel {
                        if let key = value.as(String.self) {
                            Text(axisLabelMap[key] ?? key)
                                .font(.system(size: 11))
                                .foregroundStyle(Color.designOnSurfaceVariant)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(values: .automatic) { value in
                    AxisGridLine()
                        .foregroundStyle(Color.designOnSurfaceVariant.opacity(0.15))
                    AxisValueLabel {
                        if let decimal = value.as(Decimal.self) {
                            Text(CurrencyFormatter.formatAdaptive(amount: decimal, currencyCode: currencyCode))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(Color.designOnSurfaceVariant.opacity(0.6))
                        }
                    }
                }
            }
            .frame(height: 240)
            .padding(20)
            .glassCard(cornerRadius: 20)
            .designGrain()
            .overlay(alignment: .topLeading) {
                if let key = drilled {
                    breadcrumbBar(key)
                        .padding(10)
                } else if totalAssets > 0, totalLiabilities > 0 {
                    let ratio = Double(truncating: (totalLiabilities / totalAssets) as NSNumber)
                    let ratioColor: Color = ratio < 0.3 ? .designPrimaryFixedDim
                        : ratio < 0.6 ? .orange
                        : .designAccentRed
                    let gaugeW: CGFloat = 56
                    let gaugeH: CGFloat = 6
                    let fillW = max(gaugeH, gaugeW * CGFloat(ratio))
                    HStack(spacing: 5) {
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.designOnSurfaceVariant.opacity(0.15))
                                .frame(width: gaugeW, height: gaugeH)
                            Capsule()
                                .fill(ratioColor)
                                .frame(width: fillW, height: gaugeH)
                        }
                        Text(String(format: "%.1f%%", ratio * 100))
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(ratioColor)
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 6).fill(.ultraThinMaterial))
                    .padding(10)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
        }
    }

    private var summaryBar: some View {
        HStack(spacing: 24) {
            summaryCell(
                label: String(localized: "总资产"), amount: totalAssets,
                color: Color.designPrimaryFixedDim
            )
            summaryCell(
                label: String(localized: "总负债"), amount: totalLiabilities,
                color: Color.designAccentRed
            )
            summaryCell(
                label: String(localized: "净资产"), amount: netWorth,
                color: netWorth >= 0 ? Color.designPrimaryFixedDim : Color.designAccentRed
            )
        }
    }

    /// L2 面包屑：图表内玻璃按钮，点击返回类型聚合视图
    private func breadcrumbBar(_ key: DrillKey) -> some View {
        Button {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { drilled = nil }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .semibold))
                Image(systemName: key.iconName)
                    .font(.system(size: 11))
                Text(key.displayName)
                    .font(.designBodyCaption)
            }
        }
        .buttonStyle(DesignGlassTextButton())
    }

    private func barColor(_ item: WaterfallItem) -> Color {
        item.isAsset ? Color.designPrimaryFixedDim : Color.designAccentRed
    }

    /// "+¥20,610" or "−¥3,200" for change annotations
    @ChartContentBuilder
    private func waterfallBar(i: Int, item: WaterfallItem) -> some ChartContent {
        let end = animTrigger ? item.runningEnd : item.runningStart
        BarMark(
            x: .value("", item.axisKey),
            yStart: .value("Start", item.runningStart),
            yEnd: .value("End", end),
            width: .fixed(item.isSummary ? 44 : 24)
        )
        .foregroundStyle(barFill(for: item))
        .cornerRadius(4)
        .shadow(color: item.isSummary ? barColor(item).opacity(0.35) : .clear, radius: 6, y: 2)
        .annotation(position: item.isSummary ? .top : .automatic) {
            annotationText(for: item)
        }
    }

    private func annotationText(for item: WaterfallItem) -> some View {
        if item.isSummary {
            Text(CurrencyFormatter.formatAdaptive(amount: item.runningEnd, currencyCode: currencyCode))
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.designOnSurfaceVariant)
        } else {
            Text(amountLabel(item.amount))
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(Color.designOnSurfaceVariant.opacity(0.7))
        }
    }

    private func amountLabel(_ amount: Decimal) -> String {
        let prefix = amount >= 0 ? "+" : ""
        return prefix + CurrencyFormatter.formatAdaptive(amount: amount, currencyCode: currencyCode)
    }

    private func barFill(for item: WaterfallItem) -> AnyShapeStyle {
        if item.isSummary {
            let c = barColor(item)
            return AnyShapeStyle(LinearGradient(
                stops: [
                    .init(color: c.opacity(1.0), location: 0),
                    .init(color: c.opacity(0.55), location: 1)
                ],
                startPoint: .top, endPoint: .bottom
            ))
        }
        return AnyShapeStyle(barColor(item).opacity(0.7))
    }

    private func summaryCell(label: String, amount: Decimal, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.designBodyCaption)
                .foregroundStyle(Color.designOnSurfaceVariant)
            CurrencyText(amount: amount, currencyCode: currencyCode)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .glassCard(cornerRadius: 12)
    }

    // MARK: - Treemap

    /// Lightweight squarified-layout treemap showing asset distribution by area.
    private struct TreemapRect: Identifiable {
        let id: String        // 稳定键 = 节点 id，避免下钻重算时 ForEach 全量重建
        let item: AllocationNode
        var frame: CGRect  // normalized 0…1
    }

    /// 树图与瀑布图共用两级模型：L1 类型聚合、L2 下钻账户明细
    private var treemapDisplayNodes: [AllocationNode] {
        if drilled != nil { return drillNodes }
        switch filter {
        case .all: return aggregatedNodes()
        case .assets: return l1AssetNodes
        case .liabilities: return l1LiabilityNodes
        }
    }

    /// 水平条带布局：将 items 按 balance 比例分配到 zone，返回以 zone 原点为基准的 normalized rect
    private func stripLayout(items: [AllocationNode], in rect: CGRect) -> [TreemapRect] {
        guard !items.isEmpty else { return [] }
        let total = items.reduce(Decimal.zero) { $0 + abs($1.balance) }
        guard total > 0 else { return [] }

        var result: [TreemapRect] = []
        var offset: CGFloat = 0

        for item in items {
            let fraction = CGFloat(truncating: (abs(item.balance) / total) as NSNumber)
            let width = max(0.001, fraction)
            result.append(TreemapRect(
                id: item.id,
                item: item,
                frame: CGRect(x: rect.minX + offset, y: rect.minY, width: width, height: rect.height)
            ))
            offset += width
        }
        return result
    }

    private var treemapRects: [TreemapRect] {
        // L1 全部：上资产 / 下负债 双行
        if drilled == nil, filter == .all {
            let assetItems = l1AssetNodes.sorted { abs($0.balance) > abs($1.balance) }
            let liabilityItems = l1LiabilityNodes.sorted { abs($0.balance) > abs($1.balance) }
            let totalAll = totalAssets + totalLiabilities
            guard totalAll > 0 else { return [] }

            let assetFrac = CGFloat(truncating: (totalAssets / totalAll) as NSNumber)
            let rowGap: CGFloat = 0.02  // 上下两行之间的间隙

            var result: [TreemapRect] = []
            // 上半：资产
            if !assetItems.isEmpty {
                let assetRowHeight = (assetFrac - rowGap / 2) * (1 - rowGap)
                let zone = CGRect(x: 0, y: 0, width: 1, height: max(0.001, assetRowHeight))
                result += stripLayout(items: assetItems, in: zone)
            }
            // 下半：负债
            if !liabilityItems.isEmpty {
                let liabRowHeight = ((1 - assetFrac) - rowGap / 2) * (1 - rowGap)
                let zone = CGRect(x: 0, y: 1 - max(0.001, liabRowHeight), width: 1, height: max(0.001, liabRowHeight))
                result += stripLayout(items: liabilityItems, in: zone)
            }
            return result
        }

        // L2 下钻 或 单侧 filter：单区铺满
        let items = treemapDisplayNodes.sorted { abs($0.balance) > abs($1.balance) }
        guard !items.isEmpty else { return [] }
        return stripLayout(items: items, in: CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    private var treemapSection: some View {
        GeometryReader { geo in
            let size = geo.size.width > 0 && geo.size.height > 0 ? geo.size : CGSize(width: 400, height: 300)
            let padding: CGFloat = 4

            ZStack(alignment: .topLeading) {
                ForEach(treemapRects) { rect in
                    treemapCell(rect: rect, containerSize: size, padding: padding)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: 260)
        .padding(12)
        .glassCard(cornerRadius: 20)
        .designGrain()
        .padding(.horizontal, 24)
        .padding(.top, 12)
    }

    /// L1：占比 = 类型额 / 该侧总额；L2：占比 = 账户额 / 下钻类型小计
    private func categoryPercentage(for item: AllocationNode) -> Double {
        let total: Decimal
        if drilled != nil {
            total = drillNodes.reduce(Decimal.zero) { $0 + abs($1.balance) }
        } else {
            total = item.isLiability ? totalLiabilities : totalAssets
        }
        guard total > 0 else { return 0 }
        return Double(truncating: (abs(item.balance) / total) as NSNumber)
    }

    /// Apple HIG: single hue per category, saturation = weight → larger blocks more saturated
    private func treemapColor(for item: AllocationNode) -> Color {
        let pct = categoryPercentage(for: item)
        let opacity = 0.35 + pct * 0.55
        if item.isLiability {
            return Color.designAccentRed.opacity(opacity)
        }
        return Color.designPrimaryFixedDim.opacity(opacity)
    }

    private func treemapCell(rect: TreemapRect, containerSize: CGSize, padding: CGFloat) -> some View {
        let item = rect.item
        let fill = treemapColor(for: item)
        // Absolute pixel position of the cell's top-left corner
        let cellX = rect.frame.minX * containerSize.width
        let cellY = rect.frame.minY * containerSize.height
        let cellW = max(1, rect.frame.width * containerSize.width)
        let cellH = max(1, rect.frame.height * containerSize.height)
        // Inner content area after padding
        let x = cellX + padding
        let y = cellY + padding
        let w = max(1, cellW - padding * 2)
        let h = max(1, cellH - padding * 2)

        return ZStack {
            // Tappable overlay
            Color.clear
                .contentShape(Rectangle())
                .frame(width: cellW, height: cellH)
                .position(x: cellX + cellW / 2, y: cellY + cellH / 2)
                .onTapGesture {
                    if let key = item.drillKey {
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { drilled = key }
                    }
                }
                .onHover { hovering in
                    guard item.drillKey != nil else { return }
                    #if canImport(AppKit)
                    if hovering { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
                    #endif
                }

            // Visual content
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(fill)
                    .shadow(color: .black.opacity(0.25), radius: 3, y: 2)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.white.opacity(0.25), lineWidth: 0.5)
                    )

                if w > 60, h > 36 {
                    let pad = min(8, w * 0.06, h * 0.08)
                    VStack(spacing: 0) {
                        HStack(alignment: .top) {
                            HStack(spacing: 3) {
                                Image(systemName: item.iconName)
                                    .font(.system(size: min(12, h * 0.35)))
                                    .foregroundStyle(.white.opacity(0.9))
                                Text(item.name)
                                    .font(.system(size: min(11, w * 0.07), weight: .medium))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                            }
                            Spacer()
                        }
                        Spacer()
                        HStack {
                            Spacer()
                            VStack(alignment: .trailing, spacing: 1) {
                                CurrencyText(amount: abs(item.balance), currencyCode: currencyCode)
                                    .font(.system(size: min(13, w * 0.08), weight: .bold, design: .monospaced))
                                    .foregroundStyle(.white)
                                Text(String(format: "%.1f%%", categoryPercentage(for: item) * 100))
                                    .font(.system(size: min(10, w * 0.06), design: .monospaced))
                                    .foregroundStyle(.white.opacity(0.7))
                            }
                        }
                    }
                    .padding(pad)
                } else if w > 36, h > 20 {
                    Text(String(format: "%.0f%%", categoryPercentage(for: item) * 100))
                        .font(.system(size: min(10, w * 0.15), weight: .bold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
            .frame(width: cellW, height: cellH)
            .position(x: cellX + cellW / 2, y: cellY + cellH / 2)
            .opacity(barProgress > 0 ? 1 : 0)
            .animation(.spring(response: 0.6, dampingFraction: 0.65).delay(Double(treemapRects.firstIndex(where: { $0.id == rect.id }) ?? 0) * 0.05), value: barProgress)
            .allowsHitTesting(false)
        }
    }

    // MARK: - Animation

    private func triggerAnimations() {
        animTrigger = false
        barProgress = 0
        hoveredBar = nil

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                animTrigger = true
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.65)) {
                barProgress = 1
            }
        }
    }
}
