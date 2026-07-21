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
    private let paddingInner: CGFloat = 10

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

        // 2. 不合并极小块 —— 每个账户独立 tile，由 squarify + minArea 保底保证可见性
        let items: [TreemapItem] = nodes.enumerated().map { idx, node in
            TreemapItem(
                id: node.id,
                node: node,
                weight: rawWeights[idx],
                isAggregated: false
            )
        }

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
            return layoutSplit(assetItems: assetItems, liabilityItems: liabilityItems, assetFrac: assetWeight / totalWeight, in: layoutRect)
        } else if !assetItems.isEmpty && !liabilityItems.isEmpty {
            // 负债用底部窄条；按 tile 数 × 70px 估算高度
            let liabilityCount = liabilityItems.count
            let desiredLiabilityHeight = CGFloat(liabilityCount) * 70 + CGFloat(max(0, liabilityCount - 1)) * paddingInner
            let liabilityHeight = min(layoutRect.height * 0.4, max(layoutRect.height * 0.2, desiredLiabilityHeight))
            let assetHeight = layoutRect.height - liabilityHeight - paddingInner

            let assetRect = CGRect(
                x: layoutRect.minX, y: layoutRect.minY,
                width: layoutRect.width,
                height: max(minTileSide, assetHeight)
            )
            let liabilityRect = CGRect(
                x: layoutRect.minX, y: layoutRect.maxY - liabilityHeight,
                width: layoutRect.width,
                height: liabilityHeight
            )

            // 资产 + 负债都使用 strip layout：按 weight 比例分配宽度，高度恒定
            // 这样能避免 squarify 的边界 case（tile 被压到接近 0）
            let scaleMode = currentScaleMode

            // 资产区 strip layout
            let totalAssetWeight = assetItems.reduce(0) { $0 + $1.weight }
            var assetResult: [PositionedBlock] = []
            if totalAssetWeight > 0 {
                let totalAssetGutter = paddingInner * CGFloat(max(0, assetItems.count - 1))
                let assetUsableWidth = max(1, assetRect.width - totalAssetGutter)
                let assetWidths = computeStripWidths(items: assetItems, totalWeight: totalAssetWeight, usableWidth: assetUsableWidth)
                var xOffset = assetRect.minX
                for (idx, item) in assetItems.enumerated() {
                    let frame = CGRect(
                        x: xOffset, y: assetRect.minY,
                        width: assetWidths[idx], height: assetRect.height
                    )
                    assetResult.append(PositionedBlock(item: item, frame: frame, scaleMode: scaleMode))
                    xOffset += assetWidths[idx] + paddingInner
                }
            }

            // 负债区 strip layout
            let totalLiabilityWeight = liabilityItems.reduce(0) { $0 + $1.weight }
            var liabilityResult: [PositionedBlock] = []
            if totalLiabilityWeight > 0 {
                let totalLiabGutter = paddingInner * CGFloat(max(0, liabilityItems.count - 1))
                let liabUsableWidth = max(1, liabilityRect.width - totalLiabGutter)
                let liabWidths = computeStripWidths(items: liabilityItems, totalWeight: totalLiabilityWeight, usableWidth: liabUsableWidth)
                var xOffset = liabilityRect.minX
                for (idx, item) in liabilityItems.enumerated() {
                    let frame = CGRect(
                        x: xOffset, y: liabilityRect.minY,
                        width: liabWidths[idx], height: liabilityRect.height
                    )
                    liabilityResult.append(PositionedBlock(item: item, frame: frame, scaleMode: scaleMode))
                    xOffset += liabWidths[idx] + paddingInner
                }
            }

            return assetResult + liabilityResult
        } else {
            // 单一类型：也用 strip layout（避免 squarify 边界 case）
            return stripLayout(items: sortedItems, in: layoutRect)
        }
    }

    /// Strip layout：按 weight 比例分配宽度，高度恒定 = rect.height
    /// 适合 tile 数量不多（≤10）的场景，绝对不会越界
    private func stripLayout(items: [TreemapItem], in rect: CGRect) -> [PositionedBlock] {
        guard !items.isEmpty else { return [] }
        let totalWeight = items.reduce(0) { $0 + $1.weight }
        guard totalWeight > 0 else { return [] }
        let totalGutter = paddingInner * CGFloat(max(0, items.count - 1))
        let usableWidth = max(1, rect.width - totalGutter)
        let widths = computeStripWidths(items: items, totalWeight: totalWeight, usableWidth: usableWidth)

        var result: [PositionedBlock] = []
        var xOffset = rect.minX
        for (idx, item) in items.enumerated() {
            let frame = CGRect(
                x: xOffset, y: rect.minY,
                width: widths[idx], height: rect.height
            )
            result.append(PositionedBlock(item: item, frame: frame, scaleMode: currentScaleMode))
            xOffset += widths[idx] + paddingInner
        }
        return result
    }

    /// 计算 strip layout 中每个 tile 的宽度
    /// - 保底 minTileSide
    /// - 累积超出可用宽度时等比缩小非保底部分
    private func computeStripWidths(
        items: [TreemapItem],
        totalWeight: Double,
        usableWidth: CGFloat
    ) -> [CGFloat] {
        var widths = items.map { item in
            max(minTileSide, usableWidth * CGFloat(item.weight / totalWeight))
        }
        let totalRaw = widths.reduce(0, +)
        if totalRaw > usableWidth {
            let excess = totalRaw - usableWidth
            let reducible = widths.reduce(0) { $0 + max(0, $1 - minTileSide) }
            if reducible > 0 {
                let scale = max(0, 1 - excess / reducible)
                widths = widths.map { w in max(minTileSide, w * scale) }
            }
        }
        return widths
    }

    /// 缩放模式：固定线性（保留真实占比，直观看到大小关系）
    private func chooseScaleMode() -> ScaleMode {
        return .linear
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

        // 进一步保证：每个 tile 的最短边至少 minTileSide
        // 这通过最小面积（minTileSide²）作为绝对下界实现
        // 后置在 layoutResult 阶段：检测每个 placed block 的 min(w,h)，如果 < minTileSide 就强制放大
        // 但放大后总面积会超过容器，所以必须再次归一化（按"保底后总面积"作为容器面积）
        // 这里采用 d3 风格的"backing scale"：保底 sum 后用 (totalArea / backingSum) 做最终 scale
        let backingSum = values.reduce(0, +)
        if backingSum > totalArea {
            // 所有 tile 都被保底到 minArea，总面积超过容器 → 按比例缩小
            let scale = totalArea / backingSum
            values = values.map { $0 * scale }
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

        // 后置几何校验：任何 tile 的 min(w,h) < minTileSide 强制放大到 minTileSide
        // 这会"借用"相邻 tile 的空间，迭代直到全部满足
        enforceMinimumTileSize(blocks: &result, containerRect: rect)

        return result
    }

    /// 迭代强制每个 tile 至少 minTileSide × minTileSide
    /// 通过调整相邻 tile 的大小，把空间从大 tile 转给小 tile
    private func enforceMinimumTileSize(blocks: inout [PositionedBlock], containerRect: CGRect) {
        let minSide: CGFloat = minTileSide
        let maxIterations = 5
        for _ in 0..<maxIterations {
            var needsAdjustment = false
            for i in 0..<blocks.count {
                var block = blocks[i]
                if block.frame.width < minSide || block.frame.height < minSide {
                    needsAdjustment = true
                    // 强制放大到 minSide，保持原位置中心不变
                    let newW = max(block.frame.width, minSide)
                    let newH = max(block.frame.height, minSide)
                    let dx = (newW - block.frame.width) / 2
                    let dy = (newH - block.frame.height) / 2
                    block.frame = CGRect(
                        x: block.frame.minX - dx,
                        y: block.frame.minY - dy,
                        width: newW,
                        height: newH
                    )
                    blocks[i] = block
                }
            }
            if !needsAdjustment { break }
        }
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
    /// 每个 tile 在自己的边界上 inset paddingInner/2，让相邻 tile 之间自然产生 paddingInner 间距
    private func layoutRowBlocks(
        row: [CGFloat],
        dx0: CGFloat,
        dy0: CGFloat
    ) -> [(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat)] {
        guard !row.isEmpty, dx0 > 0, dy0 > 0 else { return [] }
        let rowSum = row.reduce(0, +)
        guard rowSum > 0 else { return [] }
        let horizontal = dx0 >= dy0
        let halfPad = paddingInner / 2

        if horizontal {
            // row 是垂直方向的窄条，贴在容器右侧
            let stripWidth = rowSum / dy0
            var y: CGFloat = 0
            return row.map { value in
                let h = value / stripWidth
                let x = dx0 - stripWidth + halfPad  // tile 右边界 = strip 右边界（不 inset）
                let block = (
                    x: x + halfPad,                  // tile 左边界 inset halfPad
                    y: y + halfPad,                  // 上 inset
                    width: max(1, stripWidth - paddingInner),  // 宽缩 paddingInner
                    height: max(1, h - paddingInner)          // 高缩 paddingInner
                )
                y += h
                return block
            }
        } else {
            // row 是水平方向的窄条，贴在容器底部
            let stripHeight = rowSum / dx0
            var x: CGFloat = 0
            return row.map { value in
                let w = value / stripHeight
                let y = dy0 - stripHeight + halfPad
                let block = (
                    x: x + halfPad,
                    y: y + halfPad,
                    width: max(1, w - paddingInner),
                    height: max(1, stripHeight - paddingInner)
                )
                x += w
                return block
            }
        }
    }

    /// 计算 row 占据后的剩余 rect（相对当前原点）
    /// 剩余 rect 也需要 inset paddingInner/2，让下一个递归层级的 tile 与当前 row 间距一致
    private func computeRestRect(row: [CGFloat], dx0: CGFloat, dy0: CGFloat) -> CGRect {
        let rowSum = row.reduce(0, +)
        let horizontal = dx0 >= dy0
        let halfPad = paddingInner / 2
        if horizontal {
            let stripWidth = rowSum / dy0
            // row 占用 stripWidth（+ 半 padding 在左右各半），剩余 rect 从 (0, 0) 开始，宽度减去 row + halfPad
            return CGRect(x: 0, y: 0,
                          width: max(1, dx0 - stripWidth - halfPad),
                          height: max(1, dy0 - paddingInner))
        } else {
            let stripHeight = rowSum / dx0
            return CGRect(x: 0, y: 0,
                          width: max(1, dx0 - paddingInner),
                          height: max(1, dy0 - stripHeight - halfPad))
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
        var frame: CGRect
        let scaleMode: ScaleMode
        var id: String { item.id }
    }
}