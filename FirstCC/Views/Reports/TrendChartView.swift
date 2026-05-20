import SwiftUI

struct TrendChartView: View {
    let dataPoints: [TrendDataPoint]
    let period: ReportPeriod

    @State private var showIncome = true
    @State private var showExpense = true

    private let maxBlocks = 20
    private let blockGap: CGFloat = 1
    private let labelAreaHeight: CGFloat = 20

    private var totalIncome: Decimal {
        dataPoints.map(\.income).reduce(0, +)
    }

    private var totalExpense: Decimal {
        dataPoints.map(\.expense).reduce(0, +)
    }

    private var netBalance: Decimal {
        totalIncome - totalExpense
    }

    private var barMax: Double {
        let all = dataPoints.flatMap {
            [Double(truncating: $0.income as NSNumber),
             Double(truncating: $0.expense as NSNumber)]
        }
        return all.max() ?? 1
    }

    var body: some View {
        if dataPoints.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "chart.bar")
                    .font(.largeTitle)
                    .foregroundStyle(Color.designOnSurfaceVariant)
                Text("暂无收支数据")
                    .foregroundStyle(Color.designOnSurfaceVariant)
            }
        } else {
            VStack(spacing: 0) {
                summaryHeader
                pixelChart
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Summary Header

    private var summaryHeader: some View {
        HStack(spacing: 0) {
            summaryBlock(
                label: TransactionType.income.displayName,
                amount: totalIncome,
                color: .green,
                isActive: showIncome
            ) {
                withAnimation(.easeInOut(duration: 0.2)) { showIncome.toggle() }
            }

            summaryBlock(
                label: TransactionType.expense.displayName,
                amount: totalExpense,
                color: .red,
                isActive: showExpense
            ) {
                withAnimation(.easeInOut(duration: 0.2)) { showExpense.toggle() }
            }

            summaryBlock(
                label: "结余",
                amount: netBalance,
                color: netBalance >= 0 ? .green : .red,
                isActive: true
            ) {}
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.designOutlineVariant.opacity(0.15))
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }

    private func summaryBlock(
        label: String,
        amount: Decimal,
        color: Color,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                HStack(spacing: 3) {
                    PixelBlock(color: color, size: 6)
                    Text(label)
                        .font(.designLabel)
                        .foregroundStyle(Color.designOnSurfaceVariant)
                }
                CurrencyText(amount: amount, currencyCode: "", size: 12, foregroundColor: color)
                    .fontWeight(.bold)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .opacity(isActive ? 1 : 0.3)
    }

    // MARK: - Pixel Chart

    private var pixelChart: some View {
        let ceiling = niceCeiling(barMax)

        return GeometryReader { geo in
            let legendH: CGFloat = 18
            let dynBlockPx = max(4, min(20, (geo.size.height - legendH - labelAreaHeight - 28) / CGFloat(maxBlocks) - blockGap))
            let minColW = dynBlockPx * 2 + blockGap + 8
            let totalNeed = minColW * CGFloat(dataPoints.count)
            let availW = geo.size.width - 32 - 24
            let useScroll = totalNeed > availW
            let colPad: CGFloat = useScroll ? 3 : max(3, (availW - totalNeed) / CGFloat(dataPoints.count) / 2)

            VStack(spacing: 4) {
                HStack(alignment: .bottom, spacing: 2) {
                    yAxisColumn(blockSize: dynBlockPx, maxValue: ceiling)

                    if useScroll {
                        ScrollView(.horizontal, showsIndicators: false) {
                            barRow(maxValue: ceiling, blockSize: dynBlockPx, colPad: colPad)
                        }
                    } else {
                        barRow(maxValue: ceiling, blockSize: dynBlockPx, colPad: colPad)
                            .frame(maxWidth: .infinity)
                    }
                }

                Spacer(minLength: 0)

                legendRow
            }
            .padding(8)
            .background {
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.designOutlineVariant.opacity(0.3), lineWidth: 1)
            }
        }
        .padding(.horizontal, 12)
    }

    private var legendRow: some View {
        HStack(spacing: 12) {
            legendDot(color: .designAccentGreen, label: "收入")
            legendDot(color: .designAccentRed, label: "支出")
            legendDot(color: .blue, label: "结余趋势")
        }
    }

    private func barRow(maxValue: Double, blockSize: CGFloat, colPad: CGFloat) -> some View {
        HStack(alignment: .bottom, spacing: 0) {
            ForEach(Array(dataPoints.enumerated()), id: \.element.id) { i, point in
                VStack(spacing: 2) {
                    pixelBarsColumn(for: point, maxValue: maxValue, blockSize: blockSize)
                    xLabel(for: point)
                        .frame(height: labelAreaHeight)
                }
                .padding(.horizontal, colPad)
            }
        }
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 3) {
            PixelBlock(color: color, size: 5)
            Text(label)
                .font(.designBodySmall)
                .foregroundStyle(Color.designOnSurfaceVariant)
        }
    }

    // MARK: - Y Axis Labels

    private func yAxisColumn(blockSize: CGFloat, maxValue: Double) -> some View {
        let rowIndices = [20, 15, 10, 5, 0]

        return VStack(spacing: 2) {
            VStack(spacing: blockGap) {
                ForEach(0..<maxBlocks, id: \.self) { i in
                    let row = maxBlocks - 1 - i
                    if rowIndices.contains(row) {
                        let value = Double(row) / Double(maxBlocks) * maxValue
                        Text(formatAxis(value))
                            .font(.system(size: 7).monospacedDigit())
                            .foregroundStyle(Color.designOnSurfaceVariant)
                            .lineLimit(1)
                            .frame(height: blockSize, alignment: .center)
                    } else {
                        Color.clear.frame(height: blockSize)
                    }
                }
            }
            Color.clear.frame(height: labelAreaHeight)
        }
        .frame(width: 32)
    }

    /// Compute a "nice" ceiling, then always bump one step up so bars never touch the top
    private func niceCeiling(_ value: Double) -> Double {
        guard value > 0 else { return 1 }
        let mag = pow(10, floor(log10(value)))
        let norm = value / mag
        let raw: Double
        if norm <= 1 { raw = 1 }
        else if norm <= 2 { raw = 2 }
        else if norm <= 5 { raw = 5 }
        else { raw = 10 }
        // Bump up one nice step
        let bumped: Double = raw == 1 ? 2 : raw == 2 ? 5 : raw == 5 ? 10 : 20
        return bumped * mag
    }

    private func formatAxis(_ value: Double) -> String {
        if value >= 10000 {
            let wan = value / 10000
            return wan.formatted(.number.precision(.fractionLength(0...1))) + "万"
        }
        return value.formatted(.number.grouping(.automatic).precision(.fractionLength(0)))
    }

    // MARK: - Pixel Bars Column

    private func pixelBarsColumn(for point: TrendDataPoint, maxValue: Double, blockSize: CGFloat) -> some View {
        let incomeVal = Double(truncating: point.income as NSNumber)
        let expenseVal = Double(truncating: point.expense as NSNumber)
        let netVal = incomeVal - expenseVal
        let incomeBlocks = Int((incomeVal / maxValue * Double(maxBlocks)).rounded())
        let expenseBlocks = Int((expenseVal / maxValue * Double(maxBlocks)).rounded())

        let netBlockIdx: Int? = {
            guard maxValue > 0 else { return nil }
            let raw = Int((netVal / maxValue * Double(maxBlocks)).rounded())
            return max(0, min(maxBlocks - 1, raw))
        }()

        return HStack(alignment: .bottom, spacing: blockGap) {
            if showIncome {
                VStack(spacing: blockGap) {
                    ForEach(0..<maxBlocks, id: \.self) { i in
                        let row = maxBlocks - 1 - i
                        let isTrend = netBlockIdx == row
                        PixelBlock(
                            color: row < incomeBlocks ? (isTrend ? .blue : .green) : blockBg,
                            size: blockSize
                        )
                    }
                }
            }

            if showExpense {
                VStack(spacing: blockGap) {
                    ForEach(0..<maxBlocks, id: \.self) { i in
                        let row = maxBlocks - 1 - i
                        let isTrend = netBlockIdx == row
                        PixelBlock(
                            color: row < expenseBlocks ? (isTrend ? .blue : .red) : blockBg,
                            size: blockSize
                        )
                    }
                }
            }
        }
    }

    private var blockBg: Color {
        Color.designOutlineVariant.opacity(0.12)
    }

    // MARK: - X Axis Label

    @ViewBuilder
    private func xLabel(for point: TrendDataPoint) -> some View {
        if period == .last3Years {
            VStack(spacing: 0) {
                Text(point.yearLabel ?? " ")
                    .font(.system(size: 7).monospacedDigit())
                    .foregroundStyle(Color.designOnSurfaceVariant.opacity(0.6))
                Text(shortLabel(for: point))
                    .font(.system(size: 7).monospacedDigit())
                    .foregroundStyle(Color.designOnSurfaceVariant.opacity(0.6))
            }
        } else {
            Text(point.label)
                .font(.designMonoDataSmall)
                .foregroundStyle(Color.designOnSurfaceVariant)
        }
    }

    private func shortLabel(for point: TrendDataPoint) -> String {
        if let yl = point.yearLabel, point.label.hasPrefix(yl) {
            return String(point.label.dropFirst(yl.count))
        }
        return point.label
    }
}
