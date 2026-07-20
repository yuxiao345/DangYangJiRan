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

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let rects = computeRects(in: CGRect(origin: .zero, size: size))
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
                return log10(max(1, amount)) + 1   // log10 + 1 保证值始终 >= 0
            case .sqrt:
                return sqrt(amount)
            }
        }
        let totalWeight = weights.reduce(0, +)
        guard totalWeight > 0 else { return [] }

        // 2. 预计算目标面积（按权重）
        let containerArea = container.width * container.height
        var blocks: [TreemapBlock] = []
        var assignedArea: CGFloat = 0
        var i = 0
        while i < nodes.count {
            let w = weights[i]
            let idealArea = CGFloat(w / totalWeight) * containerArea

            // 3. 应用最小阈值（仅最后几个区块需要兜底）
            let remainingCount = nodes.count - i
            let minArea = minBlockSide * minBlockSide
            // 估算剩余空间
            let remainingArea = containerArea - assignedArea
            let idealRemaining = CGFloat(weights[i...].reduce(0, +) / totalWeight) * containerArea
            // 如果理想面积太小，把它放大到 minArea
            let targetArea: CGFloat
            if idealArea < minArea && idealRemaining > minArea * CGFloat(remainingCount) {
                targetArea = minArea
            } else if idealRemaining < minArea * CGFloat(remainingCount) {
                // 空间不够均分，使用剩余空间等分
                targetArea = remainingArea / CGFloat(remainingCount)
            } else {
                targetArea = idealArea
            }

            blocks.append(TreemapBlock(node: nodes[i], area: targetArea, index: i))
            assignedArea += targetArea
            i += 1
        }

        // 4. 归一化（防止浮点累积误差超出边界）
        let totalAssigned = blocks.reduce(0) { $0 + $1.area }
        if totalAssigned > 0 {
            let scale = containerArea / totalAssigned
            blocks = blocks.map { TreemapBlock(node: $0.node, area: $0.area * scale, index: $0.index) }
        }

        // 5. Squarified treemap 布局
        return squarify(blocks: blocks, in: container)
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
        let side = horizontal ? rect.height : rect.width

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
            rowRect = CGRect(x: rect.minX, y: rect.minY, width: rowThickness, height: rect.height)
            remainingRect = CGRect(x: rect.minX + rowThickness, y: rect.minY,
                                   width: max(0, rect.width - rowThickness), height: rect.height)
        } else {
            rowRect = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rowThickness)
            remainingRect = CGRect(x: rect.minX, y: rect.minY + rowThickness,
                                   width: rect.width, height: max(0, rect.height - rowThickness))
        }

        let laidOut = layoutRow(row, in: rowRect, side: side, horizontal: horizontal)
        let tail = squarifyRecursive(rest, in: remainingRect)
        return laidOut + tail
    }

    private func layoutRow(_ row: [TreemapBlock], in rect: CGRect, side: CGFloat, horizontal: Bool) -> [TreemapBlock] {
        let rowTotal = row.reduce(0) { $0 + $1.area }
        guard rowTotal > 0 else { return row }
        var placed: [TreemapBlock] = []
        var offset: CGFloat = 0
        for block in row {
            let length = (block.area / rowTotal) * side
            let frame: CGRect
            if horizontal {
                frame = CGRect(x: rect.minX, y: rect.minY + offset,
                               width: rect.width, height: length)
            } else {
                frame = CGRect(x: rect.minX + offset, y: rect.minY,
                               width: length, height: rect.height)
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
        let fill = blockColor(for: node, index: block.index)
        let frame = block.frame

        return ZStack {
            // Visual
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(fill)
                    .shadow(color: .black.opacity(0.2), radius: 3, y: 2)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
                    )

                if frame.width > 60, frame.height > 36 {
                    let pad = min(8, frame.width * 0.06, frame.height * 0.08)
                    VStack(spacing: 0) {
                        HStack(alignment: .top) {
                            HStack(spacing: 3) {
                                Image(systemName: node.iconName)
                                    .font(.system(size: min(11, frame.height * 0.35)))
                                    .foregroundStyle(.white.opacity(0.9))
                                Text(node.name)
                                    .font(.system(size: min(10, frame.width * 0.07), weight: .medium))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                            }
                            Spacer()
                        }
                        Spacer()
                        HStack {
                            Spacer()
                            Text(formatAmount(abs(node.balance)))
                                .font(.system(size: min(11, frame.width * 0.08), weight: .bold, design: .monospaced))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                        }
                    }
                    .padding(pad)
                } else if frame.width > 36, frame.height > 22 {
                    Image(systemName: node.iconName)
                        .font(.system(size: min(12, frame.width * 0.2)))
                        .foregroundStyle(.white.opacity(0.85))
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

    private func blockColor(for node: AllocationNode, index: Int) -> Color {
        let baseHue: Double = node.isLiability ? 0.0 : 0.4
        let saturation = 0.55 + Double(index % 3) * 0.15
        let brightness = 0.55 + Double((index + 1) % 4) * 0.08
        return Color(hue: baseHue, saturation: saturation, brightness: brightness)
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