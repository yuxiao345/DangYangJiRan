import SwiftUI
import Charts

struct MacTrendChartView: View {
    let dataPoints: [TrendDataPoint]

    @Environment(AppContainer.self) private var appContainer

    private var currencyCode: String { appContainer.currentCurrencyCode }

    @State private var selectedDate: String?
    @State private var showIncome = true
    @State private var showExpense = true
    @State private var showNet = true
    @State private var pointerY: CGFloat = 80
    @State private var lineProgress: CGFloat = 0
    @State private var areaFillProgress: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            if dataPoints.isEmpty {
                emptyView
            } else {
                summaryCards
                trendChart
                    .mask(alignment: .leading) {
                        Rectangle().scaleEffect(x: lineProgress, y: 1, anchor: .leading)
                    }
                    .layoutPriority(1)
                    .padding(20)
                    .glassCard(cornerRadius: 20)
                    .designGrain()
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
                legendBar
            }
        }
        .onAppear { startDrawAnimation(delay: 0) }
        .onChange(of: dataPoints.map(\.id)) { _, _ in startDrawAnimation(delay: 0) }
    }

    // MARK: - Empty

    private var emptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 40))
                .foregroundStyle(Color.designOnSurfaceVariant.opacity(0.4))
            Text("暂无收支数据")
                .font(.designBodyMedium)
                .foregroundStyle(Color.designOnSurfaceVariant)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Computed

    private var totalIncome: Decimal {
        dataPoints.reduce(0) { $0 + $1.income }
    }

    private var totalExpense: Decimal {
        dataPoints.reduce(0) { $0 + $1.expense }
    }

    private var totalNet: Decimal {
        totalIncome + totalExpense
    }

    private var avgIncome: Decimal {
        dataPoints.isEmpty ? 0 : totalIncome / Decimal(dataPoints.count)
    }

    private var avgExpense: Decimal {
        dataPoints.isEmpty ? 0 : totalExpense / Decimal(dataPoints.count)
    }

    private var yAxisMax: Double {
        var maxVal: Double = 100
        for dp in dataPoints {
            if showIncome { maxVal = max(maxVal, Double(truncating: dp.income as NSNumber)) }
            if showExpense { maxVal = max(maxVal, Double(truncating: dp.expense as NSNumber)) }
            if showNet { maxVal = max(maxVal, abs(Double(truncating: (dp.income - dp.expense) as NSNumber))) }
        }
        return maxVal * 1.15
    }

    /// Show every Nth label to avoid crowding. More data → larger stride.
    private var strideLabels: [String] {
        let count = dataPoints.count
        let step = count > 24 ? 3 : (count > 12 ? 2 : 1)
        return stride(from: 0, to: count, by: step).map { dataPoints[$0].label }
    }

    private func startDrawAnimation(delay: Double) {
        lineProgress = 0
        areaFillProgress = 0
        withAnimation(.easeOut(duration: 1.2)) { lineProgress = 1 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation(.easeOut(duration: 0.6)) { areaFillProgress = 1 }
        }
    }

    private func net(for dp: TrendDataPoint) -> Decimal {
        dp.income - dp.expense
    }

    // MARK: - Summary Cards (tappable to toggle)

    private var summaryCards: some View {
        HStack(spacing: 16) {
            summaryCell(
                label: String(localized: "总收入"), amount: totalIncome,
                color: Color.designPrimaryFixedDim, isOn: showIncome
            ) { showIncome.toggle() }

            summaryCell(
                label: String(localized: "总支出"), amount: abs(totalExpense),
                color: Color.designAccentRed, isOn: showExpense
            ) { showExpense.toggle() }

            summaryCell(
                label: String(localized: "结余"), amount: totalNet,
                color: Color.blue,
                isOn: showNet
            ) { showNet.toggle() }
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
    }

    private func summaryCell(label: String, amount: Decimal, color: Color, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text(label)
                    .font(.designBodyCaption)
                    .foregroundStyle(isOn ? Color.designOnSurfaceVariant : Color.designOnSurfaceVariant.opacity(0.4))
                CurrencyText(amount: amount, currencyCode: "", showSign: false, size: 20, foregroundColor: isOn ? color : color.opacity(0.3), fractionDigits: 0)
                    .bold()
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .glassCard(cornerRadius: 12)
        .opacity(isOn ? 1.0 : 0.5)
    }

    // MARK: - Trend Chart

    private var trendChart: some View {
        let incomeLabel = String(localized: "收入")
        let expenseLabel = String(localized: "支出")
        let netLabel = String(localized: "结余")
        let incomeArea = "IncomeArea"
        let expenseArea = "ExpenseArea"
        let netArea = "NetArea"

        return Chart {
            ForEach(dataPoints) { dp in
                if showIncome {
                    let val = Double(truncating: dp.income as NSNumber)
                    AreaMark(
                        x: .value("Month", dp.label),
                        yStart: .value("Amount", val),
                        yEnd: .value("Fill", val * (1 - areaFillProgress))
                    )
                    .foregroundStyle(by: .value("Type", incomeArea))
                    .interpolationMethod(.catmullRom)
                    LineMark(
                        x: .value("Month", dp.label),
                        y: .value("Amount", val)
                    )
                    .foregroundStyle(by: .value("Type", incomeLabel))
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                }
                if showExpense {
                    let val = abs(Double(truncating: dp.expense as NSNumber))
                    AreaMark(
                        x: .value("Month", dp.label),
                        yStart: .value("Amount", val),
                        yEnd: .value("Fill", val * (1 - areaFillProgress))
                    )
                    .foregroundStyle(by: .value("Type", expenseArea))
                    .interpolationMethod(.catmullRom)
                    LineMark(
                        x: .value("Month", dp.label),
                        y: .value("Amount", val)
                    )
                    .foregroundStyle(by: .value("Type", expenseLabel))
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                }
                if showNet {
                    let val = Double(truncating: net(for: dp) as NSNumber)
                    AreaMark(
                        x: .value("Month", dp.label),
                        yStart: .value("Amount", val),
                        yEnd: .value("Fill", val * (1 - areaFillProgress))
                    )
                    .foregroundStyle(by: .value("Type", netArea))
                    .interpolationMethod(.catmullRom)
                    LineMark(
                        x: .value("Month", dp.label),
                        y: .value("Amount", val)
                    )
                    .foregroundStyle(by: .value("Type", netLabel))
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 2, dash: [4, 3]))
                }
            }

            // Zero baseline
            RuleMark(y: .value("Zero", 0))
                .foregroundStyle(Color.designOnSurfaceVariant.opacity(0.2))
                .lineStyle(StrokeStyle(lineWidth: 1))

            // Crosshair vertical line
            if let selected = selectedDate, dataPoints.contains(where: { $0.label == selected }) {
                RuleMark(x: .value("Selected", selected))
                    .foregroundStyle(Color.designOnSurfaceVariant.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .annotation(position: .top, alignment: .top) {
                        Text(selected)
                            .font(.designLabelSmall)
                            .foregroundStyle(Color.designOnSurfaceVariant.opacity(0.6))
                    }
            }
        }
        .chartForegroundStyleScale { (type: String) -> LinearGradient in
            switch type {
            case incomeArea:
                LinearGradient(colors: [Color.designPrimaryFixedDim.opacity(0.12), Color.designPrimaryFixedDim.opacity(0.0)], startPoint: .top, endPoint: .bottom)
            case expenseArea:
                LinearGradient(colors: [Color.designAccentRed.opacity(0.12), Color.designAccentRed.opacity(0.0)], startPoint: .top, endPoint: .bottom)
            case netArea:
                LinearGradient(colors: [Color.blue.opacity(0.10), Color.blue.opacity(0.0)], startPoint: .top, endPoint: .bottom)
            case incomeLabel:
                LinearGradient(colors: [Color.designPrimaryFixedDim, Color.designPrimaryFixedDim], startPoint: .top, endPoint: .bottom)
            case expenseLabel:
                LinearGradient(colors: [Color.designAccentRed, Color.designAccentRed], startPoint: .top, endPoint: .bottom)
            case netLabel:
                LinearGradient(colors: [Color.blue, Color.blue], startPoint: .top, endPoint: .bottom)
            default:
                LinearGradient(colors: [.gray, .gray], startPoint: .top, endPoint: .bottom)
            }
        }
        .chartXSelection(value: $selectedDate)
        .chartOverlay { proxy in
            GeometryReader { geometry in
                if let selected = selectedDate,
                   let dp = dataPoints.first(where: { $0.label == selected }),
                   let xPos = proxy.position(forX: selected) {
                    selectedTooltip(dp)
                        .position(x: clampX(xPos, in: geometry.size.width), y: pointerY - 24)
                        .allowsHitTesting(false)
                }
            }
        }
        .onContinuousHover { phase in
            switch phase {
            case .active(let location):
                pointerY = location.y
            case .ended:
                break
            }
        }
        .chartXAxis {
            AxisMarks(values: strideLabels) { _ in
                AxisGridLine()
                AxisTick()
                AxisValueLabel()
            }
        }
        .chartYScale(domain: 0...yAxisMax)
        .chartYAxis {
            AxisMarks { _ in
                AxisGridLine()
                AxisValueLabel(format: Decimal.FormatStyle.Currency(code: currencyCode).precision(.fractionLength(0)))
            }
        }
        .chartLegend(.hidden)
        .frame(minHeight: 180)
    }

    private func clampX(_ x: CGFloat, in width: CGFloat) -> CGFloat {
        max(80, min(x, width - 80))
    }

    @ViewBuilder
    private func selectedTooltip(_ dp: TrendDataPoint) -> some View {
        let n = net(for: dp)
        VStack(alignment: .leading, spacing: 4) {
            Text(dp.label)
                .font(.designLabelSmall)
                .foregroundStyle(Color.designOnSurfaceVariant)
                .padding(.bottom, 2)
            if showIncome {
                HStack(spacing: 4) {
                    Circle().fill(Color.designPrimaryFixedDim).frame(width: 5, height: 5)
                    Text("\(CurrencyFormatter.formatDecimal(amount: dp.income, fractionDigits: 0))")
                        .font(.designMonoDataCompact)
                        .foregroundStyle(Color.designPrimaryFixedDim)
                }
            }
            if showExpense {
                HStack(spacing: 4) {
                    Circle().fill(Color.designAccentRed).frame(width: 5, height: 5)
                    Text("\(CurrencyFormatter.formatDecimal(amount: dp.expense, fractionDigits: 0, showAbs: true))")
                        .font(.designMonoDataCompact)
                        .foregroundStyle(Color.designAccentRed)
                }
            }
            if showNet {
                HStack(spacing: 4) {
                    Circle().fill(n >= 0 ? Color.blue : Color.designAccentRed).frame(width: 5, height: 5)
                    Text("\(n >= 0 ? "+" : "")\(CurrencyFormatter.formatDecimal(amount: n, fractionDigits: 0))")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(n >= 0 ? Color.blue : Color.designAccentRed)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
    }

    // MARK: - Legend Bar

    private var legendBar: some View {
        HStack(spacing: 24) {
            legendDot(color: Color.designPrimaryFixedDim, label: String(localized: "收入"), isOn: showIncome) { showIncome.toggle() }
            legendDot(color: Color.designAccentRed, label: String(localized: "支出"), isOn: showExpense) { showExpense.toggle() }
            legendDot(color: Color.blue, label: String(localized: "结余"), isOn: showNet) { showNet.toggle() }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
    }

    private func legendDot(color: Color, label: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Circle().fill(isOn ? color : color.opacity(0.25)).frame(width: 8, height: 8)
                Text(label)
                    .font(.designBodyCaption)
                    .foregroundStyle(isOn ? Color.designOnSurface : Color.designOnSurfaceVariant.opacity(0.5))
            }
        }
        .buttonStyle(.plain)
    }
}
