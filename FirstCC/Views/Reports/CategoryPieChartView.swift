import SwiftUI
import Charts

struct CategoryPieChartView: View {
    let categories: [CategoryExpenseItem]
    let totalExpense: Decimal
    let centerTitle: String
    let isDrilledDown: Bool
    let onCategoryTap: (UUID) -> Void
    let onCenterTap: () -> Void
    let onSelectTransaction: ((Transaction) -> Void)?
    let transactions: [Transaction]?

    var body: some View {
        VStack(spacing: 12) {
            if let txs = transactions, !txs.isEmpty {
                transactionList(txs)
            } else {
                donutChart
                categoryLegend
            }
        }
    }

    // MARK: - Donut Chart

    private var donutChart: some View {
        Chart(categories) { item in
            SectorMark(
                angle: .value("金额", abs(item.amount)),
                innerRadius: .ratio(0.55),
                angularInset: 1
            )
            .foregroundStyle(Color(hex: item.colorHex) ?? .gray)
        }
        .chartBackground { _ in
            VStack(spacing: 2) {
                if isDrilledDown {
                    Button {
                        onCenterTap()
                    } label: {
                        HStack(spacing: 2) {
                            Image(systemName: "chevron.left")
                                .font(.caption2)
                            Text(centerTitle)
                                .font(.caption2)
                        }
                        .foregroundStyle(.secondary)
                    }
                } else {
                    Text(centerTitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text(CurrencyFormatter.formatShort(amount: totalExpense, currencyCode: ""))
                    .font(.headline.weight(.bold))
            }
        }
        .frame(height: 220)
    }

    // MARK: - Legend

    private var categoryLegend: some View {
        VStack(spacing: 0) {
            ForEach(categories) { item in
                Button {
                    onCategoryTap(item.id)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: item.iconName)
                            .font(.caption)
                            .foregroundStyle(Color(hex: item.colorHex) ?? .gray)
                            .frame(width: 20)

                        Text(item.name)
                            .font(.subheadline)
                            .foregroundStyle(.primary)

                        Spacer()

                        VStack(alignment: .trailing, spacing: 2) {
                            Text(CurrencyFormatter.formatShort(amount: item.amount, currencyCode: ""))
                                .font(.subheadline.weight(.medium))
                            Text(String(format: "%.1f%%", item.percentage * 100))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)

                if item.id != categories.last?.id {
                    Divider().padding(.leading, 28)
                }
            }
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Transaction List

    private func transactionList(_ txs: [Transaction]) -> some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button {
                    onCenterTap()
                } label: {
                    HStack(spacing: 2) {
                        Image(systemName: "chevron.left")
                            .font(.caption.weight(.medium))
                        Text(centerTitle)
                            .font(.subheadline.weight(.medium))
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                Text(CurrencyFormatter.formatShort(amount: totalExpense, currencyCode: ""))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 8)

            Divider()

            ForEach(txs.sorted(by: { $0.date > $1.date })) { tx in
                Button {
                    onSelectTransaction?(tx)
                } label: {
                    TransactionRowView(transaction: tx)
                }
                .buttonStyle(.plain)

                if tx.id != txs.last?.id {
                    Divider().padding(.leading, 16)
                }
            }
        }
    }
}
