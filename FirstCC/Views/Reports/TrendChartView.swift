import SwiftUI

struct TrendChartView: View {
    let dataPoints: [TrendDataPoint]
    let period: ReportPeriod

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

    private var incomeMax: Double {
        dataPoints.map { Double(truncating: $0.income as NSNumber) }.max() ?? 1
    }

    private var expenseMax: Double {
        dataPoints.map { Double(truncating: $0.expense as NSNumber) }.max() ?? 1
    }

    /// Y-axis ceiling: max of both scales, so labels cover the full range
    private var barMax: Double {
        max(incomeMax, expenseMax)
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
                summaryCards
                pixelChart
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Summary Cards

    private var summaryCards: some View {
        HStack(spacing: 8) {
            summaryCard(label: "收入", amount: totalIncome, color: Color.designAccentGreen)
            summaryCard(label: "支出", amount: totalExpense, color: Color.designAccentRed)
            summaryCard(label: "结余", amount: netBalance, color: netBalance >= 0 ? Color.designAccentGreen : Color.designAccentRed)
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }

    private func summaryCard(label: String, amount: Decimal, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(color)
                    .frame(width: 6, height: 6)
                Text(LocalizedStringKey(label))
                    .font(.custom("JetBrainsMono-Medium", fixedSize: 9))
                    .foregroundStyle(color.opacity(0.8))
            }
            CurrencyText(amount: amount, currencyCode: "", size: 14, foregroundColor: color, fractionDigits: 0)
                .fontWeight(.bold)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .glassCard(cornerRadius: 12)
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
        .padding(.top, 16)
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
            Text(LocalizedStringKey(label))
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

    private func niceCeiling(_ value: Double) -> Double {
        value * 1.3
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
        let incomeBlocks = incomeVal > 0 ? max(1, Int((incomeVal / maxValue * Double(maxBlocks)).rounded(.up))) : 0
        let expenseBlocks = expenseVal > 0 ? max(1, Int((expenseVal / maxValue * Double(maxBlocks)).rounded(.up))) : 0

        // Blue net marker: appears in income column when net>0, expense column when net<0
        let incomeNetIdx: Int? = {
            guard maxValue > 0, netVal > 0 else { return nil }
            let raw = Int((netVal / maxValue * Double(maxBlocks)).rounded())
            return min(maxBlocks - 1, raw)
        }()
        let expenseNetIdx: Int? = {
            guard maxValue > 0, netVal < 0 else { return nil }
            let raw = Int((-netVal / maxValue * Double(maxBlocks)).rounded())
            return min(maxBlocks - 1, raw)
        }()

        return HStack(alignment: .bottom, spacing: blockGap) {
            VStack(spacing: blockGap) {
                ForEach(0..<maxBlocks, id: \.self) { i in
                    let row = maxBlocks - 1 - i
                    let isTrend = incomeNetIdx == row
                    PixelBlock(
                        color: row < incomeBlocks ? (isTrend ? .blue : .green) : blockBg,
                        size: blockSize
                    )
                }
            }

            VStack(spacing: blockGap) {
                ForEach(0..<maxBlocks, id: \.self) { i in
                    let row = maxBlocks - 1 - i
                    let isTrend = expenseNetIdx == row
                    PixelBlock(
                        color: row < expenseBlocks ? (isTrend ? .blue : .red) : blockBg,
                        size: blockSize
                    )
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
                    .font(.system(size: 7))
                    .foregroundStyle(Color.designOnSurfaceVariant.opacity(0.6))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text(shortLabel(for: point))
                    .font(.system(size: 7))
                    .foregroundStyle(Color.designOnSurfaceVariant.opacity(0.6))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
        } else {
            Text(point.label)
                .font(.system(size: 8))
                .foregroundStyle(Color.designOnSurfaceVariant)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
    }

    private func shortLabel(for point: TrendDataPoint) -> String {
        if let yl = point.yearLabel, point.label.hasPrefix(yl) {
            return String(point.label.dropFirst(yl.count))
        }
        return point.label
    }
}
