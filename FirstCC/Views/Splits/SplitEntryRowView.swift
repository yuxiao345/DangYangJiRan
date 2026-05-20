import SwiftUI
import SwiftData

struct SplitEntryRowView: View {
    let entry: SplitEntry
    let onToggle: () -> Void

    var body: some View {
        HStack {
            Image(systemName: entry.member?.avatar ?? "person.circle")
                .foregroundStyle(Color.designPrimaryContainer)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.member?.name ?? "未知成员")
                    .font(.designBodyMedium)
                if let paidDate = entry.paidDate {
                    Text("已付于 \(paidDate.formatted(date: .abbreviated, time: .omitted))")
                        .font(.designBodySmall)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(entry.amount, format: .currency(code: entry.splitGroup?.currencyCode ?? "CNY"))
                .foregroundStyle(entry.isPaid ? .secondary : .primary)
            Button {
                onToggle()
            } label: {
                Image(systemName: entry.isPaid ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(entry.isPaid ? .green : .secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }
}
