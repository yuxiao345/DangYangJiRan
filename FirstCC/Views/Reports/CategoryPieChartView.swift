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

    @State private var selectedAngle: Double?

    var body: some View {
        VStack(spacing: 12) {
            if let txs = transactions, !txs.isEmpty {
                transactionList(txs)
            } else {
                donutCard
                categoryList
            }
        }
    }

    // MARK: - Donut Card

    private var donutCard: some View {
        VStack(spacing: 0) {
            donutChart
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .glassCard(cornerRadius: 24)
        .padding(.horizontal, 12)
    }

    private var donutChart: some View {
        Chart(categories) { item in
            SectorMark(
                angle: .value("金额", abs(Double(truncating: item.amount as NSNumber))),
                innerRadius: .ratio(0.55),
                angularInset: 1
            )
            .foregroundStyle(Color(hex: item.colorHex) ?? .gray)
        }
        .chartAngleSelection(value: $selectedAngle)
        .onChange(of: selectedAngle) { _, angle in
            guard let angle else { return }
            var cumulative: Double = 0
            for item in categories {
                cumulative += Double(truncating: item.amount as NSNumber)
                if angle <= cumulative {
                    onCategoryTap(item.id)
                    selectedAngle = nil
                    return
                }
            }
        }
        .chartBackground { _ in
            VStack(spacing: 2) {
                if isDrilledDown {
                    Button {
                        onCenterTap()
                    } label: {
                        HStack(spacing: 2) {
                            Image(systemName: "chevron.left")
                                .font(.designBodySmall)
                            Text(centerTitle)
                                .font(.designBodySmall)
                        }
                        .foregroundStyle(Color.designAccentGreen)
                    }
                } else {
                    Text(centerTitle)
                        .font(.designBodySmall)
                        .foregroundStyle(Color.designOnSurfaceVariant)
                }
                CurrencyText(amount: totalExpense, currencyCode: "", size: 17, foregroundColor: Color.designOnSurface)
                    .fontWeight(.bold)
            }
        }
        .frame(height: 220)
    }

    // MARK: - Category List

    private var categoryList: some View {
        VStack(spacing: 8) {
            ForEach(categories) { item in
                Button {
                    onCategoryTap(item.id)
                } label: {
                    VStack(spacing: 8) {
                        HStack(spacing: 8) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color(hex: item.colorHex) ?? .gray)
                                .frame(width: 12, height: 12)

                            Text(item.name)
                                .font(.designBodyMedium)
                                .foregroundStyle(Color.designOnSurface)

                            Spacer()

                            VStack(alignment: .trailing, spacing: 2) {
                                CurrencyText(amount: item.amount, currencyCode: "", size: 15, foregroundColor: Color.designOnSurface)
                                    .fontWeight(.medium)
                                Text(String(format: "%.1f%%", item.percentage * 100))
                                    .font(.designMonoDataSmall)
                                    .foregroundStyle(Color.designOnSurfaceVariant)
                            }

                            Image(systemName: "chevron.right")
                                .font(.designBodySmall)
                                .foregroundStyle(Color.designOnSurfaceVariant.opacity(0.5))
                        }

                        PixelProgressBar(progress: item.percentage, tint: Color(hex: item.colorHex) ?? .gray, totalBlocks: 16)
                    }
                    .padding(12)
                    .glassCard(cornerRadius: 16)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
    }

    // MARK: - Transaction List

    private func transactionList(_ txs: [Transaction]) -> some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    onCenterTap()
                } label: {
                    HStack(spacing: 2) {
                        Image(systemName: "chevron.left")
                            .font(.designBodySmall.weight(.medium))
                        Text(centerTitle)
                            .font(.designBodyMedium.weight(.medium))
                    }
                    .foregroundStyle(Color.designAccentGreen)
                }
                .buttonStyle(.plain)

                Spacer()

                CurrencyText(amount: totalExpense, currencyCode: "", size: 15, foregroundColor: Color.designOnSurface)
                    .fontWeight(.bold)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)

            Divider()

            ForEach(txs.sorted(by: { $0.date > $1.date }), id: \.id) { tx in
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
