import SwiftUI

// MARK: - Transaction Detail List

/// Reusable transaction detail list used by category and dimension drill-down views.
struct TransactionDetailList: View {
    let transactions: [Transaction]
    let centerTitle: String
    let totalExpense: Decimal
    let onBack: () -> Void
    let onSelectTransaction: ((Transaction) -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    onBack()
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
}
