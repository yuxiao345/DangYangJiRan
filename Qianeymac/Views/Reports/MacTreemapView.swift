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
        if items.count == 1 {
            return [PositionedBlock(item: items[0], frame: rect, scaleMode: currentScaleMode)]
        }

        let totalWeight = items.reduce(0) { $0 + $1.weight }
        guard totalWeight > 0, rect.width > 0, rect.height > 0 else { return [] }

        // weight → area（线性）
        let totalArea = rect.width * rect.height
        var values = items.map { CGFloat($0.weight / totalWeight) * totalArea }

        // 后置最小可见性校验
        let minArea = minTileSide * minTileSide
        var needsRescale = false
        for i in 0..<values.count where values[i] < minArea {
            values[i] = minArea
            needsRescale = true
        }
        if needsRescale {
            let sum = values.reduce(0, +)
            if sum > 0 {
                values = values.map { $0 * totalArea / sum }
            }
        }

        // 调用 d3 算法（忠实翻译 squarify.js）
        let positioned = d3Squarify(
            values: values,
            dx: rect.width,
            dy: rect.height
        )

        // 匹配 items（按 weight 降序）
        var sortedItems = items.sorted { $0.weight > $1.weight }
        var result: [PositionedBlock] = []
        for p in positioned {
            guard !sortedItems.isEmpty else { break }
            let item = sortedItems.removeFirst()
            let frame = CGRect(
                x: rect.minX + p.x,
                y: rect.minY + p.y,
                width: p.width,
                height: p.height
            )
            result.append(PositionedBlock(item: item, frame: frame, scaleMode: currentScaleMode))
        }
        return result
    }

    /// 忠实翻译 d3-hierarchy/src/treemap/squarify.js
    /// 输出：相对 (0,0) 的坐标，绝对坐标由 squarify 添加 rect.minX/minY
    private func d3Squarify(
        values: [CGFloat],
        dx: CGFloat,
        dy: CGFloat
    ) -> [(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat)] {
        // 边界 case：只有一个值
        if values.count == 1 {
            return [(x: 0, y: 0, width: dx, height: dy)]
        }

        // 递归算法（d3 风格）
        return squarifyImpl(row: [], values: values, dx0: dx, dy0: dy)
    }

    /// Bruls 2000 算法核心
    private func squarifyImpl(
        row: [CGFloat],
        values: [CGFloat],
        dx0: CGFloat,
        dy0: CGFloat
    ) -> [(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat)] {
        if values.count == 0 {
            // 没有剩余 → 布局当前 row
            return layoutRowBlocks(row: row, dx0: dx0, dy0: dy0)
        }

        let value = values[0]
        let newRow = row + [value]

        // 计算当前 row 的 worst AR
        let currentWorst = row.isEmpty ? .infinity : worst(row: row, dx0: dx0, dy0: dy0)
        let newWorst = worst(row: newRow, dx0: dx0, dy0: dy0)

        // 如果加入新项后 worst 不变差，继续扩展 row
        // 否则布局当前 row，递归处理剩余 values
        if row.isEmpty || newWorst <= currentWorst {
            return squarifyImpl(row: newRow, values: Array(values.dropFirst()), dx0: dx0, dy0: dy0)
        } else {
            // 关闭当前 row，布局它
            let rowBlocks = layoutRowBlocks(row: row, dx0: dx0, dy0: dy0)
            // 剩余空间递归（d3 用 strip 简化处理）
            let restRect = computeRestRect(row: row, dx0: dx0, dy0: dy0)
            let restBlocks = squarifyImpl(row: [], values: values, dx0: restRect.width, dy0: restRect.height)
            // 把 restBlocks 偏移到 restRect 位置
            let offsetX = restRect.minX
            let offsetY = restRect.minY
            return rowBlocks + restBlocks.map { (x: $0.x + offsetX, y: $0.y + offsetY, width: $0.width, height: $0.height) }
        }
    }

    /// d3 的 worst(row, dx0, dy0) 计算
    private func worst(row: [CGFloat], dx0: CGFloat, dy0: CGFloat) -> CGFloat {
        guard !row.isEmpty, dx0 > 0, dy0 > 0 else { return .infinity }
        let rowMax = row.max()!
        let rowMin = row.min()!
        let rowSum = row.reduce(0, +)
        guard rowMin > 0, rowSum > 0 else { return .infinity }
        let alpha = max(dx0 / dy0, dy0 / dx0) / (rowSum * phi)
        let beta = rowSum * rowSum * alpha
        return max(rowMax / beta, beta / rowMin)
    }

    /// d3 的 row(...) 几何布局：把 row 中的元素按比例铺在容器一条窄带上
    /// 返回 [(x, y, width, height), ...]
    private func layoutRowBlocks(
        row: [CGFloat],
        dx0: CGFloat,
        dy0: CGFloat
    ) -> [(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat)] {
        guard !row.isEmpty, dx0 > 0, dy0 > 0 else { return [] }
        let rowSum = row.reduce(0, +)
        guard rowSum > 0 else { return [] }
        let horizontal = dx0 >= dy0

        if horizontal {
            // row 是垂直方向的窄条，贴在容器右侧
            let stripWidth = rowSum / dy0  // row 厚度 = 总面积 / 长边
            var y: CGFloat = 0
            return row.map { value in
                let h = value / stripWidth
                let x = dx0 - stripWidth
                let block = (x: x, y: y, width: stripWidth, height: h)
                y += h
                return block
            }
        } else {
            // row 是水平方向的窄条，贴在容器底部
            let stripHeight = rowSum / dx0
            var x: CGFloat = 0
            return row.map { value in
                let w = value / stripHeight
                let y = dy0 - stripHeight
                let block = (x: x, y: y, width: w, height: stripHeight)
                x += w
                return block
            }
        }
    }

    /// 计算 row 占据后的剩余 rect（相对当前原点）
    private func computeRestRect(row: [CGFloat], dx0: CGFloat, dy0: CGFloat) -> CGRect {
        let rowSum = row.reduce(0, +)
        let horizontal = dx0 >= dy0
        if horizontal {
            let stripWidth = rowSum / dy0
            return CGRect(x: 0, y: 0, width: dx0 - stripWidth, height: dy0)
        } else {
            let stripHeight = rowSum / dx0
            return CGRect(x: 0, y: 0, width: dx0, height: dy0 - stripHeight)
        }
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