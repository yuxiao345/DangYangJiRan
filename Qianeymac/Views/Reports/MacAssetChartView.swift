import SwiftUI
import Charts

struct MacAssetChartView: View {
    let dataPoints: [AssetDataPoint]

    @Environment(AppContainer.self) private var appContainer

    private var currencyCode: String { appContainer.currentCurrencyCode }

    @State private var showAssets = false
    @State private var showLiabilities = false
    @State private var showNet = true
    @State private var selectedLabel: String?
    @State private var pointerY: CGFloat = 80
    @State private var lineProgress: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            if dataPoints.isEmpty {
                emptyView
            } else {
                summaryCards
                assetChart
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
        .onAppear { startDrawAnimation() }
        .onChange(of: dataPoints.map(\.id)) { _, _ in startDrawAnimation() }
    }

    // MARK: - Empty

    private var emptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.bar.fill")
                .font(.system(size: 40))
                .foregroundStyle(Color.designOnSurfaceVariant.opacity(0.4))
            Text("暂无资产数据")
                .font(.designBodyMedium)
                .foregroundStyle(Color.designOnSurfaceVariant)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Computed

    private var latest: AssetDataPoint? { dataPoints.last }

    private var totalAssets: Decimal { latest?.totalAssets ?? 0 }
    private var totalLiabilities: Decimal { latest?.totalLiabilities ?? 0 }
    private var netWorth: Decimal { latest?.netWorth ?? 0 }

    private var yAxisMin: Double {
        var minVal: Double = 0
        for dp in dataPoints {
            if showNet { minVal = min(minVal, Double(truncating: dp.netWorth as NSNumber)) }
        }
        return minVal * 1.15
    }

    private var yAxisMax: Double {
        var maxVal: Double = 100
        for dp in dataPoints {
            if showAssets { maxVal = max(maxVal, Double(truncating: dp.totalAssets as NSNumber)) }
            if showLiabilities { maxVal = max(maxVal, Double(truncating: dp.totalLiabilities as NSNumber)) }
            if showNet { maxVal = max(maxVal, Double(truncating: dp.netWorth as NSNumber)) }
        }
        return maxVal * 1.15
    }

    private var strideLabels: [String] {
        let count = dataPoints.count
        let step = count > 24 ? 4 : (count > 12 ? 3 : (count > 6 ? 2 : 1))
        return stride(from: 0, to: count, by: step).map { dataPoints[$0].label }
    }

    private func startDrawAnimation() {
        lineProgress = 0
        withAnimation(.easeOut(duration: 1.2)) { lineProgress = 1 }
    }

    // MARK: - Summary Cards

    private var summaryCards: some View {
        HStack(spacing: 16) {
            summaryCell(
                label: String(localized: "总资产"), amount: totalAssets,
                color: Color.designPrimaryFixedDim, isOn: showAssets
            ) { showAssets.toggle() }

            summaryCell(
                label: String(localized: "总负债"), amount: totalLiabilities,
                color: Color.designAccentRed, isOn: showLiabilities
            ) { showLiabilities.toggle() }

            summaryCell(
                label: String(localized: "净资产"), amount: netWorth,
                color: .blue, isOn: showNet
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

    // MARK: - Chart

    private var assetChart: some View {
        let assetLabel = String(localized: "总资产")
        let liabilityLabel = String(localized: "总负债")
        let netLabel = String(localized: "净资产")

        return Chart {
            ForEach(dataPoints) { dp in
                // AreaMarks: explicit yStart=0 prevents Swift Charts auto-stacking
                if showNet {
                    let val = Double(truncating: dp.netWorth as NSNumber)
                    AreaMark(
                        x: .value("Month", dp.label),
                        yStart: .value("Amount", 0),
                        yEnd: .value("Amount", val)
                    )
                    .foregroundStyle(by: .value("Type", "NetArea"))
                    .interpolationMethod(.catmullRom)
                    .opacity(0.10)
                }
                if showLiabilities {
                    let val = Double(truncating: dp.totalLiabilities as NSNumber)
                    AreaMark(
                        x: .value("Month", dp.label),
                        yStart: .value("Zero", 0),
                        yEnd: .value("Amount", val)
                    )
                    .foregroundStyle(by: .value("Type", "LiabArea"))
                    .interpolationMethod(.catmullRom)
                    .opacity(0.12)
                }
                if showAssets {
                    let val = Double(truncating: dp.totalAssets as NSNumber)
                    AreaMark(
                        x: .value("Month", dp.label),
                        yStart: .value("Zero", 0),
                        yEnd: .value("Amount", val)
                    )
                    .foregroundStyle(by: .value("Type", "AssetsArea"))
                    .interpolationMethod(.catmullRom)
                    .opacity(0.12)
                }

                // Lines drawn on TOP of areas
                if showNet {
                    let val = Double(truncating: dp.netWorth as NSNumber)
                    LineMark(x: .value("Month", dp.label), y: .value("Amount", val))
                        .foregroundStyle(by: .value("Type", netLabel))
                        .interpolationMethod(.catmullRom)
                        .lineStyle(StrokeStyle(lineWidth: 2, dash: [4, 3]))
                }
                if showLiabilities {
                    let val = Double(truncating: dp.totalLiabilities as NSNumber)
                    LineMark(x: .value("Month", dp.label), y: .value("Amount", val))
                        .foregroundStyle(by: .value("Type", liabilityLabel))
                        .interpolationMethod(.catmullRom)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                }
                if showAssets {
                    let val = Double(truncating: dp.totalAssets as NSNumber)
                    LineMark(x: .value("Month", dp.label), y: .value("Amount", val))
                        .foregroundStyle(by: .value("Type", assetLabel))
                        .interpolationMethod(.catmullRom)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                }
            }

            RuleMark(y: .value("Zero", 0))
                .foregroundStyle(Color.designOnSurfaceVariant.opacity(0.2))
                .lineStyle(StrokeStyle(lineWidth: 1))

            // Crosshair vertical line
            if let selected = selectedLabel, dataPoints.contains(where: { $0.label == selected }) {
                RuleMark(x: .value("Selected", selected))
                    .foregroundStyle(Color.designOnSurfaceVariant.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 1))
            }
        }
        .chartForegroundStyleScale { (type: String) -> Color in
            switch type {
            case assetLabel, "AssetsArea": Color.designPrimaryFixedDim
            case liabilityLabel, "LiabArea": Color.designAccentRed
            case netLabel, "NetArea": Color.blue
            default: .gray
            }
        }
        .chartXSelection(value: $selectedLabel)
        .chartOverlay { proxy in
            GeometryReader { geometry in
                if let selected = selectedLabel,
                   let dp = dataPoints.first(where: { $0.label == selected }),
                   let xPos = proxy.position(forX: selected) {
                    assetTooltip(dp)
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
        .chartYScale(domain: yAxisMin...yAxisMax)
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
    private func assetTooltip(_ dp: AssetDataPoint) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(dp.label)
                .font(.designLabelSmall)
                .foregroundStyle(Color.designOnSurfaceVariant)
                .padding(.bottom, 2)
            if showAssets {
                HStack(spacing: 4) {
                    Circle().fill(Color.designPrimaryFixedDim).frame(width: 5, height: 5)
                    Text("\(CurrencyFormatter.formatDecimal(amount: dp.totalAssets, fractionDigits: 0))")
                        .font(.designMonoDataCompact)
                        .foregroundStyle(Color.designPrimaryFixedDim)
                }
            }
            if showLiabilities {
                HStack(spacing: 4) {
                    Circle().fill(Color.designAccentRed).frame(width: 5, height: 5)
                    Text("\(CurrencyFormatter.formatDecimal(amount: dp.totalLiabilities, fractionDigits: 0))")
                        .font(.designMonoDataCompact)
                        .foregroundStyle(Color.designAccentRed)
                }
            }
            if showNet {
                let nw = dp.netWorth
                HStack(spacing: 4) {
                    Circle().fill(nw >= 0 ? Color.blue : Color.designAccentRed).frame(width: 5, height: 5)
                    Text("\(nw >= 0 ? "+" : "")\(CurrencyFormatter.formatDecimal(amount: nw, fractionDigits: 0))")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(nw >= 0 ? Color.blue : Color.designAccentRed)
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
            legendDot(color: Color.designPrimaryFixedDim, label: String(localized: "总资产"), isOn: showAssets) { showAssets.toggle() }
            legendDot(color: Color.designAccentRed, label: String(localized: "总负债"), isOn: showLiabilities) { showLiabilities.toggle() }
            legendDot(color: .blue, label: String(localized: "净资产"), isOn: showNet) { showNet.toggle() }
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
