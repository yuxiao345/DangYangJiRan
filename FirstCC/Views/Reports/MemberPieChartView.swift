import SwiftUI
import Charts

/// L1: 成员支出份额 — 环形图 + 排名列表
struct MemberPieChartView: View {
    let members: [MemberExpenseItem]
    let onMemberTap: (UUID) -> Void

    @State private var animationProgress: Double = 0
    @State private var selectedAngle: Double?

    private let memberColors: [Color] = [
        Color(hex: "#FF6B6B") ?? .red,
        Color(hex: "#4ECDC4") ?? .teal,
        Color(hex: "#FFD93D") ?? .yellow,
        Color(hex: "#6C5CE7") ?? .purple,
        Color(hex: "#A8E6CF") ?? .mint,
        Color(hex: "#74B9FF") ?? .blue,
        Color(hex: "#FF8A80") ?? .pink,
        Color(hex: "#B388FF") ?? .indigo,
    ]

    var body: some View {
        VStack(spacing: 12) {
            donutCard
            memberList
        }
        .onAppear {
            withAnimation(.spring(response: 0.8, dampingFraction: 0.6)) {
                animationProgress = 1.0
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
        Chart {
            ForEach(Array(members.enumerated()), id: \.element.id) { index, member in
                SectorMark(
                    angle: .value("amount", abs(Double(truncating: member.amount as NSNumber)) * animationProgress),
                    innerRadius: .ratio(0.5),
                    angularInset: 2.5
                )
                .foregroundStyle(memberColor(for: index))
            }
        }
        .chartAngleSelection(value: $selectedAngle)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .frame(height: 240)
        .shadow(color: .black.opacity(0.12), radius: 20, y: 8)
        .chartOverlay { proxy in
            GeometryReader { geometry in
                let frame = geometry[proxy.plotAreaFrame]
                centerLabel
                    .position(x: frame.midX, y: frame.midY)
            }
        }
        .simultaneousGesture(
            TapGesture().onEnded {
                guard animationProgress >= 1.0, let angle = selectedAngle else { return }
                let tappedIndex = memberIndex(for: angle)
                guard tappedIndex >= 0, tappedIndex < members.count else { return }
                onMemberTap(members[tappedIndex].id)
            }
        )
    }

    // MARK: - Center Label

    private var centerLabel: some View {
        VStack(spacing: 2) {
            Text(String(localized: "成员占比"))
                .font(.designBodySmall)
                .foregroundStyle(Color.designOnSurfaceVariant)
            CurrencyText(
                amount: members.map(\.amount).reduce(0, +),
                currencyCode: "",
                size: 18,
                foregroundColor: Color.designOnSurface
            )
            .bold()
        }
        .padding(12)
    }

    // MARK: - Member List

    private var memberList: some View {
        VStack(spacing: 8) {
            ForEach(Array(members.enumerated()), id: \.element.id) { index, member in
                Button {
                    onMemberTap(member.id)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: member.avatar)
                            .font(.designBodyMedium)
                            .foregroundStyle(memberColor(for: index))
                            .frame(width: 28, height: 28)

                        Text(member.name)
                            .font(.designBodyMedium)
                            .foregroundStyle(Color.designOnSurface)

                        Spacer()

                        VStack(alignment: .trailing, spacing: 2) {
                            CurrencyText(amount: member.amount, currencyCode: "", size: 15, foregroundColor: Color.designOnSurface)
                                .fontWeight(.medium)
                            HStack(spacing: 4) {
                                Text(member.percentage, format: .percent.precision(.fractionLength(1)))
                                    .font(.designMonoDataSmall)
                                    .foregroundStyle(Color.designOnSurfaceVariant)
                                Text("·")
                                    .foregroundStyle(Color.designOnSurfaceVariant.opacity(0.5))
                                Text("\(member.transactionCount)\(String(localized: "笔"))")
                                    .font(.designMonoDataSmall)
                                    .foregroundStyle(Color.designOnSurfaceVariant.opacity(0.7))
                            }
                        }

                        Image(systemName: "chevron.right")
                            .font(.designBodySmall)
                            .foregroundStyle(Color.designOnSurfaceVariant.opacity(0.5))
                    }
                    .padding(12)
                    .glassCard(cornerRadius: 16)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
    }

    // MARK: - Helpers

    private func memberColor(for index: Int) -> Color {
        memberColors[index % memberColors.count]
    }

    private func memberIndex(for angle: Double) -> Int {
        var cumulative: Double = 0
        for (i, member) in members.enumerated() {
            cumulative += Double(truncating: member.amount as NSNumber)
            if angle <= cumulative { return i }
        }
        return -1
    }
}
