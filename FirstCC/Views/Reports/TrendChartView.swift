import SwiftUI

struct TrendChartView: View {
    let dataPoints: [TrendDataPoint]
    let period: ReportPeriod

    @State private var selectedMonthID: UUID?
    @State private var showIncome = true
    @State private var showExpense = true
    @State private var showNet = true

    // MARK: - Summary (selected month or full period)

    private var activePoint: TrendDataPoint? {
        guard let id = selectedMonthID else { return nil }
        return dataPoints.first { $0.id == id }
    }

    private var summaryIncome: Decimal {
        activePoint?.income ?? totalIncome
    }

    private var summaryExpense: Decimal {
        activePoint?.expense ?? totalExpense
    }

    private var summaryBalance: Decimal {
        summaryIncome - summaryExpense
    }

    private var totalIncome: Decimal {
        dataPoints.map(\.income).reduce(0, +)
    }

    private var totalExpense: Decimal {
        dataPoints.map(\.expense).reduce(0, +)
    }

    // MARK: - Bar Scaling

    /// Max across all three metrics so each bar segment scales to the same ceiling
    private var globalMax: Double {
        let maxInc = dataPoints.map { Double(truncating: $0.income as NSNumber) }.max() ?? 1
        let maxExp = dataPoints.map { Double(truncating: $0.expense as NSNumber) }.max() ?? 1
        let maxNet = dataPoints.map { abs(Double(truncating: ($0.income - $0.expense) as NSNumber)) }.max() ?? 1
        return max(maxInc, maxExp, maxNet)
    }

    private var axisCeiling: Double {
        niceCeiling(globalMax)
    }

    private var axisValues: [Double] {
        [0, axisCeiling / 2, axisCeiling]
    }

    // MARK: - Display Order

    /// Data points reversed: newest at top, oldest at bottom
    private var displayPoints: [TrendDataPoint] {
        dataPoints.reversed()
    }

    // MARK: - Year Range

    private var yearRange: String {
        let years = yearSet
        if years.count >= 2 {
            let sorted = years.sorted()
            return "\(sorted.first!) – \(sorted.last!)"
        }
        if let y = years.first { return "\(y)" }
        return ""
    }

    /// All distinct years detected from labels (works for all periods)
    private var yearSet: Set<Int> {
        var years = Set<Int>()
        for dp in dataPoints {
            if let y = extractYear(from: dp) { years.insert(y) }
        }
        // Also try yearLabel for last3Years
        for dp in dataPoints {
            if let yl = dp.yearLabel, let y = Int(yl) { years.insert(2000 + y) }
        }
        return years
    }

    /// Extract 4-digit year from label (e.g. "24年6月" → 2024, "6月" → nil)
    private func extractYear(from dp: TrendDataPoint) -> Int? {
        guard let nianIdx = dp.label.firstIndex(of: "年") else { return nil }
        let prefix = String(dp.label[..<nianIdx])
        guard let yy = Int(prefix) else { return nil }
        return yy >= 1000 ? yy : 2000 + yy
    }

    /// Extract year string from label for separator display (e.g. "24年6月" → "2024")
    private func yearString(from dp: TrendDataPoint) -> String? {
        guard let year = extractYear(from: dp) else { return nil }
        return "\(year)"
    }

    // MARK: - Body

    var body: some View {
        if dataPoints.isEmpty {
            emptyState
        } else {
            ScrollView {
                VStack(spacing: 16) {
                    summaryCards
                        .padding(.horizontal, 16)
                    chartCard
                        .padding(.horizontal, 16)
                }
                .padding(.vertical, 8)
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.bar")
                .font(.largeTitle)
                .foregroundStyle(Color.designOnSurfaceVariant)
            Text("暂无收支数据")
                .foregroundStyle(Color.designOnSurfaceVariant)
        }
    }

    // MARK: - Summary Cards

    private var summaryCards: some View {
        HStack(spacing: 8) {
            summaryCard(
                label: String(localized: "收入"),
                amount: summaryIncome,
                color: Color.designAccentGreen
            )
            summaryCard(
                label: String(localized: "支出"),
                amount: summaryExpense,
                color: Color.designAccentRed
            )
            summaryCard(
                label: String(localized: "结余"),
                amount: summaryBalance,
                color: summaryBalance >= 0 ? Color.designAccentGreen : Color.designAccentRed
            )
        }
        .animation(.easeInOut(duration: 0.2), value: selectedMonthID)
    }

    private func summaryCard(label: String, amount: Decimal, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.designLabel)
                .foregroundStyle(color.opacity(0.8))
            CurrencyText(
                amount: amount,
                currencyCode: "",
                size: 16,
                foregroundColor: color,
                fractionDigits: 0
            )
            .fontWeight(.bold)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .glassCard(cornerRadius: 16)
    }

    // MARK: - Chart Card

    private var chartCard: some View {
        VStack(spacing: 0) {
            chartHeader
            chartRows
            chartAxis
        }
        .padding(16)
        .glassCard(cornerRadius: 24)
    }

    // MARK: - Chart Header

    private var chartHeader: some View {
        HStack {
            HStack(spacing: 12) {
                legendToggle(
                    color: Color.designAccentGreen,
                    activeColor: Color.designAccentGreen,
                    label: String(localized: "收入"),
                    isOn: $showIncome
                )
                legendToggle(
                    color: Color.designAccentRed,
                    activeColor: Color.designAccentRed,
                    label: String(localized: "支出"),
                    isOn: $showExpense
                )
                legendToggle(
                    color: Color.blue,
                    activeColor: Color.blue,
                    label: String(localized: "结余"),
                    isOn: $showNet
                )
            }
            Spacer()
            if !yearRange.isEmpty {
                Text(yearRange)
                    .font(.custom("JetBrainsMono-Medium", fixedSize: 11))
                    .foregroundStyle(Color.designOnSurfaceVariant)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color.designSurfaceContainer.opacity(0.5))
                    )
                    .overlay(
                        Capsule()
                            .stroke(Color.designOutlineVariant.opacity(0.2), lineWidth: 1)
                    )
            }
        }
        .padding(.bottom, 16)
    }

    private func legendToggle(color: Color, activeColor: Color, label: String, isOn: Binding<Bool>) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isOn.wrappedValue.toggle()
            }
        } label: {
            HStack(spacing: 4) {
                Circle()
                    .fill(isOn.wrappedValue ? activeColor : Color.gray.opacity(0.35))
                    .frame(width: 8, height: 8)
                Text(label)
                    .font(.custom("JetBrainsMono-Medium", fixedSize: 11))
                    .foregroundStyle(isOn.wrappedValue ? Color.designOnSurfaceVariant : Color.designOnSurfaceVariant.opacity(0.4))
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Chart Rows

    private var chartRows: some View {
        let points = displayPoints
        return ForEach(Array(points.enumerated()), id: \.element.id) { i, point in
            if i == 0, let year = yearString(from: point) {
                yearSeparator(label: year)
            } else if i > 0,
                      let prevYear = yearString(from: points[i - 1]),
                      let thisYear = yearString(from: point),
                      prevYear != thisYear {
                yearSeparator(label: thisYear)
            }
            monthRowButton(point: point)
        }
    }

    private func yearSeparator(label: String) -> some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(Color.designOutlineVariant.opacity(0.2))
                .frame(height: 1)
            Text(label)
                .font(.custom("JetBrainsMono-Medium", fixedSize: 10))
                .foregroundStyle(Color.designOnSurfaceVariant.opacity(0.4))
                .padding(.horizontal, 12)
            Rectangle()
                .fill(Color.designOutlineVariant.opacity(0.2))
                .frame(height: 1)
        }
        .padding(.vertical, 10)
    }

    private func monthRowButton(point: TrendDataPoint) -> some View {
        let isSelected = selectedMonthID == point.id

        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedMonthID = isSelected ? nil : point.id
            }
        } label: {
            monthRow(point: point, isSelected: isSelected)
        }
        .buttonStyle(.plain)
    }

    private func monthRow(point: TrendDataPoint, isSelected: Bool) -> some View {
        let incomeVal = Double(truncating: point.income as NSNumber)
        let expenseVal = Double(truncating: point.expense as NSNumber)
        let netVal = incomeVal - expenseVal
        let ceil = axisCeiling

        return HStack(spacing: 10) {
            // Month label
            HStack(spacing: 4) {
                Circle()
                    .fill(isSelected ? Color.designAccentGreen : Color.designAccentGreen.opacity(0.3))
                    .frame(width: 5, height: 5)
                Text(monthDisplayLabel(for: point))
                    .font(.custom("JetBrainsMono-Medium", fixedSize: 11))
                    .foregroundStyle(isSelected ? Color.designOnSurface : Color.designOnSurfaceVariant)
            }
            .frame(width: 42, alignment: .leading)

            // Three independent bar segments
            GeometryReader { geo in
                let totalW = geo.size.width
                HStack(spacing: 3) {
                    if showIncome, incomeVal > 0 {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.designAccentGreen)
                            .frame(width: max(4, totalW * (incomeVal / ceil)))
                    }
                    if showExpense, expenseVal > 0 {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.designAccentRed.opacity(0.7))
                            .frame(width: max(4, totalW * (expenseVal / ceil)))
                    }
                    if showNet, netVal != 0 {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.blue.opacity(0.6))
                            .frame(width: max(4, totalW * (abs(netVal) / ceil)))
                    }
                    Spacer(minLength: 0)
                }
                .frame(height: 16)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(isSelected
                            ? Color.designSurfaceContainer.opacity(0.6)
                            : Color.designSurfaceContainer.opacity(0.3))
                )
            }
            .frame(height: 16)

            // Net amount
            Text(formatNetAmount(netVal))
                .font(.custom("JetBrainsMono-Medium", fixedSize: 11))
                .foregroundStyle(netAmountColor(netVal))
                .frame(width: 48, alignment: .trailing)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.designPrimaryContainer.opacity(0.08) : Color.clear)
        )
    }

    private func monthDisplayLabel(for point: TrendDataPoint) -> String {
        var raw = point.label
        // For last3Years: strip year prefix via yearLabel (e.g. "24年" from "24年6月")
        if let yl = point.yearLabel, raw.hasPrefix(yl) {
            raw = String(raw.dropFirst(yl.count))
        }
        // Strip remaining year prefix: "26年6月" → "6月"
        if let nianIdx = raw.firstIndex(of: "年") {
            raw = String(raw[raw.index(after: nianIdx)...])
        }
        return raw
    }

    // MARK: - Bottom Axis

    private var chartAxis: some View {
        HStack {
            Spacer()
                .frame(width: 42 + 10)
            ForEach(axisValues.indices, id: \.self) { i in
                if i > 0 { Spacer() }
                Text("¥\(formatAxis(axisValues[i]))")
                    .font(.custom("JetBrainsMono-Medium", fixedSize: 10))
                    .foregroundStyle(Color.designOnSurfaceVariant.opacity(0.4))
            }
            Spacer()
                .frame(width: 48 + 10)
        }
        .padding(.top, 12)
        .padding(.horizontal, 2)
    }

    // MARK: - Helpers

    private func niceCeiling(_ value: Double) -> Double {
        guard value > 0 else { return 100 }
        let exp = floor(log10(value))
        let base = pow(10, exp)
        let mantissa = value / base
        let nice: Double = mantissa <= 1 ? 1 : mantissa <= 2 ? 2 : mantissa <= 5 ? 5 : 10
        return nice * base * 1.2
    }

    private func formatAxis(_ value: Double) -> String {
        let isChinese = Bundle.main.preferredLocalizations.first?.hasPrefix("zh") ?? true
        if value >= 10000 && isChinese {
            let wan = value / 10000
            return wan.formatted(.number.precision(.fractionLength(0...1))) + String(localized: "万")
        }
        if value >= 1000 {
            let k = value / 1000
            return k.formatted(.number.precision(.fractionLength(0...1))) + "k"
        }
        return value.formatted(.number.grouping(.automatic).precision(.fractionLength(0)))
    }

    private func formatNetAmount(_ value: Double) -> String {
        if value == 0 { return "0" }
        let sign = value > 0 ? "+" : ""
        let absVal = abs(value)
        if absVal >= 10000 {
            let wan = absVal / 10000
            return "\(sign)\(String(format: "%.1f", wan))万"
        }
        if absVal >= 1000 {
            let k = absVal / 1000
            return "\(sign)\(String(format: "%.1f", k))k"
        }
        return "\(sign)\(Int(absVal))"
    }

    private func netAmountColor(_ value: Double) -> Color {
        if value > 0 { return Color.designAccentGreen }
        if value < 0 { return Color.designAccentRed }
        return Color.designOnSurfaceVariant
    }
}
