import SwiftUI
@preconcurrency import CoreData

struct RefundSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var modelContext
    @Environment(AppContainer.self) private var appContainer

    let original: Transaction
    let onDone: () -> Void

    @State private var amount: Decimal = 0
    @State private var amountString: String = ""
    @State private var date: Date = Date()
    @State private var note: String = ""
    @State private var showNumpad: Bool = false
    @State private var errorMessage: String?

    private var maxRefund: Decimal { abs(original.amount) }
    private var refundFraction: Double {
        guard maxRefund > 0 else { return 0 }
        return Double(truncating: (amount / maxRefund) as NSNumber)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 24) {
                        originalSummaryCard
                        refundInputCard

                        if amount > maxRefund {
                            overflowWarning
                        }

                        decorativeGlow
                    }
                    .padding(16)
                }
                .scrollClipDisabled()

                // Bottom numpad
                if showNumpad {
                    numpadView
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .designScreen()
            .animation(.easeInOut(duration: 0.25), value: showNumpad)
            .navigationTitle("退款")
            .navigationBarTitleDisplayMode(.inline)
            .errorAlert("退款失败", message: $errorMessage)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("确认退款") { save() }
                        .fontWeight(.bold)
                        .disabled(amount <= 0 || amountString.isEmpty || amount > maxRefund)
                }
            }
            .onAppear {
                amount = maxRefund
                date = original.date
                syncAmountString()
            }
        }
    }

    // MARK: - Original Summary Card

    private var originalSummaryCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("原交易摘要")
                .font(.designLabel)
                .foregroundStyle(Color.designOnSurfaceVariant)
                .tracking(1.0)

            VStack(spacing: 0) {
                HStack {
                    Text("原交易金额")
                        .font(.designBodyMedium)
                        .foregroundStyle(Color.designOnSurfaceVariant)
                    Spacer()
                    CurrencyText(
                        amount: maxRefund,
                        currencyCode: original.currencyCode,
                        size: 24,
                        foregroundColor: Color.designOnSurface
                    )
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)

                Divider()
                    .overlay(Color.designOnSurfaceVariant.opacity(0.1))
                    .padding(.horizontal, 20)

                HStack {
                    Text("原交易日期")
                        .font(.designBodyMedium)
                        .foregroundStyle(Color.designOnSurfaceVariant)
                    Spacer()
                    Text(original.date.formatted(date: .abbreviated, time: .omitted))
                        .font(.designBodyMedium)
                        .foregroundStyle(Color.designOnSurface)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .glassCard(cornerRadius: 24)
        }
    }

    // MARK: - Refund Input Card

    private var refundInputCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("退款详情")
                .font(.designLabel)
                .foregroundStyle(Color.designOnSurfaceVariant)
                .tracking(1.0)

            VStack(spacing: 0) {
                // Amount input with custom numpad trigger
                VStack(alignment: .leading, spacing: 4) {
                    Text("退款金额")
                        .font(.designBodySmall)
                        .foregroundStyle(Color.designOnSurfaceVariant)
                        .padding(.horizontal, 20)

                    Button {
                        withAnimation { showNumpad.toggle() }
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text("¥")
                                .font(.custom("JetBrainsMono-Medium", fixedSize: 24))
                                .foregroundStyle(Color.designPrimary)
                            Text(amountString.isEmpty ? "0.00" : amountString)
                                .font(.custom("JetBrainsMono-Medium", fixedSize: 32))
                                .foregroundStyle(Color.designOnSurface)
                                .tracking(-0.02)
                            Spacer()
                            Image(systemName: showNumpad ? "keyboard.arrow.down" : "keyboard.arrow.up")
                                .font(.system(size: 14))
                                .foregroundStyle(Color.designPrimaryContainer.opacity(0.5))
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(amountString.isEmpty ? Color.designOutlineVariant.opacity(0.2) : Color.designPrimaryContainer.opacity(0.4))
                            .frame(height: 2)
                            .padding(.horizontal, 20)
                    }

                    HStack {
                        Text("最大可退金额 \(CurrencyFormatter.currencySymbol(for: original.currencyCode))\(maxRefund.formatted(.number.precision(.fractionLength(2))))")
                            .font(.designBodySmall)
                            .foregroundStyle(Color.designOnSurfaceVariant.opacity(0.7))
                        Spacer()
                        PixelProgressBar(
                            progress: min(refundFraction, 1.0),
                            tint: refundFraction > 1.0 ? Color.designAccentRed : Color.designAccentGreen,
                            totalBlocks: 20
                        )
                        .frame(width: 80, height: 6)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                }
                .padding(.vertical, 20)

                Divider()
                    .overlay(Color.designOnSurfaceVariant.opacity(0.1))
                    .padding(.horizontal, 20)

                DatePickerButton(title: "退款日期", date: $date)
                .padding(.horizontal, 20)
                .padding(.vertical, 16)

                Divider()
                    .overlay(Color.designOnSurfaceVariant.opacity(0.1))
                    .padding(.horizontal, 20)

                // Note
                TextEditor(text: $note)
                    .font(.designBodyMedium)
                    .foregroundStyle(Color.designOnSurface)
                    .frame(minHeight: 80)
                    .scrollContentBackground(.hidden)
                    .padding(12)
                    .background(Color.designSurfaceContainer.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(alignment: .topLeading) {
                        if note.isEmpty {
                            Text("备注（可选）")
                                .font(.designBodyMedium)
                                .foregroundStyle(Color.designOnSurfaceVariant.opacity(0.4))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 20)
                                .allowsHitTesting(false)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
            }
            .glassCard(cornerRadius: 24)
        }
    }

    // MARK: - Overflow Warning

    private var overflowWarning: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14))
            Text("退款金额超过原交易金额")
                .font(.designBodySmall)
        }
        .foregroundStyle(Color.designAccentRed)
        .frame(maxWidth: .infinity)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.designAccentRed.opacity(0.1))
        )
    }

    // MARK: - Decorative

    private var decorativeGlow: some View {
        Circle()
            .fill(Color.designPrimaryContainer.opacity(0.08))
            .frame(width: 128, height: 128)
            .blur(radius: 48)
            .padding(.top, 8)
    }

    // MARK: - Numpad

    private var numpadView: some View {
        VStack(spacing: 8) {
            NumpadGrid(
                onDigit: { appendDigit($0) },
                onDot: { appendDot() },
                onDelete: { backspace() }
            )
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .padding(.top, 12)
        .background(
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(Color.designGlassBorderHighlight)
                        .frame(height: 1)
                }
        )
    }

    private func appendDigit(_ digit: Int) {
        if amountString == "0" || amountString == "0.00" { amountString = "\(digit)" }
        else { amountString += "\(digit)" }
        syncAmountFromString()
    }

    private func appendDot() {
        if amountString.contains(".") { return }
        if amountString.isEmpty { amountString = "0." }
        else { amountString += "." }
        syncAmountFromString()
    }

    private func backspace() {
        if amountString.count <= 1 { amountString = "0" }
        else { amountString.removeLast() }
        syncAmountFromString()
    }

    private func syncAmountFromString() {
        amount = Decimal(string: amountString.replacingOccurrences(of: ",", with: "")) ?? 0
    }

    // MARK: - Helpers

    private func syncAmountString() {
        if amount == 0 { amountString = "" }
        else {
            amountString = CurrencyFormatter.decimalFormatter.string(from: amount as NSDecimalNumber) ?? "\(amount)"
        }
    }

    private func save() {
        do {
            try appContainer.transactionService.createRefund(
                for: original,
                amount: amount,
                date: date,
                context: modelContext
            )
            onDone()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
