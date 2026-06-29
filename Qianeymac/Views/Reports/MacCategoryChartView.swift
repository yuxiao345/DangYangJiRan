import SwiftUI

// MARK: - Pie Slice Shape

private struct PieSliceShape: Shape {
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
        // Outer arc (clockwise)
        path.addArc(center: center, radius: outerRadius, startAngle: startAngle, endAngle: endAngle, clockwise: false)
        // Inner arc (counter-clockwise back to start)
        path.addArc(center: center, radius: innerRadius, startAngle: endAngle, endAngle: startAngle, clockwise: true)
        path.closeSubpath()
        return path
    }
}

// MARK: - Main View

struct MacCategoryChartView: View {
    let categories: [CategoryExpenseItem]
    let totalExpense: Decimal
    let centerTitle: String
    let isDrilledDown: Bool
    let isShowingTransactions: Bool
    let transactions: [Transaction]
    @Binding var categoryType: TransactionType
    let onCategoryTap: (UUID) -> Void
    let onCenterTap: () -> Void
    let onSelectTransaction: ((Transaction) -> Void)?

    @State private var barProgress: Double = 0
    @State private var pieProgress: Double = 0
    @State private var explodedIndex: Int? = nil
    @State private var hoveredIndex: Int? = nil

    private let explodeDistance: CGFloat = 14

    var body: some View {
        VStack(spacing: 0) {
            if isShowingTransactions {
                transactionListView
            } else if categories.isEmpty {
                emptyView
            } else {
                VStack(spacing: 0) {
                    pieSection
                    ScrollView {
                        categoryBars
                            .padding(.vertical, 12)
                    }
                }
            }
        }
        .onAppear { triggerAnimations() }
        .onChange(of: categories.map(\.id)) { _, _ in
            explodedIndex = nil
            triggerAnimations()
        }
    }

    private func triggerAnimations() {
        barProgress = 0
        pieProgress = 0
        Task {
            try? await Task.sleep(nanoseconds: 50_000_000)
            withAnimation(.spring(response: 0.6, dampingFraction: 0.65)) { barProgress = 1 }
            withAnimation(.easeOut(duration: 0.9)) { pieProgress = 1 }
        }
    }

    // MARK: - Empty

    private var emptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.pie.fill")
                .font(.system(size: 40))
                .foregroundStyle(Color.designOnSurfaceVariant.opacity(0.4))
            Text("暂无支出数据")
                .font(.designBodyMedium)
                .foregroundStyle(Color.designOnSurfaceVariant)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Pie Section

    private var pieSection: some View {
        VStack(spacing: 0) {
            // Top bar: back button or type pill
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
                    glassPillToggle
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)

            GeometryReader { geo in
                let size = geo.size
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let rawRadius = min(size.width, size.height) / 2
                let radius = rawRadius - 14  // padding so exploded segments stay inside glass card

                ZStack {
                    // Draw each pie slice
                    ForEach(Array(categories.enumerated()), id: \.element.id) { index, item in
                        let angles = segmentAngles(for: index)
                        let isExploded = explodedIndex == index
                        let midAngle = angles.start + (angles.end - angles.start) / 2
                        let offset = isExploded
                            ? CGSize(width: cos(midAngle) * explodeDistance,
                                     height: sin(midAngle) * explodeDistance)
                            : .zero

                        let slice = PieSliceShape(startAngle: Angle(radians: angles.start),
                                                  endAngle: Angle(radians: angles.end))
                        slice
                            .fill(Color(hex: item.colorHex) ?? .gray)
                            .overlay(slice.stroke(Color.white.opacity(0.15), lineWidth: 1))
                            .offset(offset)
                            .scaleEffect((isExploded || hoveredIndex == index) ? 1.04 : 1.0)
                            .shadow(color: (isExploded || hoveredIndex == index) ? .black.opacity(0.25) : .clear,
                                    radius: (isExploded || hoveredIndex == index) ? 8 : 0,
                                    y: (isExploded || hoveredIndex == index) ? 4 : 0)
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

                    // Center label — in the donut hole
                    VStack(spacing: 2) {
                        Text(centerTitle)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.designOnSurfaceVariant)
                        CurrencyText(amount: totalExpense, currencyCode: "", size: 20, foregroundColor: Color.designOnSurface)
                            .fontWeight(.black)
                    }
                    .position(center)
                    .allowsHitTesting(false)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Info panel — shown on explode or hover
                if let idx = explodedIndex ?? hoveredIndex, idx < categories.count {
                    let item = categories[idx]
                    HStack {
                        Spacer()
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
                                    .fontWeight(.bold)
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
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                        .padding(.trailing, 4)
                        .padding(.top, (size.height - 160) / 2)
                    }
                }
            }
            .frame(height: 220)
            .padding(.horizontal, 12)
            .padding(.bottom, 16)
        }
        .glassCard(cornerRadius: 20)
        .padding(.horizontal, 24)
        .padding(.top, 4)
        .padding(.bottom, 20)
        .animation(.spring(response: 0.45, dampingFraction: 0.65), value: explodedIndex)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: hoveredIndex)
    }

    private var glassPillToggle: some View {
        HStack(spacing: 0) {
            ForEach([TransactionType.expense, TransactionType.income], id: \.self) { type in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        categoryType = type
                    }
                } label: {
                    Text(type == .expense ? String(localized: "支出") : String(localized: "收入"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(
                            categoryType == type
                                ? Color.designOnSurface
                                : Color.designOnSurfaceVariant.opacity(0.7)
                        )
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .contentShape(Rectangle())
                        .background(periodPillBackground(active: categoryType == type))
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
    private func periodPillBackground(active: Bool) -> some View {
        if active {
            Capsule()
                .fill(Color.white.opacity(0.06))
                .background(.regularMaterial, in: Capsule())
                .overlay { Capsule().stroke(Color.white.opacity(0.15), lineWidth: 1) }
                .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
        }
    }

    /// Returns (startAngle, endAngle) in radians for the segment at the given index.
    /// Angles start from top (-π/2), grow clockwise. Sweep angle is scaled by `pieProgress`
    /// for initial fill-in animation.
    private func segmentAngles(for index: Int) -> (start: Double, end: Double) {
        let anglePerUnit = (2 * .pi) / precomputedTotal
        let cumulative = precomputedCumulatives[index]
        let start = -.pi / 2 + cumulative * anglePerUnit * pieProgress
        let end = start + categories[index].percentage * anglePerUnit * pieProgress
        return (start, end)
    }

    /// Precomputed once before ForEach: total percentage sum + cumulative sums per index.
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

    // MARK: - Transaction List (leaf drill-down)

    private var transactionListView: some View {
        VStack(spacing: 0) {
            // Back button header
            HStack {
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
                Spacer()
                CurrencyText(amount: totalExpense, currencyCode: "", size: 18, foregroundColor: Color.designOnSurface)
                    .fontWeight(.bold)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)

            Divider()
                .padding(.horizontal, 24)

            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(transactions.sorted(by: { $0.date > $1.date }), id: \.id) { tx in
                        Button {
                            onSelectTransaction?(tx)
                        } label: {
                            TransactionRowView(transaction: tx)
                                .padding(.vertical, 2)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
            }
        }
    }

    // MARK: - Category Bars

    private var categoryBars: some View {
        VStack(spacing: 8) {
            ForEach(Array(categories.enumerated()), id: \.element.id) { index, item in
                let isLeaf = item.children.isEmpty
                categoryRow(item, index: index, isLeaf: isLeaf)
            }
        }
        .padding(.horizontal, 24)
    }

    private func categoryRow(_ item: CategoryExpenseItem, index: Int, isLeaf: Bool) -> some View {
        Button {
            onCategoryTap(item.id)
        } label: {
            VStack(spacing: 6) {
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color(hex: item.colorHex) ?? .gray)
                        .frame(width: 12, height: 12)

                    Text(item.name)
                        .font(.designBodyMedium)
                        .foregroundStyle(Color.designOnSurface)

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        CurrencyText(amount: item.amount, currencyCode: "", size: 14, foregroundColor: Color.designOnSurface)
                            .fontWeight(.medium)
                        Text(String(format: "%.1f%%", item.percentage * 100))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Color.designOnSurfaceVariant)
                    }

                    if !isLeaf {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.designOnSurfaceVariant.opacity(0.4))
                    }
                }

                // Thermometer-fill bar: mask with scaleEffect from leading edge
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.designOnSurfaceVariant.opacity(0.1))
                            .frame(height: 6)
                        Capsule()
                            .fill(Color(hex: item.colorHex) ?? .gray)
                            .frame(height: 6)
                            .frame(width: max(6, geo.size.width * item.percentage))
                            .overlay(alignment: .top) {
                                Capsule()
                                    .fill(Color.white.opacity(0.18))
                                    .frame(height: 2)
                                    .padding(.horizontal, 2)
                            }
                            .mask(alignment: .leading) {
                                Rectangle()
                                    .scaleEffect(x: barProgress, anchor: .leading)
                            }
                            .animation(
                                .spring(response: 0.7, dampingFraction: 0.55)
                                .delay(Double(index) * 0.09),
                                value: barProgress
                            )
                    }
                }
                .frame(height: 6)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
            .glassCard(cornerRadius: 10)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering {
                explodedIndex = nil
                hoveredIndex = index
            } else {
                hoveredIndex = nil
            }
        }
    }
}
