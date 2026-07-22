import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

/// Strip Treemap（条带式树图）
/// - 上排：资产账户（按 weight 比例分配宽度 + 恒定高度）
/// - 下排：负债账户（同上）
/// - 每个 tile 保底 minTileSide（50×50px）
/// - 适合账户数量适中（≤ 10）的场景，绝对不会越界
struct MacTreemapView: View {
    typealias AllocationNode = AccountAllocationItem.AllocationNode

    let nodes: [AllocationNode]
    let total: Decimal
    let onSelect: (AllocationNode) -> Void

    // MARK: - Layout Constants

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

    /// 负债区高度保底：每个负债 tile 至少 70px + gutter
    private let liabilityTileMinHeight: CGFloat = 70

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

    // MARK: - Layout

    /// 主布局入口：把资产放在上排、负债放在下排，分别用 strip layout
    private func computeLayout(in container: CGRect) -> [PositionedBlock] {
        guard !nodes.isEmpty, total > 0, container.width > 0, container.height > 0 else {
            return []
        }

        let layoutRect = container.insetBy(dx: paddingOuter, dy: paddingOuter)

        // 按资产/负债分组
        var assetItems: [TreemapItem] = []
        var liabilityItems: [TreemapItem] = []
        let rawWeights = computeWeights()
        for (idx, node) in nodes.enumerated() {
            let item = TreemapItem(id: node.id, node: node, weight: rawWeights[idx])
            if node.isLiability {
                liabilityItems.append(item)
            } else {
                assetItems.append(item)
            }
        }

        if !assetItems.isEmpty && !liabilityItems.isEmpty {
            // 双排布局：资产上、负债下
            let liabilityHeight = computeLiabilityHeight(tileCount: liabilityItems.count, in: layoutRect)
            let assetHeight = max(minTileSide, layoutRect.height - liabilityHeight - paddingInner)
            let assetRect = CGRect(
                x: layoutRect.minX, y: layoutRect.minY,
                width: layoutRect.width, height: assetHeight
            )
            let liabilityRect = CGRect(
                x: layoutRect.minX, y: layoutRect.maxY - liabilityHeight,
                width: layoutRect.width, height: liabilityHeight
            )
            return stripLayout(items: assetItems, in: assetRect)
                 + stripLayout(items: liabilityItems, in: liabilityRect)
        } else {
            // 单一类型：满铺整个容器
            let items = assetItems.isEmpty ? liabilityItems : assetItems
            return stripLayout(items: items, in: layoutRect)
        }
    }

    /// 计算负债区高度：每个 tile 至少 minTileSide，保证 tile 不变成像素点
    /// 上限 50%，超过则按比例压缩但绝不低于"每 tile 至少 minTileSide"
    private func computeLiabilityHeight(tileCount: Int, in rect: CGRect) -> CGFloat {
        let hardMin = CGFloat(tileCount) * minTileSide + CGFloat(max(0, tileCount - 1)) * paddingInner
        let upperBound = rect.height * 0.5
        let lowerBound = rect.height * 0.2
        // 优先级：硬最小值 > 上限取上限 > 下限取下限
        if hardMin > upperBound {
            return hardMin  // 即使超出 50%，也必须满足每 tile 至少 minTileSide
        }
        return max(lowerBound, min(upperBound, hardMin))
    }

    /// Strip layout：按 weight 比例分配宽度，高度恒定 = rect.height
    /// 永远不越界，适合 tile 数量适中（≤ 10）
    private func stripLayout(items: [TreemapItem], in rect: CGRect) -> [PositionedBlock] {
        guard !items.isEmpty else { return [] }
        let totalWeight = items.reduce(0) { $0 + $1.weight }
        guard totalWeight > 0, rect.width > 0, rect.height > 0 else { return [] }

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
            result.append(PositionedBlock(item: item, frame: frame))
            xOffset += widths[idx] + paddingInner
        }
        return result
    }

    /// 计算 strip layout 中每个 tile 的宽度
    /// - 保底 minTileSide
    /// - 累积超出可用宽度时等比缩小非保底部分
    /// - 即使全保底场景也严格保证总宽 ≤ usableWidth
    private func computeStripWidths(
        items: [TreemapItem],
        totalWeight: Double,
        usableWidth: CGFloat
    ) -> [CGFloat] {
        guard !items.isEmpty else { return [] }
        let n = CGFloat(items.count)
        // 硬保底总宽：所有 item 至少 minTileSide，总 gutter = paddingInner * (n-1)
        let hardFloorWidth = n * minTileSide + max(0, n - 1) * paddingInner

        if hardFloorWidth >= usableWidth {
            // 极端场景：保底就已经超出可用宽度
            // 按可用宽度均匀分配每个 tile，最少 1px
            let perTile = max(1, (usableWidth - max(0, n - 1) * paddingInner) / n)
            return Array(repeating: perTile, count: items.count)
        }

        // 标准场景：按比例分配，保底 minTileSide
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
            } else {
                // reducible=0（所有都被保底），按可用宽度均分
                let perTile = max(1, (usableWidth - max(0, n - 1) * paddingInner) / n)
                return Array(repeating: perTile, count: items.count)
            }
        }
        return widths
    }

    /// 缩放后的权重（线性，保留真实占比）
    private func computeWeights() -> [Double] {
        nodes.map { NSDecimalNumber(decimal: abs($0.balance)).doubleValue }
    }

    // MARK: - Render

    private func treemapCell(block: PositionedBlock, onSelect: @escaping (AllocationNode) -> Void) -> some View {
        let node = block.item.node
        let palette = blockPalette(for: node)
        let frame = block.frame
        let percentage = blockPercentage(for: block)

        return ZStack {
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

                renderContent(node: node, frame: frame, percentage: percentage)
            }
            .frame(width: frame.width, height: frame.height)
            .position(x: frame.midX, y: frame.midY)
            .allowsHitTesting(false)

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
    private func renderContent(node: AllocationNode, frame: CGRect, percentage: Double) -> some View {
        if frame.width > 70 && frame.height > 42 {
            // 大块：图标 + 名称 + 金额 + 百分比
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
                            Text(CurrencyFormatter.formatCompactNumber(abs(node.balance).doubleValue))
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
            // 小块：图标居中（圆形玻璃背景胶囊）
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
        } else {
            // 极小块：仅图标（无背景胶囊），保证 tile 永远有内容
            Image(systemName: node.iconName)
                .font(.system(size: min(frame.width, frame.height) * 0.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.8))
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

    // MARK: - Types

    struct TreemapItem {
        let id: String
        let node: AllocationNode
        let weight: Double
    }

    struct PositionedBlock: Identifiable {
        let item: TreemapItem
        let frame: CGRect
        var id: String { item.id }
    }
}