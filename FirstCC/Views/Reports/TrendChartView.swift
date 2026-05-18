import SwiftUI
import Charts

struct TrendChartView: View {
    let dataPoints: [TrendDataPoint]

    private var totalIncome: Decimal {
        dataPoints.map(\.income).reduce(0, +)
    }

    private var totalExpense: Decimal {
        dataPoints.map(\.expense).reduce(0, +)
    }

    var body: some View {
        if dataPoints.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "chart.bar")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text("暂无收支数据")
                    .foregroundStyle(.secondary)
            }
        } else {
            VStack(spacing: 12) {
                // Summary header
                HStack(spacing: 24) {
                    VStack(spacing: 4) {
                        HStack(spacing: 4) {
                            Circle().fill(.green).frame(width: 8, height: 8)
                            Text("收入")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text(CurrencyFormatter.formatShort(amount: totalIncome, currencyCode: ""))
                            .font(.title3.weight(.bold))
                            .foregroundStyle(.green)
                    }
                    VStack(spacing: 4) {
                        HStack(spacing: 4) {
                            Circle().fill(.red).frame(width: 8, height: 8)
                            Text("支出")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text(CurrencyFormatter.formatShort(amount: totalExpense, currencyCode: ""))
                            .font(.title3.weight(.bold))
                            .foregroundStyle(.red)
                    }
                    VStack(spacing: 4) {
                        Text("结余")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(CurrencyFormatter.formatShort(amount: totalIncome - totalExpense, currencyCode: ""))
                            .font(.title3.weight(.bold))
                            .foregroundStyle((totalIncome - totalExpense) >= 0 ? .green : .red)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)

                // Chart
                Chart {
                    ForEach(dataPoints) { point in
                        BarMark(
                            x: .value("日期", point.label),
                            y: .value("收入", point.income),
                            width: .automatic
                        )
                        .foregroundStyle(.green)
                        .position(by: .value("类型", "收入"))
                    }
                    ForEach(dataPoints) { point in
                        BarMark(
                            x: .value("日期", point.label),
                            y: .value("支出", point.expense),
                            width: .automatic
                        )
                        .foregroundStyle(.red)
                        .position(by: .value("类型", "支出"))
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let v = value.as(Decimal.self) {
                                Text(CurrencyFormatter.formatShort(amount: v, currencyCode: ""))
                                    .font(.caption2)
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic) { _ in
                        AxisValueLabel()
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
