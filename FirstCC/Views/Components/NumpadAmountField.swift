import SwiftUI

/// 自定义数字键盘金额输入 — 替代 iPad 上有 bug 的 .decimalPad TextField
struct NumpadAmountField: View {
    @Binding var amount: Decimal
    let currencySymbol: String
    let allowSignToggle: Bool

    @State private var showNumpad = false
    @State private var text: String = ""

    init(amount: Binding<Decimal>, currencySymbol: String = "¥", allowSignToggle: Bool = false) {
        self._amount = amount
        self.currencySymbol = currencySymbol
        self.allowSignToggle = allowSignToggle
    }

    var body: some View {
        VStack(spacing: 8) {
            Button {
                if !showNumpad {
                    #if os(iOS)
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    #endif
                }
                withAnimation(.easeInOut(duration: 0.2)) {
                    if showNumpad { syncToBinding() }
                    showNumpad.toggle()
                }
                if !showNumpad { text = formatDecimal(amount) }
            } label: {
                HStack {
                    Text(currencySymbol)
                        .font(.custom("JetBrainsMono-Medium", fixedSize: 15))
                        .foregroundStyle(.secondary)
                    Text(displayText)
                        .font(.custom("JetBrainsMono-Medium", fixedSize: 15))
                        .foregroundStyle(showNumpad ? Color.designPrimary : .primary)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showNumpad {
                NumpadGrid(
                    onDigit: { appendDigit($0) },
                    onDot: appendDot,
                    onDelete: backspace
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))

                HStack(spacing: 12) {
                    Button {
                        text = ""
                    } label: {
                        Text("清空")
                            .font(.designLabel)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.designSurfaceContainer.opacity(0.5))
                            )
                            .foregroundStyle(Color.designOnSurfaceVariant)
                    }
                    .buttonStyle(.plain)

                    if allowSignToggle {
                        Button {
                            if text.hasPrefix("-") {
                                text.removeFirst()
                            } else {
                                text = "-" + text
                            }
                        } label: {
                            Text("+/-")
                                .font(.custom("JetBrainsMono-Medium", fixedSize: 16))
                                .frame(maxWidth: .infinity)
                                .frame(height: 48)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.designSurfaceContainer.opacity(0.5))
                                )
                                .foregroundStyle(Color.designOnSurfaceVariant)
                        }
                        .buttonStyle(.plain)
                    }

                    Button {
                        syncToBinding()
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showNumpad = false
                        }
                    } label: {
                        Text("确认")
                            .font(.designLabel)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.designPrimaryContainer.opacity(0.2))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.designPrimaryContainer.opacity(0.4), lineWidth: 1)
                            )
                            .foregroundStyle(Color.designPrimaryContainer)
                    }
                    .buttonStyle(.plain)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onAppear { text = formatDecimal(amount) }
    }

    /// 编辑中显示当前输入（空则显示0）；非编辑中显示 binding 值
    private var displayText: String {
        if showNumpad {
            return text.isEmpty ? "0" : text
        }
        return text.isEmpty ? formatDecimal(amount) : text
    }

    private func formatDecimal(_ d: Decimal) -> String {
        let s = NSDecimalNumber(decimal: d).stringValue
        return s == "0" ? "" : s
    }

    private func parseText() -> Decimal {
        Decimal(string: text.filter { $0.isNumber || $0 == "." || $0 == "-" }) ?? 0
    }

    private func syncToBinding() {
        amount = parseText()
    }

    private func appendDigit(_ digit: Int) {
        if let dotIndex = text.firstIndex(of: ".") {
            let decimals = text[dotIndex...].dropFirst()
            if decimals.count >= 2 { return }
        }
        if text == "0" { text = "\(digit)" }
        else { text += "\(digit)" }
    }

    private func appendDot() {
        if text.contains(".") { return }
        if text.isEmpty { text = "0." }
        else { text += "." }
    }

    private func backspace() {
        if text.count <= 1 { text = "" }
        else { text.removeLast() }
    }
}
