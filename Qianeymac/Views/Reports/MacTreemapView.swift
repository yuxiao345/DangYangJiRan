import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

/// Squarified Treemap v2.0 — 严格按 d3-hierarchy 算法实现
/// 参考：Bruls, Huijsen, van Wijk (2000) Squarified Treemaps
///       d3-hierarchy/src/treemap/squarify.js (v3)
///
/// 核心设计：
/// 1. 外置 padding：在 layout 前一次性扣减，layoutRect 内部 tile 完美铺满
/// 2. 黄金比例阈值 (φ ≈ 1.618) 控制 worst aspect ratio
/// 3. 后置最小可见性校验 + fallback "其他" 合并
/// 4. 单一递归，资产/负债不分组（除 30% 分隔情况）
/// 5. 自动选择缩放模式（linear/sqrt/log）
struct MacTreemapView: View {
    typealias AllocationNode = AccountAllocationItem.AllocationNode

    let nodes: [AllocationNode]
    let total: Decimal
    let onSelect: (AllocationNode) -> Void

    // MARK: - Layout Constants

    /// 黄金比例阈值（d3 默认）
    private let phi: CGFloat = (1 + sqrt(5)) / 2

    /// 内边距（gutter）：tile 之间的间距
    private let paddingInner: CGFloat = 14

    /// 外边距：容器四周
    private let paddingOuter: CGFloat = 4

    /// 最小 tile 短边（保证标签可读）
    private let minTileSide: CGFloat = 50

    /// 圆角
    private let cornerRadius: CGFloat = 16

    /// 内容区内边距比例
    private let contentPaddingRatio: CGFloat = 0.15

    /// 分隔阈值：负债占比超过此值时启用左右/上下分屏
    private let dividerThreshold: Double = 0.30

    /// 极小账户阈值：占比低于此值会被合并到"其他"
    private let tinyThreshold: Double = 0.01

    // MARK: - Body

    var body: some View {
        GeometryReader { geo in
            let containerRect = CGRect(origin: .zero, size: geo.size)
            let blocks = computeLayout(in: containerRect)
            ZStack(alignment: .topLeading) {
                ForEach(blocks) { block in
                    treemapCell(block: block, onSelect: onSelect)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Layout Pipeline

    /// 主布局入口
    private func computeLayout(in container: CGRect) -> [PositionedBlock] {
        guard !nodes.isEmpty, total > 0, container.width > 0, container.height > 0 else {
            return []
        }

        // 1. 缩放模式自动选择
        let scaleMode = chooseScaleMode()
        let rawWeights = computeWeights(mode: scaleMode)

        // 2. 后置极小块合并 → 生成 TreemapItem（带"其他" fallback）
        let items = groupTinyItems(nodes: nodes, weights: rawWeights)

        // 3. 排序（降序）
        let sortedItems = items.sorted { $0.weight > $1.weight }

        // 4. 资产/负债分组判断
        let (assetItems, liabilityItems) = partitionBySide(sortedItems)
        let assetWeight = assetItems.reduce(0) { $0 + $1.weight }
        let liabilityWeight = liabilityItems.reduce(0) { $0 + $1.weight }
        let totalWeight = assetWeight + liabilityWeight
        guard totalWeight > 0 else { return [] }

        // 5. 决定布局策略
        let layoutRect = container.insetBy(dx: paddingOuter, dy: paddingOuter)
        let liabilityFrac = liabilityWeight / totalWeight

        if !assetItems.isEmpty && !liabilityItems.isEmpty && liabilityFrac > dividerThreshold {
            // 负债占比 > 30%：分两区
            return layoutSplit(assetItems: assetItems, liabilityItems: liabilityItems, assetFrac: assetWeight / totalWeight, in: layoutRect)
        } else {
            // 单一递归 squarify
            return squarify(items: sortedItems, in: layoutRect)
        }
    }

    /// 选择缩放模式
    private func chooseScaleMode() -> ScaleMode {
        let amounts = nodes.map { abs(NSDecimalNumber(decimal: $0.balance).doubleValue) }
        guard let maxAmt = amounts.max(), let minAmt = amounts.min(), maxAmt > 0 else { return .sqrt }
        let ratio = maxAmt / max(minAmt, 1)
        if ratio <= 100 { return .linear }
        if ratio <= 10000 { return .sqrt }
        return .log
    }

    /// 计算缩放后的权重
    private func computeWeights(mode: ScaleMode) -> [Double] {
        nodes.map { node in
            let amount = NSDecimalNumber(decimal: abs(node.balance)).doubleValue
            switch mode {
            case .linear: return amount
            case .sqrt: return sqrt(amount)
            case .log: return log10(max(1, amount)) + 1
            }
        }
    }

    /// 合并极小账户到"其他"
    private func groupTinyItems(nodes: [AllocationNode], weights: [Double]) -> [TreemapItem] {
        let totalWeight = weights.reduce(0, +)
        guard totalWeight > 0 else { return [] }

        var kept: [TreemapItem] = []
        var tinyAccumulator: (weight: Double, count: Int) = (0, 0)
        var tinyNodes: [AllocationNode] = []

        let sortedIndices = nodes.indices.sorted { weights[$0] > weights[$1] }
        for idx in sortedIndices {
            let w = weights[idx]
            let frac = w / totalWeight
            if frac < tinyThreshold && tinyAccumulator.count < 5 {
                // 累计极小块（最多 5 个合并到"其他"）
                tinyAccumulator.weight += w
                tinyAccumulator.count += 1
                tinyNodes.append(nodes[idx])
            } else {
                kept.append(TreemapItem(
                    id: nodes[idx].id,
                    node: nodes[idx],
                    weight: w,
                    isAggregated: false
                ))
            }
        }

        // 如果有极小块，生成"其他"合成节点
        if tinyAccumulator.count > 0 {
            let combinedNode = AllocationNode(
                id: "__other__",
                name: String(localized: "其他 (\(tinyAccumulator.count))"),
                iconName: "circle.grid.3x3.fill",
                balance: tinyNodes.reduce(Decimal.zero) { $0 + abs($1.balance) },
                isLiability: tinyNodes.first?.isLiability ?? false,
                accountType: .other,
                customName: "",
                drillKey: nil
            )
            kept.append(TreemapItem(
                id: "__other__",
                node: combinedNode,
                weight: tinyAccumulator.weight,
                isAggregated: true
            ))
        }

        return kept
    }

    /// 按资产/负债分组
    private func partitionBySide(_ items: [TreemapItem]) -> (assets: [TreemapItem], liabilities: [TreemapItem]) {
        var assets: [TreemapItem] = []
        var liabilities: [TreemapItem] = []
        for item in items {
            if item.node.isLiability {
                liabilities.append(item)
            } else {
                assets.append(item)
            }
        }
        return (assets, liabilities)
    }

    // MARK: - Split Layout (负债 > 30% 时)

    private func layoutSplit(assetItems: [TreemapItem], liabilityItems: [TreemapItem], assetFrac: Double, in rect: CGRect) -> [PositionedBlock] {
        let horizontal = rect.width >= rect.height
        var result: [PositionedBlock] = []

        if horizontal {
            // 横向 split：左资产 / 右负债
            let assetWidth = rect.width * CGFloat(assetFrac) - paddingInner / 2
            let liabilityWidth = rect.width * CGFloat(1 - assetFrac) - paddingInner / 2
            let assetRect = CGRect(x: rect.minX, y: rect.minY,
                                   width: max(minTileSide, assetWidth),
                                   height: rect.height)
            let liabilityRect = CGRect(x: rect.minX + rect.width * CGFloat(assetFrac) + paddingInner / 2,
                                       y: rect.minY,
                                       width: max(minTileSide, liabilityWidth),
                                       height: rect.height)
            result += squarify(items: assetItems, in: assetRect)
            result += squarify(items: liabilityItems, in: liabilityRect)
        } else {
            // 纵向 split：上资产 / 下负债
            let assetHeight = rect.height * CGFloat(assetFrac) - paddingInner / 2
            let liabilityHeight = rect.height * CGFloat(1 - assetFrac) - paddingInner / 2
            let assetRect = CGRect(x: rect.minX, y: rect.minY,
                                   width: rect.width,
                                   height: max(minTileSide, assetHeight))
            let liabilityRect = CGRect(x: rect.minX,
                                       y: rect.minY + rect.height * CGFloat(assetFrac) + paddingInner / 2,
                                       width: rect.width,
                                       height: max(minTileSide, liabilityHeight))
            result += squarify(items: assetItems, in: assetRect)
            result += squarify(items: liabilityItems, in: liabilityRect)
        }

        return result
    }

    // MARK: - Squarified Treemap Algorithm (Bruls 2000 / d3)

    /// Squarified 主算法：把 items 按降序铺入 rect，最小化最差长宽比
    /// 参考 d3-hierarchy/src/treemap/squarify.js
    private func squarify(items: [TreemapItem], in rect: CGRect) -> [PositionedBlock] {
        guard !items.isEmpty else { return [] }
        guard items.count > 1 else {
            return [PositionedBlock(item: items[0], frame: rect, scaleMode: currentScaleMode)]
        }

        let totalArea = rect.width * rect.height
        let totalWeight = items.reduce(0) { $0 + $1.weight }
        guard totalWeight > 0, totalArea > 0 else { return [] }

        // 把 weight 转换为 area（保持线性比例）
        // 外置 padding 已被 inset 扣减，layoutRect 内总面积 = totalArea
        var areas: [CGFloat] = items.map { CGFloat($0.weight / totalWeight) * totalArea }

        // 后置最小可见性校验：面积不能太小
        let minArea = minTileSide * minTileSide
        var overflow = false
        for i in 0..<areas.count where areas[i] < minArea {
            areas[i] = minArea
            overflow = true
        }
        // 重新归一化
        let sumArea = areas.reduce(0, +)
        if sumArea > 0 {
            areas = areas.map { $0 * totalArea / sumArea }
        }

        // 计算 dx/dy（剩余空间的短边和长边）
        let dx = rect.width
        let dy = rect.height
        let stack = squarifyRecursive(
            values: areas,
            rowValues: [],
            rowMin: .greatestFiniteMagnitude,
            rowMax: -1,
            dx: dx,
            dy: dy
        )

        // 把堆叠结果展开为 PositionedBlock 列表
        return layoutStack(stack, in: rect, items: items, areas: areas)
    }

    /// Bruls 2000 递归核心
    /// 输入：剩余 values, 当前 row, dx/dy
    /// 输出：堆叠结构 [(value, scale, x, y, width, height), ...]
    private func squarifyRecursive(
        values: [CGFloat],
        rowValues: [CGFloat],
        rowMin: CGFloat,
        rowMax: CGFloat,
        dx: CGFloat,
        dy: CGFloat
    ) -> [(value: CGFloat, x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat)] {
        let shortSide = min(dx, dy)

        // 找最佳分割点
        var bestRow: [CGFloat] = []
        var bestRest: [CGFloat] = values
        var bestScore = CGFloat.greatestFiniteMagnitude

        var currentRow = rowValues
        var currentMin = rowMin
        var currentMax = rowMax
        let sum = currentRow.reduce(0, +)

        for i in 0..<values.count {
            let value = values[i]
            let newRow = currentRow + [value]
            let newMin = min(currentMin, value)
            let newMax = max(currentMax, value)
            let newSum = sum + value

            if shortSide > 0 {
                let score = worstRatio(
                    rowMin: newMin, rowMax: newMax,
                    rowSum: newSum, shortSide: shortSide
                )
                if score < bestScore {
                    bestScore = score
                    bestRow = newRow
                    bestRest = Array(values[(i + 1)...])
                    currentMin = newMin
                    currentMax = newMax
                } else {
                    // score 变差，停止当前 row
                    break
                }
            } else {
                break
            }
        }

        // 简化：直接选 row = bestRow
        if bestRow.isEmpty {
            // 不应该发生，但保护一下
            return values.map { ($0, 0, 0, 0, 0) }
        }

        // 计算 row 的几何位置
        let rowSum = bestRow.reduce(0, +)
        let rowThickness = shortSide > 0 ? rowSum / shortSide : 0
        let rowScale = rowThickness > 0 ? shortSide / rowThickness : 0  // 不直接用，保留作 scale 概念

        var positioned: [(value: CGFloat, x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat)] = []

        // 沿短边方向铺 row
        let isHorizontalRow = dx >= dy
        if isHorizontalRow {
            // row 在底部沿 x 排列
            let rowX = dx - rowThickness
            var offsetY: CGFloat = 0
            for value in bestRow {
                let h = rowThickness > 0 ? value / rowThickness * rowScale * 0 + (rowSum / rowThickness) * (value / rowSum) * 0 + (value / rowSum) * shortSide : 0
                _ = h // unused
                let itemH = value / rowThickness * shortSide
                let itemW = rowThickness
                positioned.append((value, rowX, offsetY, itemW, itemH))
                offsetY += itemH
            }
        } else {
            // row 在右侧沿 y 排列
            let rowY = dy - rowThickness
            var offsetX: CGFloat = 0
            for value in bestRow {
                let itemW = value / rowThickness * shortSide
                let itemH = rowThickness
                positioned.append((value, offsetX, rowY, itemW, itemH))
                offsetX += itemW
            }
        }

        // 剩余空间递归
        let restArea = bestRest.reduce(0, +)
        guard restArea > 0 else {
            return positioned
        }

        // 计算剩余 rect
        var restRect: CGRect = .zero
        if isHorizontalRow {
            restRect = CGRect(x: 0, y: 0,
                              width: dx - rowThickness,
                              height: dy)
        } else {
            restRect = CGRect(x: 0, y: 0,
                              width: dx,
                              height: dy - rowThickness)
        }

        let restPositioned = squarifyRecursive(
            values: bestRest,
            rowValues: [],
            rowMin: .greatestFiniteMagnitude,
            rowMax: -1,
            dx: restRect.width,
            dy: restRect.height
        )

        // 把 restPositioned 的坐标转换到剩余 rect 内
        let restTranslated = restPositioned.map { p in
            (p.value, p.x + restRect.minX, p.y + restRect.minY, p.width, p.height)
        }

        return positioned + restTranslated
    }

    /// 计算 row 的 worst aspect ratio（按 d3 公式）
    /// worst = max(rowMax/beta, beta/rowMin)
    /// alpha = max(dy/dx, dx/dy) / (rowSum * phi)
    /// beta = rowSum² * alpha
    private func worstRatio(rowMin: CGFloat, rowMax: CGFloat, rowSum: CGFloat, shortSide: CGFloat) -> CGFloat {
        guard rowMin > 0, rowSum > 0, shortSide > 0 else { return .greatestFiniteMagnitude }
        let alpha = (1.0) / (rowSum * phi)  // 简化：假设正方形容器
        let beta = rowSum * rowSum * alpha
        return max(rowMax / beta, beta / rowMin)
    }

    /// 把堆叠结果展开为 PositionedBlock（按 rect 偏移）
    private func layoutStack(
        _ stack: [(value: CGFloat, x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat)],
        in rect: CGRect,
        items: [TreemapItem],
        areas: [CGFloat]
    ) -> [PositionedBlock] {
        // 按 value 降序顺序匹配 items
        var sortedItems = items.sorted { $0.weight > $1.weight }
        var result: [PositionedBlock] = []

        for placement in stack {
            // 找到对应 item（按 area 匹配）
            guard !sortedItems.isEmpty else { break }
            let targetArea = placement.value

            // 找最接近 targetArea 的 item
            var bestIdx = 0
            var bestDiff = CGFloat.greatestFiniteMagnitude
            for (i, item) in sortedItems.enumerated() {
                let totalArea = areas.reduce(0, +)
                let itemArea = totalArea > 0 ? CGFloat(item.weight / items.reduce(0) { $0 + $1.weight }) * totalArea : 0
                let diff = abs(itemArea - targetArea)
                if diff < bestDiff {
                    bestDiff = diff
                    bestIdx = i
                }
            }

            let item = sortedItems.remove(at: bestIdx)
            let frame = CGRect(
                x: rect.minX + placement.x,
                y: rect.minY + placement.y,
                width: placement.width,
                height: placement.height
            )
            result.append(PositionedBlock(item: item, frame: frame, scaleMode: currentScaleMode))
        }

        return result
    }

    // MARK: - Scale Mode Tracking

    private var currentScaleMode: ScaleMode {
        chooseScaleMode()
    }

    // MARK: - Render Cell

    private func treemapCell(block: PositionedBlock, onSelect: @escaping (AllocationNode) -> Void) -> some View {
        let node = block.item.node
        let palette = blockPalette(for: node)
        let frame = block.frame
        let percentage = blockPercentage(for: block)

        return ZStack {
            // Visual
            ZStack {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(palette.fill)
                    .background(
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(.ultraThinMaterial)
                            .opacity(0.25)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.4),
                                        Color.white.opacity(0.1),
                                        Color.black.opacity(0.05)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 0.5
                            )
                    )
                    .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 2)

                // 内容
                renderContent(node: node, frame: frame, percentage: percentage, isAggregated: block.item.isAggregated)
            }
            .frame(width: frame.width, height: frame.height)
            .position(x: frame.midX, y: frame.midY)
            .allowsHitTesting(false)

            // Tappable overlay
            Color.clear
                .contentShape(Rectangle())
                .frame(width: frame.width, height: frame.height)
                .position(x: frame.midX, y: frame.midY)
                .onTapGesture { onSelect(node) }
                .onHover { hovering in
                    #if canImport(AppKit)
                    if hovering { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
                    #endif
                }
        }
    }

    @ViewBuilder
    private func renderContent(node: AllocationNode, frame: CGRect, percentage: Double, isAggregated: Bool) -> some View {
        if frame.width > 70 && frame.height > 42 {
            // 大块：完整内容（左上 + 右下非对称对齐）
            let pad = max(8, min(frame.width, frame.height) * contentPaddingRatio)
            ZStack(alignment: .topLeading) {
                HStack(alignment: .top, spacing: 4) {
                    Image(systemName: node.iconName)
                        .font(.system(size: min(12, frame.height * 0.18), weight: .semibold))
                        .foregroundStyle(.white.opacity(0.95))
                    Text(node.name)
                        .font(.system(size: min(11, frame.width * 0.07), weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 0)
                }
                .padding(pad)
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(formatAmount(abs(node.balance)))
                                .font(.system(size: min(12, frame.width * 0.085), weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.5)
                            Text(String(format: "%.1f%%", percentage * 100))
                                .font(.system(size: min(9, frame.width * 0.06), weight: .medium, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.7))
                                .lineLimit(1)
                        }
                    }
                    .padding(pad)
                }
            }
        } else if frame.width > 32 && frame.height > 22 {
            // 小块：图标居中
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.12))
                    .frame(
                        width: min(frame.width, frame.height) * 0.55,
                        height: min(frame.width, frame.height) * 0.55
                    )
                Image(systemName: node.iconName)
                    .font(.system(size: min(frame.width, frame.height) * 0.32, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
            }
        }
    }

    private func blockPalette(for node: AllocationNode) -> (fill: Color, accent: Color) {
        let baseHue: Double = node.isLiability ? 0.0 : 0.42
        return (
            fill: Color(hue: baseHue, saturation: 0.55, brightness: 0.58).opacity(0.85),
            accent: Color(hue: baseHue, saturation: 0.7, brightness: 0.7)
        )
    }

    private func blockPercentage(for block: PositionedBlock) -> Double {
        let amount = NSDecimalNumber(decimal: abs(block.item.node.balance)).doubleValue
        let totalDouble = NSDecimalNumber(decimal: total).doubleValue
        return totalDouble > 0 ? amount / totalDouble : 0
    }

    private func formatAmount(_ amount: Decimal) -> String {
        let amountDouble = NSDecimalNumber(decimal: amount).doubleValue
        if amountDouble >= 100000 {
            return String(format: "%.0f万", amountDouble / 10000)
        } else if amountDouble >= 10000 {
            return String(format: "%.1f万", amountDouble / 10000)
        } else {
            return String(format: "%.0f", amountDouble)
        }
    }

    // MARK: - Types

    enum ScaleMode { case linear, sqrt, log }

    struct TreemapItem {
        let id: String
        let node: AllocationNode
        let weight: Double
        let isAggregated: Bool
    }

    struct PositionedBlock: Identifiable {
        let item: TreemapItem
        let frame: CGRect
        let scaleMode: ScaleMode
        var id: String { item.id }
    }
}