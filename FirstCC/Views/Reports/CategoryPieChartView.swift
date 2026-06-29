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
    @State private var animationProgress: Double = 0
    @State private var barFillStep: Double = 0
    @State private var barAnimID = UUID()
    @State private var hasAppeared = false
    @State private var animationTask: Task<Void, Never>?
    /// 稳定后才更新给 Chart 的数据，避免快速切换时 Charts 收到变化中的数据触发断言
    @State private var stableCategories: [CategoryExpenseItem] = []
    @State private var chartID = UUID()

    var body: some View {
        VStack(spacing: 12) {
            if let txs = transactions, !txs.isEmpty {
                transactionList(txs)
            } else {
                donutCard
                categoryList
            }
        }
        .onAppear {
            if stableCategories.isEmpty { stableCategories = categories }
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
        DonutChartContent(
            categories: stableCategories,
            animationProgress: animationProgress,
            selectedAngle: $selectedAngle,
            gradientLookup: gradientLookup,
            fallbackGradient: fallbackGradient,
            onCategoryTap: { onCategoryTap($0) }
        )
        .id(chartID)
        .frame(height: 240)
        .shadow(color: .black.opacity(0.12), radius: 20, y: 8)
        .chartOverlay { proxy in
            GeometryReader { geometry in
                let frame = geometry[proxy.plotAreaFrame]
                centerLabel
                    .position(x: frame.midX, y: frame.midY)
            }
        }
        .onChange(of: categories.map(\.id)) { _, _ in
            gradientLookup = buildGradientLookup()
            guard hasAppeared else { return }
            animationTask?.cancel()
            animationTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled else { return }
                // 先更新数据源，等一个 runloop 确保 Chart 拿到完整数据
                stableCategories = categories
                chartID = UUID()
                try? await Task.sleep(for: .milliseconds(1))
                guard !Task.isCancelled else { return }
                // 再播动画
                animationProgress = 0
                withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                    animationProgress = 1.0
                }
                guard !Task.isCancelled else { return }
                runBarAnimation(delay: 0.1)
            }
        }
        .onAppear {
            gradientLookup = buildGradientLookup()
            guard !hasAppeared else { return }
            hasAppeared = true
            withAnimation(.spring(response: 0.8, dampingFraction: 0.6)) {
                animationProgress = 1.0
            }
            runBarAnimation(delay: 0.3)
        }
    }

    // MARK: - Center Label

    private var centerLabel: some View {
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
            CurrencyText(amount: totalExpense, currencyCode: "", size: 18, foregroundColor: Color.designOnSurface)
                .fontWeight(.bold)
        }
        .padding(12)
    }

    // MARK: - Gradient Helpers

    /// Pre-computed once per category set — prevents color flashing during animation.
    @State private var gradientLookup: [String: LinearGradient] = [:]

    private var fallbackGradient: LinearGradient {
        LinearGradient(colors: [.gray.opacity(0.5), .gray], startPoint: .top, endPoint: .bottom)
    }

    private func buildGradientLookup() -> [String: LinearGradient] {
        var map: [String: LinearGradient] = [:]
        func collect(_ items: [CategoryExpenseItem]) {
            for item in items {
                map[item.name] = gradientFor(hex: item.colorHex)
                collect(item.children)
            }
        }
        collect(categories)
        return map
    }

    private func gradientFor(hex: String) -> LinearGradient {
        let base = Color(hex: hex) ?? .gray
        let lighter = base.opacity(0.65)
        return LinearGradient(
            colors: [lighter, base],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    // MARK: - Category List

    private var categoryList: some View {
        VStack(spacing: 8) {
            ForEach(Array(categories.enumerated()), id: \.element.id) { index, item in
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

                        let targetBlocks = item.percentage * 16
                        let displayProgress = min(barFillStep, targetBlocks) / 16.0
                        PixelProgressBar(progress: displayProgress, tint: Color(hex: item.colorHex) ?? .gray, totalBlocks: 16)
                    }
                    .padding(12)
                    .glassCard(cornerRadius: 16)
                }
                .buttonStyle(.plain)
                .opacity(animationProgress >= 1.0 ? 1 : 0)
                .offset(y: animationProgress >= 1.0 ? 0 : 20)
                .animation(
                    .spring(response: 0.5, dampingFraction: 0.7)
                    .delay(Double(index) * 0.06),
                    value: animationProgress
                )
            }
        }
        .padding(.horizontal, 12)
    }

    // MARK: - Bar Animation

    /// Steps through blocks one-by-one: 1 → 2 → 3 → ... → N, with a partial fill on the last block.
    private func runBarAnimation(delay: Double) {
        let maxBlocks = categories.map { $0.percentage * 16.0 }.max() ?? 8.0
        let fullSteps = Int(floor(maxBlocks))
        let remainder = maxBlocks - Double(fullSteps)
        let stepDuration = 0.2
        let thisID = UUID()
        barAnimID = thisID

        barFillStep = 0

        for i in 1...fullSteps {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay + Double(i) * stepDuration) {
                guard barAnimID == thisID else { return }
                withAnimation(.easeOut(duration: stepDuration * 0.6)) {
                    barFillStep = Double(i)
                }
            }
        }
        if remainder > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay + Double(fullSteps + 1) * stepDuration) {
                guard barAnimID == thisID else { return }
                withAnimation(.easeOut(duration: stepDuration * 0.6)) {
                    barFillStep = maxBlocks
                }
            }
        }
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
