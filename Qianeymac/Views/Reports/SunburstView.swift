import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

/// Sunburst（旭日图）层级资产配置可视化
/// - L1：内圆显示净资产汇总，外圈按类型（资产/负债）分配扇区
/// - L2：选中某类型后，外圈变为该类型下的账户明细，中心显示该类型汇总
struct SunburstView: View {
    typealias AllocationNode = AccountAllocationItem.AllocationNode

    let nodes: [AllocationNode]      // 当前层级（L1 = 类型，L2 = 账户）
    let total: Decimal               // 当前层级的总额（用于计算扇区角度）
    let centerLabel: String          // 内圆主标签
    let centerValue: String          // 内圆主值
    let centerSubLabel: String?      // 内圆副标签
    let isDrilled: Bool              // 是否处于 L2 下钻状态
    let onSelect: (AllocationNode) -> Void
    let onReturnToRoot: () -> Void

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let radius = side * 0.45

            ZStack {
                Canvas { ctx, _ in
                    drawSectors(in: ctx, center: center, radius: radius, side: side)
                }
                .contentShape(Rectangle())
                .accessibilityLabel(Text("选择资产配置分区"))
                .accessibilityAddTraits(.isButton)
                .accessibilityAction {
                    handleTap(at: CGPoint(x: geo.size.width / 2, y: geo.size.height / 2), center: center, radius: radius)
                }
                .onTapGesture { location in
                    handleTap(at: location, center: center, radius: radius)
                }

                SunburstCenter(
                    label: centerLabel,
                    value: centerValue,
                    subLabel: centerSubLabel,
                    isDrilled: isDrilled,
                    onReturn: onReturnToRoot
                )
                .frame(width: radius * 1.4, height: radius * 1.4)
                .position(center)
            }
        }
    }

    private func drawSectors(in ctx: GraphicsContext, center: CGPoint, radius: CGFloat, side: CGFloat) {
        guard total > 0, !nodes.isEmpty else { return }

        let grandTotal = CGFloat(NSDecimalNumber(decimal: total).doubleValue)
        guard grandTotal > 0 else { return }

        var startAngle = -CGFloat.pi / 2
        let gap: CGFloat = 0.012

        for node in nodes {
            let fraction = CGFloat(NSDecimalNumber(decimal: node.balance).doubleValue) / grandTotal
            let sweep = max(0.001, fraction * 2 * .pi - gap)
            let endAngle = startAngle + sweep

            // 配色：资产绿色系 / 负债红色系，按占比调整饱和度
            let pct = Double(fraction)
            let opacity = 0.45 + pct * 0.45
            let baseColor: Color = node.isLiability ? .designAccentRed : .designPrimaryFixedDim

            let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
            var path = Path()
            path.move(to: center)
            path.addArc(
                center: center,
                radius: radius,
                startAngle: .radians(startAngle),
                endAngle: .radians(endAngle),
                clockwise: false
            )
            path.closeSubpath()

            ctx.fill(path, with: .color(baseColor.opacity(opacity)))

            // 扇区上的文字：仅当扇区足够大时显示
            if sweep > 0.3 {
                let midAngle = (startAngle + endAngle) / 2
                let labelRadius = radius * 0.78
                let labelPoint = CGPoint(
                    x: center.x + labelRadius * cos(midAngle),
                    y: center.y + labelRadius * sin(midAngle)
                )

                let displayName = node.name
                let pctText = Text(pct, format: .percent.precision(.fractionLength(1)))
                let nameFontSize = min(11, side / 30)
                let pctFontSize = min(10, side / 35)

                let nameText = Text(displayName)
                    .font(.system(size: nameFontSize, weight: .medium))
                    .foregroundStyle(.white.opacity(0.95))
                let pctTextView = pctText
                    .font(.system(size: pctFontSize, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.7))

                ctx.draw(nameText, at: CGPoint(x: labelPoint.x, y: labelPoint.y - 8))
                ctx.draw(pctTextView, at: CGPoint(x: labelPoint.x, y: labelPoint.y + 10))
            }

            startAngle = endAngle + gap
        }
    }

    private func handleTap(at location: CGPoint, center: CGPoint, radius: CGFloat) {
        let dx = location.x - center.x
        let dy = location.y - center.y
        let distance = sqrt(dx * dx + dy * dy)

        // 点击内圆 → 返回 L1
        if distance < radius * 0.42 {
            if isDrilled { onReturnToRoot() }
            return
        }

        // 点击外圈 → 解析扇区
        guard distance <= radius else { return }
        var angle = atan2(dy, dx)
        if angle < -.pi / 2 { angle += 2 * .pi }

        let grandTotal = CGFloat(truncating: (abs(total) as NSDecimalNumber))
        guard grandTotal > 0 else { return }
        let gap: CGFloat = 0.012
        var startAngle = -CGFloat.pi / 2

        for node in nodes {
            let fraction = CGFloat(NSDecimalNumber(decimal: node.balance).doubleValue) / grandTotal
            let sweep = max(0.001, fraction * 2 * .pi - gap)
            let endAngle = startAngle + sweep
            if angle >= startAngle && angle < endAngle {
                if node.drillKey != nil || !isDrilled {
                    onSelect(node)
                }
                return
            }
            startAngle = endAngle + gap
        }
    }
}

/// 中心圆：显示当前层级汇总
private struct SunburstCenter: View {
    let label: String
    let value: String
    let subLabel: String?
    let isDrilled: Bool
    let onReturn: () -> Void

    var body: some View {
        ZStack {
            Circle()
                .fill(.ultraThinMaterial)
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.2), radius: 8, y: 4)

            VStack(spacing: 3) {
                if isDrilled {
                    Button {
                        onReturn()
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 8, weight: .semibold))
                            Text(String(localized: "返回"))
                                .font(.system(size: 9, weight: .medium))
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.designPrimaryFixedDim)
                } else {
                    Text(label)
                        .font(.system(size: 9))
                        .foregroundStyle(Color.designOnSurfaceVariant)
                }

                Text(value)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.designOnSurface)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)

                if let sub = subLabel {
                    Text(sub)
                        .font(.system(size: 8))
                        .foregroundStyle(Color.designOnSurfaceVariant)
                }
            }
            .padding(6)
        }
    }
}