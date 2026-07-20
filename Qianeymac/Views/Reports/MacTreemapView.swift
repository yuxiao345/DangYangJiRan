import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

/// Squarified Treemap（正方化树图）
/// - 使用 log/sqrt 缩放：大幅压缩大账户视觉权重，提升小账户可见度
/// - 最小物理阈值：所有块至少达到最小面积（避免像素点）
/// - Squarified 算法：保证每个块长宽比接近 1:1
struct MacTreemapView: View {
    typealias AllocationNode = AccountAllocationItem.AllocationNode

    let nodes: [AllocationNode]
    let total: Decimal
    let onSelect: (AllocationNode) -> Void

    /// 缩放模式：log（指数压缩）/ sqrt（平方根压缩）
    enum ScaleMode { case log, sqrt }
    private let scaleMode: ScaleMode = .sqrt

    /// 最小块尺寸（像素）
    private let minBlockSide: CGFloat = 50

    /// 区块间 gutter（像素），让玻璃切片之间有呼吸空间
    private let gutter: CGFloat = 14

    /// 区块圆角（增大负空间）
    private let blockCornerRadius: CGFloat = 16

    /// 内容区内边距（占块尺寸的比例，确保文字安全距离）
    private let contentPaddingRatio: CGFloat = 0.15

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            // 主容器外部留白：让边缘区块也保持呼吸感
            let outerInset: CGFloat = 4
            let containerRect = CGRect(
                x: outerInset,
                y: outerInset,
                width: max(0, size.width - outerInset * 2),
                height: max(0, size.height - outerInset * 2)
            )
            let rects = computeRects(in: containerRect)
            ZStack(alignment: .topLeading) {
                ForEach(rects) { block in
                    treemapCell(block: block, onSelect: onSelect)
                }
            }
        }
    }

    private func computeRects(in container: CGRect) -> [TreemapBlock] {
        guard !nodes.isEmpty, total > 0 else { return [] }

        // 1. 计算每个节点的非线性权重值
        let weights = nodes.map { node -> Double in
            let amount = NSDecimalNumber(decimal: abs(node.balance)).doubleValue
            switch scaleMode {
            case .log:
                return log10(max(1, amount)) + 1
            case .sqrt:
                return sqrt(amount)
            }
        }
        let totalWeight = weights.reduce(0, +)
        guard totalWeight > 0 else { return [] }

        let containerArea = container.width * container.height

        // 2. 按资产/负债分组，分别计算权重
        let assetIndices = nodes.indices.filter { !nodes[$0].isLiability }
        let liabilityIndices = nodes.indices.filter { nodes[$0].isLiability }

        let assetWeight = assetIndices.reduce(0) { $0 + weights[$1] }
        let liabilityWeight = liabilityIndices.reduce(0) { $0 + weights[$1] }
        let twoSides = !assetIndices.isEmpty && !liabilityIndices.isEmpty

        // 3. 按分组占比分配主区域
        let assetArea: CGFloat
        let liabilityArea: CGFloat
        if twoSides {
            let assetFrac = CGFloat(assetWeight / (assetWeight + liabilityWeight))
            assetArea = containerArea * assetFrac
            liabilityArea = containerArea * (1 - assetFrac)
        } else if assetIndices.isEmpty {
            assetArea = 0
            liabilityArea = containerArea
        } else {
            assetArea = containerArea
            liabilityArea = 0
        }

        // 4. 构建 blocks 并应用最小阈值
        func buildBlocks(for indices: [Int], in area: CGFloat) -> [TreemapBlock] {
            guard !indices.isEmpty, area > 0 else { return [] }
            let sortedIndices = indices.sorted { weights[$0] > weights[$1] }
            let groupWeight = indices.reduce(0) { $0 + weights[$1] }
            let minArea = minBlockSide * minBlockSide
            var blocks: [TreemapBlock] = []
            var assigned: CGFloat = 0
            for (pos, idx) in sortedIndices.enumerated() {
                let idealArea = CGFloat(weights[idx] / groupWeight) * area
                let remainingCount = sortedIndices.count - pos
                let remainingArea = area - assigned
                let idealRemaining = CGFloat(sortedIndices[pos...].reduce(0) { $0 + weights[$1] } / groupWeight) * area
                let targetArea: CGFloat
                if idealArea < minArea && idealRemaining > minArea * CGFloat(remainingCount) {
                    targetArea = minArea
                } else if idealRemaining < minArea * CGFloat(remainingCount) {
                    targetArea = remainingArea / CGFloat(remainingCount)
                } else {
                    targetArea = idealArea
                }
                blocks.append(TreemapBlock(node: nodes[idx], area: targetArea, index: idx))
                assigned += targetArea
            }
            // 归一化
            let totalAssigned = blocks.reduce(0) { $0 + $1.area }
            if totalAssigned > 0 {
                let scale = area / totalAssigned
                blocks = blocks.map { TreemapBlock(node: $0.node, area: $0.area * scale, index: $0.index) }
            }
            return blocks
        }

        let assetBlocks = buildBlocks(for: assetIndices, in: assetArea)
        let liabilityBlocks = buildBlocks(for: liabilityIndices, in: liabilityArea)

        // 5. 按方向分配矩形：横向 split 时左资产右负债，纵向 split 时上资产下负债
        var result: [TreemapBlock] = []
        if twoSides {
            let assetFrac = CGFloat(assetWeight / (assetWeight + liabilityWeight))
            let liabilityFrac = 1 - assetFrac

            // 横向容器（宽 > 高）→ 横向 split（左资产/右负债）
            if container.width >= container.height {
                let assetRect = CGRect(
                    x: container.minX, y: container.minY,
                    width: container.width * assetFrac - gutter / 2,
                    height: container.height
                )
                let liabilityRect = CGRect(
                    x: container.minX + container.width * assetFrac + gutter / 2,
                    y: container.minY,
                    width: max(minBlockSide, container.width * liabilityFrac - gutter / 2),
                    height: container.height
                )
                result += squarify(blocks: assetBlocks, in: assetRect)
                result += squarify(blocks: liabilityBlocks, in: liabilityRect)
            } else {
                // 纵向容器 → 纵向 split（上资产/下负债）
                let assetRect = CGRect(
                    x: container.minX, y: container.minY,
                    width: container.width,
                    height: container.height * assetFrac - gutter / 2
                )
                let liabilityRect = CGRect(
                    x: container.minX,
                    y: container.minY + container.height * assetFrac + gutter / 2,
                    width: container.width,
                    height: max(minBlockSide, container.height * liabilityFrac - gutter / 2)
                )
                result += squarify(blocks: assetBlocks, in: assetRect)
                result += squarify(blocks: liabilityBlocks, in: liabilityRect)
            }
        } else if assetIndices.isEmpty {
            result += squarify(blocks: liabilityBlocks, in: container)
        } else {
            result += squarify(blocks: assetBlocks, in: container)
        }

        return result
    }

    /// Squarified treemap：递归分割，最优化每个矩形长宽比
    private func squarify(blocks: [TreemapBlock], in rect: CGRect) -> [TreemapBlock] {
        guard !blocks.isEmpty else { return [] }
        return squarifyRecursive(blocks, in: rect)
    }

    private func squarifyRecursive(_ blocks: [TreemapBlock], in rect: CGRect) -> [TreemapBlock] {
        guard !blocks.isEmpty else { return [] }
        if blocks.count == 1 {
            return [blocks[0].withFrame(rect)]
        }

        let horizontal = rect.width >= rect.height
        // 减去 gutter 后用于分配的"有效短边"
        let rawSide = horizontal ? rect.height : rect.width
        let effectiveSide = max(1, rawSide - gutter)
        let side = effectiveSide

        // 找最佳分组：贪心扫描，最小化最差长宽比
        var bestSplit = 1
        var bestRatio = CGFloat.greatestFiniteMagnitude
        var rowArea: CGFloat = 0
        var i = 0
        while i < blocks.count {
            let newRowArea = rowArea + blocks[i].area
            let rect1 = CGRect(x: 0, y: 0,
                               width: horizontal ? side : newRowArea / side,
                               height: horizontal ? newRowArea / side : side)
            if rect1.width <= 0 || rect1.height <= 0 { break }
            let ratio = max(aspectRatio(rect1.size), worstInRow(Array(blocks[0...i]), side: side, horizontal: horizontal))
            if ratio > bestRatio { break }
            bestRatio = ratio
            bestSplit = i + 1
            rowArea = newRowArea
            i += 1
        }

        let row = Array(blocks[0..<bestSplit])
        let rest = Array(blocks[bestSplit...])

        let rowTotalArea = row.reduce(0) { $0 + $1.area }
        let rowThickness = side > 0 ? rowTotalArea / side : 0
        let rowRect: CGRect
        let remainingRect: CGRect

        if horizontal {
            // 左侧 row 列 + gutter + 右侧 rest
            rowRect = CGRect(x: rect.minX, y: rect.minY, width: rowThickness, height: rect.height)
            remainingRect = CGRect(
                x: rect.minX + rowThickness + gutter,
                y: rect.minY,
                width: max(0, rect.width - rowThickness - gutter),
                height: rect.height
            )
        } else {
            // 上方 row + gutter + 下方 rest
            rowRect = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rowThickness)
            remainingRect = CGRect(
                x: rect.minX,
                y: rect.minY + rowThickness + gutter,
                width: rect.width,
                height: max(0, rect.height - rowThickness - gutter)
            )
        }

        let laidOut = layoutRow(row, in: rowRect, side: rowRect.height > 0 ? rowRect.height : rowRect.width, horizontal: horizontal)
        let tail = squarifyRecursive(rest, in: remainingRect)
        return laidOut + tail
    }

    private func layoutRow(_ row: [TreemapBlock], in rect: CGRect, side: CGFloat, horizontal: Bool) -> [TreemapBlock] {
        let rowTotal = row.reduce(0) { $0 + $1.area }
        guard rowTotal > 0 else { return row }
        var placed: [TreemapBlock] = []
        var offset: CGFloat = 0
        for (idx, block) in row.enumerated() {
            let length = (block.area / rowTotal) * side
            let frame: CGRect
            if horizontal {
                // 区块间留 gutter（最后一块不留）
                let isLast = idx == row.count - 1
                let height = max(0, length - (isLast ? 0 : gutter))
                frame = CGRect(x: rect.minX, y: rect.minY + offset,
                               width: rect.width, height: height)
            } else {
                let isLast = idx == row.count - 1
                let width = max(0, length - (isLast ? 0 : gutter))
                frame = CGRect(x: rect.minX + offset, y: rect.minY,
                               width: width, height: rect.height)
            }
            placed.append(block.withFrame(frame))
            offset += length
        }
        return placed
    }

    private func worstInRow(_ row: [TreemapBlock], side: CGFloat, horizontal: Bool) -> CGFloat {
        let total = row.reduce(0) { $0 + $1.area }
        guard total > 0 else { return .greatestFiniteMagnitude }
        return row.map { block in
            let length = (block.area / total) * side
            let rect: CGRect
            if horizontal {
                let w = length > 0 ? block.area / length : 0
                rect = CGRect(x: 0, y: 0, width: w, height: length)
            } else {
                let h = length > 0 ? block.area / length : 0
                rect = CGRect(x: 0, y: 0, width: length, height: h)
            }
            return aspectRatio(rect.size)
        }.max() ?? 0
    }

    private func aspectRatio(_ size: CGSize) -> CGFloat {
        guard size.width > 0, size.height > 0 else { return .greatestFiniteMagnitude }
        return max(size.width / size.height, size.height / size.width)
    }

    private func treemapCell(block: TreemapBlock, onSelect: @escaping (AllocationNode) -> Void) -> some View {
        let node = block.node
        let palette = blockPalette(for: node, index: block.index)
        let frame = block.frame
        let percentage = blockPercentage(for: block)

        return ZStack {
            // Visual: glassmorphism + 0.5px 极细高光描边 + 步进式透明度
            ZStack {
                // 1. 底色：步进式透明度（按金额占比分层）
                RoundedRectangle(cornerRadius: blockCornerRadius)
                    .fill(palette.fill)
                    .background(
                        // 2. 多层级 Glassmorphism 弥散光
                        RoundedRectangle(cornerRadius: blockCornerRadius)
                            .fill(.ultraThinMaterial)
                            .opacity(0.25)
                    )
                    .overlay(
                        // 3. 0.5px 极细高光描边（模拟玻璃切片）
                        RoundedRectangle(cornerRadius: blockCornerRadius)
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

                // 内容：左上 + 右下 非对称对齐
                if frame.width > 70, frame.height > 42 {
                    // 15% 内边距比例（按短边取），确保文字安全距离
                    let pad = max(8, min(frame.width, frame.height) * contentPaddingRatio)
                    ZStack(alignment: .topLeading) {
                        // 左上：图标 + 名称
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
                } else if frame.width > 32, frame.height > 22 {
                    // 小块：图标居中显示（避免贴左上角）
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

    private func blockPercentage(for block: TreemapBlock) -> Double {
        guard total > 0 else { return 0 }
        let amount = NSDecimalNumber(decimal: abs(block.node.balance)).doubleValue
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

    /// 步进式透明度：薄荷绿（资产）/ 稳重红（负债）+ 按 index 分层
private func blockPalette(for node: AllocationNode, index: Int) -> (fill: Color, accent: Color) {
    let baseHue: Double = node.isLiability ? 0.0 : 0.42
    let layer = index % 4
    // 步进式饱和度与亮度：层 0 = 主色 / 层 1-3 = 逐步淡化
    let saturation = node.isLiability
        ? [0.55, 0.50, 0.45, 0.40][layer]
        : [0.50, 0.45, 0.40, 0.35][layer]
    let brightness = node.isLiability
        ? [0.55, 0.62, 0.68, 0.74][layer]
        : [0.50, 0.58, 0.66, 0.74][layer]
    return (
        fill: Color(hue: baseHue, saturation: saturation, brightness: brightness).opacity(0.85),
        accent: Color(hue: baseHue, saturation: saturation + 0.1, brightness: min(brightness + 0.1, 1.0))
    )
}

    struct TreemapBlock: Identifiable {
        let node: AllocationNode
        let area: CGFloat
        let index: Int
        let frame: CGRect
        var id: String { node.id }

        init(node: AllocationNode, area: CGFloat, index: Int, frame: CGRect = .zero) {
            self.node = node
            self.area = area
            self.index = index
            self.frame = frame
        }

        func withFrame(_ frame: CGRect) -> TreemapBlock {
            TreemapBlock(node: node, area: area, index: index, frame: frame)
        }
    }
}