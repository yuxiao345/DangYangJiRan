import SwiftUI

struct TrendChartView: View {
    let dataPoints: [TrendDataPoint]

    @State private var selectedMonthID: UUID?
    @State private var showIncome = true
    @State private var showExpense = true
    @State private var showNet = true

    // MARK: - Totals (single pass)

    private var totals: (income: Decimal, expense: Decimal) {
        dataPoints.reduce(into: (income: Decimal(0), expense: Decimal(0))) { acc, dp in
            acc.income += dp.income
            acc.expense += dp.expense
        }
    }

    // MARK: - Summary (selected month or full period)

    private var activePoint: TrendDataPoint? {
        guard let id = selectedMonthID else { return nil }
        return dataPoints.first { $0.id == id }
    }

    // MARK: - Bar Scaling

    /// Dynamic ceiling: sum of VISIBLE metrics for the heaviest month.
    /// Used for both bar widths AND axis labels — toggling legend items updates the axis.
    private var barCeil: Double {
        var maxSum = 0.0
        for dp in dataPoints {
            var s = 0.0
            if showIncome { s += Double(truncating: dp.income as NSNumber) }
            if showExpense { s += Double(truncating: dp.expense as NSNumber) }
            if showNet {
                let n = Double(truncating: dp.income as NSNumber) - Double(truncating: dp.expense as NSNumber)
                if n > 0 { s += n }
            }
            maxSum = max(maxSum, s)
        }
        return maxSum > 0 ? maxSum : 100
    }

    private var axisCeiling: Double {
        niceCeiling(barCeil)
    }

    // MARK: - Display Order

    private var displayPoints: [TrendDataPoint] {
        Array(dataPoints.reversed())
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

    private var yearSet: Set<Int> {
        Set(dataPoints.compactMap(\.year))
    }

    // MARK: - Body

    var body: some View {
        if dataPoints.isEmpty {
            emptyState
        } else {
            let ceil = axisCeiling
            let bCeil = barCeil
            let t = totals
            let yr = yearRange
            ScrollView {
                VStack(spacing: 16) {
                    summaryCards(totals: t)
                        .padding(.horizontal, 16)
                    chartCard(ceil: ceil, barCeil: bCeil, yearRange: yr)
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

    private func summaryCards(totals: (income: Decimal, expense: Decimal)) -> some View {
        let inc = activePoint?.income ?? totals.income
        let exp = activePoint?.expense ?? totals.expense
        let bal = inc - exp
        return HStack(spacing: 8) {
            summaryCard(
                label: String(localized: "收入"),
                amount: inc,
                color: Color.designAccentGreen
            )
            summaryCard(
                label: String(localized: "支出"),
                amount: exp,
                color: Color.designAccentRed
            )
            summaryCard(
                label: String(localized: "结余"),
                amount: bal,
                color: bal >= 0 ? Color.designAccentGreen : Color.designAccentRed
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

    private func chartCard(ceil: Double, barCeil: Double, yearRange: String) -> some View {
        let axisVals: [Double] = [0, ceil / 2, ceil]
        return VStack(spacing: 0) {
            chartHeader(yearRange: yearRange)
            chartRows(ceil: barCeil)
            chartAxis(values: axisVals)
        }
        .padding(16)
        .glassCard(cornerRadius: 24)
    }

    // MARK: - Chart Header

    private func chartHeader(yearRange: String) -> some View {
        HStack {
            HStack(spacing: 12) {
                legendToggle(
                    activeColor: Color.designAccentGreen,
                    label: String(localized: "收入"),
                    isOn: $showIncome
                )
                legendToggle(
                    activeColor: Color.designAccentRed,
                    label: String(localized: "支出"),
                    isOn: $showExpense
                )
                legendToggle(
                    activeColor: Color.blue,
                    label: String(localized: "结余"),
                    isOn: $showNet
                )
            }
            Spacer()
            if !yearRange.isEmpty {
                Text(yearRange)
                    .font(.designMonoDataCompact)
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

    private func legendToggle(activeColor: Color, label: String, isOn: Binding<Bool>) -> some View {
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
                    .font(.designMonoDataCompact)
                    .foregroundStyle(isOn.wrappedValue ? Color.designOnSurfaceVariant : Color.designOnSurfaceVariant.opacity(0.4))
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Chart Rows

    private func chartRows(ceil: Double) -> some View {
        let points = displayPoints
        return ForEach(Array(points.enumerated()), id: \.element.id) { i, point in
            if i == 0, let year = point.year {
                yearSeparator(label: "\(year)")
            } else if i > 0,
                      let prevYear = points[i - 1].year,
                      let thisYear = point.year,
                      prevYear != thisYear {
                yearSeparator(label: "\(thisYear)")
            }
            monthRow(point: point, ceil: ceil, isSelected: selectedMonthID == point.id)
                .accessibilityAddTraits(selectedMonthID == point.id ? [.isButton, .isSelected] : .isButton)
                .accessibilityAction {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedMonthID = selectedMonthID == point.id ? nil : point.id
                    }
                }
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedMonthID = selectedMonthID == point.id ? nil : point.id
                    }
                }
        }
    }

    private func yearSeparator(label: String) -> some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(Color.designOutlineVariant.opacity(0.2))
                .frame(height: 1)
            Text(label)
                .font(.designLabelSmall)
                .foregroundStyle(Color.designOnSurfaceVariant.opacity(0.4))
                .padding(.horizontal, 12)
            Rectangle()
                .fill(Color.designOutlineVariant.opacity(0.2))
                .frame(height: 1)
        }
        .padding(.vertical, 10)
    }

    private func monthRow(point: TrendDataPoint, ceil: Double, isSelected: Bool) -> some View {
        let incomeVal = Double(truncating: point.income as NSNumber)
        let expenseVal = Double(truncating: point.expense as NSNumber)
        let netVal = incomeVal - expenseVal

        return HStack(spacing: 10) {
            // Month label
            HStack(spacing: 4) {
                Circle()
                    .fill(isSelected ? Color.designAccentGreen : Color.designAccentGreen.opacity(0.3))
                    .frame(width: 5, height: 5)
                Text(point.monthLabel)
                    .font(.designMonoDataCompact)
                    .foregroundStyle(isSelected ? Color.designOnSurface : Color.designOnSurfaceVariant)
            }
            .frame(width: 42, alignment: .leading)

            // Three bar segments, all scaled to the same dynamic ceil (sum of visible metrics for heaviest month)
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
                    if showNet, netVal > 0 {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.blue.opacity(0.6))
                            .frame(width: max(4, totalW * (netVal / ceil)))
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
                .font(.designMonoDataCompact)
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

    // MARK: - Bottom Axis

    private func chartAxis(values: [Double]) -> some View {
        HStack {
            Spacer()
                .frame(width: 42 + 10)
            ForEach(values.indices, id: \.self) { i in
                if i > 0 { Spacer() }
                Text("¥\(CurrencyFormatter.formatCompactNumber(values[i]))")
                    .font(.designLabelSmall)
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
        let nice: Double = mantissa <= 1 ? 1 : mantissa <= 1.5 ? 1.5 : mantissa <= 2 ? 2 : mantissa <= 2.5 ? 2.5 : mantissa <= 3 ? 3 : mantissa <= 4 ? 4 : mantissa <= 5 ? 5 : mantissa <= 7.5 ? 7.5 : 10
        return nice * base
    }

    private func formatNetAmount(_ value: Double) -> String {
        if value == 0 { return "0" }
        let sign = value > 0 ? "+" : "-"
        return "\(sign)\(CurrencyFormatter.formatCompactNumber(abs(value)))"
    }

    private func netAmountColor(_ value: Double) -> Color {
        if value > 0 { return Color.designAccentGreen }
        if value < 0 { return Color.designAccentRed }
        return Color.designOnSurfaceVariant
    }
}
