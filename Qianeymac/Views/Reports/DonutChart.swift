import SwiftUI

// MARK: - Pie Slice Shape

struct PieSliceShape: Shape {
    var startAngle: Angle
    var endAngle: Angle
    var innerRadiusFraction: CGFloat = 0.55

    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(startAngle.radians, endAngle.radians) }
        set {
            startAngle = Angle(radians: newValue.first)
            endAngle = Angle(radians: newValue.second)
        }
    }

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outerRadius = min(rect.width, rect.height) / 2
        let innerRadius = outerRadius * innerRadiusFraction
        var path = Path()
        path.addArc(center: center, radius: outerRadius, startAngle: startAngle, endAngle: endAngle, clockwise: false)
        path.addArc(center: center, radius: innerRadius, startAngle: endAngle, endAngle: startAngle, clockwise: true)
        path.closeSubpath()
        return path
    }
}

// MARK: - Donut Chart

struct DonutChart: View {
    let categories: [CategoryExpenseItem]
    let totalExpense: Decimal
    let centerTitle: String
    let isDrilledDown: Bool
    var showTopBar: Bool = true
    @Binding var categoryType: TransactionType
    let onCategoryTap: (UUID) -> Void
    let onCenterTap: () -> Void

    @Binding var pieProgress: Double
    @Binding var explodedIndex: Int?
    @Binding var hoveredIndex: Int?

    private let explodeDistance: CGFloat = 14

    var body: some View {
        VStack(spacing: 0) {
            if showTopBar { topBar }
            GeometryReader { geo in
                let size = geo.size
                let panelVisible = (explodedIndex ?? hoveredIndex) != nil && (explodedIndex ?? hoveredIndex)! < categories.count
                let panelShift: CGFloat = panelVisible ? -50 : 0
                let panelGap: CGFloat = 30
                let halfPanelWidth: CGFloat = 70
                let adjustedCenter = CGPoint(x: size.width / 2 + panelShift, y: size.height / 2)
                let rawRadius = min(size.width, size.height) / 2
                let radius = rawRadius - 14

                ZStack {
                    ForEach(Array(categories.enumerated()), id: \.element.id) { index, item in
                        sliceView(for: index, item: item, center: adjustedCenter, radius: radius)
                    }

                    centerLabel
                        .position(adjustedCenter)
                        .allowsHitTesting(false)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                infoPanel(size: size, radius: radius, panelShift: panelShift, panelGap: panelGap, halfPanelWidth: halfPanelWidth)
            }
            .frame(height: 220)
            .padding(.horizontal, 12)
            .padding(.bottom, 16)
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.65), value: explodedIndex)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: hoveredIndex)
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            if isDrilledDown {
                Button {
                    onCenterTap()
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(DesignGlassCircleButton())
                Text(centerTitle)
                    .font(.designBodyMedium)
                    .foregroundStyle(Color.designOnSurface)
                    .padding(.leading, 8)
            } else {
                GlassPillToggle(selection: $categoryType)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 17)
    }

    // MARK: - Slice

    private func sliceView(for index: Int, item: CategoryExpenseItem, center: CGPoint, radius: CGFloat) -> some View {
        let angles = segmentAngles(for: index)
        let isExploded = explodedIndex == index
        let isHighlighted = isExploded || hoveredIndex == index
        let midAngle = angles.start + (angles.end - angles.start) / 2
        let offset = isExploded
            ? CGSize(width: cos(midAngle) * explodeDistance,
                     height: sin(midAngle) * explodeDistance)
            : .zero

        let slice = PieSliceShape(startAngle: Angle(radians: angles.start),
                                  endAngle: Angle(radians: angles.end))
        return slice
            .fill(Color(hex: item.colorHex) ?? .gray)
            .overlay(slice.stroke(Color.white.opacity(0.15), lineWidth: 1))
            .offset(offset)
            .scaleEffect(isHighlighted ? 1.04 : 1.0)
            .shadow(color: isHighlighted ? .black.opacity(0.25) : .clear,
                    radius: isHighlighted ? 8 : 0,
                    y: isHighlighted ? 4 : 0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: hoveredIndex)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: explodedIndex)
            .frame(width: radius * 2, height: radius * 2)
            .position(center)
            .onTapGesture {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.65)) {
                    explodedIndex = (explodedIndex == index) ? nil : index
                }
            }
    }

    // MARK: - Center Label

    private var centerLabel: some View {
        VStack(spacing: 2) {
            Text(centerTitle)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.designOnSurfaceVariant)
            CurrencyText(amount: totalExpense, currencyCode: "", size: 20, foregroundColor: Color.designOnSurface, fractionDigits: 0)
                .fontWeight(.black)
        }
    }

    // MARK: - Info Panel

    private func infoPanel(size: CGSize, radius: CGFloat, panelShift: CGFloat, panelGap: CGFloat, halfPanelWidth: CGFloat) -> some View {
        Group {
            if let idx = explodedIndex ?? hoveredIndex, idx < categories.count {
                let item = categories[idx]
                // donut center shifted left by panelShift, radius outward; panel positioned to the right with panelGap
                let panelLeftX = size.width / 2 + panelShift + radius + panelGap
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color(hex: item.colorHex) ?? .gray)
                            .frame(width: 10, height: 10)
                        Text(item.name)
                            .font(.designBodyMedium)
                            .foregroundStyle(Color.designOnSurface)
                    }
                    Divider()
                    VStack(alignment: .leading, spacing: 4) {
                        Text(String(localized: "金额"))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.designOnSurfaceVariant)
                        CurrencyText(amount: item.amount, currencyCode: "", size: 18, foregroundColor: Color.designOnSurface)
                            .bold()
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(String(localized: "占比"))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.designOnSurfaceVariant)
                        Text(String(format: "%.1f%%", item.percentage * 100))
                            .font(.system(size: 20, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.designOnSurface)
                    }
                }
                .padding(16)
                .frame(width: 140)
                .glassCard(cornerRadius: 12)
                .transition(.opacity.combined(with: .offset(x: -50)))
                .position(x: panelLeftX + halfPanelWidth, y: size.height / 2)
            }
        }
    }

    // MARK: - Angle Calculation

    private func segmentAngles(for index: Int) -> (start: Double, end: Double) {
        let anglePerUnit = (2 * .pi) / precomputedTotal
        let cumulative = precomputedCumulatives[index]
        let start = -.pi / 2 + cumulative * anglePerUnit * pieProgress
        let end = start + categories[index].percentage * anglePerUnit * pieProgress
        return (start, end)
    }

    private var precomputedTotal: Double {
        categories.reduce(0.0) { $0 + $1.percentage }
    }

    private var precomputedCumulatives: [Double] {
        var result: [Double] = []
        var sum: Double = 0
        for item in categories {
            result.append(sum)
            sum += item.percentage
        }
        return result
    }
}

// MARK: - Glass Pill Toggle

struct GlassPillToggle: View {
    @Binding var selection: TransactionType

    var body: some View {
        HStack(spacing: 0) {
            ForEach([TransactionType.expense, TransactionType.income], id: \.self) { type in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        selection = type
                    }
                } label: {
                    Text(type == .expense ? String(localized: "支出") : String(localized: "收入"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(
                            selection == type
                                ? Color.designOnSurface
                                : Color.designOnSurfaceVariant.opacity(0.7)
                        )
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .contentShape(Rectangle())
                        .background(activePillBackground(active: selection == type))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background { Capsule().fill(Color.designGlassBg) }
        .background(.regularMaterial, in: Capsule())
        .overlay { Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1) }
        .overlay { Capsule().stroke(Color.white.opacity(0.04), lineWidth: 1).padding(1) }
        .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
    }

    @ViewBuilder
    private func activePillBackground(active: Bool) -> some View {
        if active {
            Capsule()
                .fill(Color.white.opacity(0.06))
                .background(.regularMaterial, in: Capsule())
                .overlay { Capsule().stroke(Color.white.opacity(0.15), lineWidth: 1) }
                .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
        }
    }
}
