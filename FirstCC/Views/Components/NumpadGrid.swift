import SwiftUI

/// 自定义数字键盘的金额输入状态。
///
/// 关键行为：程序预填的值（编辑已有交易、套用模版、选中拆分子项…）在用户按下第一个
/// 数字键时被整串替换，而不是追加 —— 不需要先点「清空」。
/// 退格和清空不算「整串重输」：它们只把状态标成已由用户编辑，后续照常追加/删除。
/// 负号是例外：预填值是负数时，整串替换只换数值、保留符号（见 `toggleSign()`）。
/// 只在 `seed(_:)` 里进入预填态，所以「用户打了一半又去套模版」这类操作也能正确处理。
struct AmountInputState {
    /// 显示用的金额串，可能带千分位。空串等同于 0。
    var text: String = ""
    /// 串仍是程序预填的原样、用户没按过任何键。
    private(set) var isPristine = false

    /// 程序写入一个值。传入空串表示「这是个空字段」，不会进入预填态。
    mutating func seed(_ value: String) {
        text = value
        isPristine = !value.isEmpty
    }

    mutating func appendDigit(_ digit: Int) {
        // 预填态、「0」「0.00」占位：整串顶掉，而不是拼成「05」。
        // 必须在两位小数上限之前判断 —— 否则 "0.00" 会被上限拦下，按了没反应。
        if isPristine || text == "0" || text == "0.00" {
            // 预填值带负号时保留符号：信用卡余额这类字段，用户换的是金额不是方向
            let sign = isPristine && text.hasPrefix("-") ? "-" : ""
            text = sign + "\(digit)"
            isPristine = false
            return
        }
        guard decimalPlaces < 2 else { return }
        text += "\(digit)"
    }

    mutating func appendDot() {
        if isPristine {
            text = text.hasPrefix("-") ? "-0." : "0."
            isPristine = false
            return
        }
        guard !text.contains(".") else { return }
        text = text.isEmpty ? "0." : text + "."
    }

    /// 翻转正负号。预填态不改变：用户只是调了方向、还没输入数字，
    /// 之后按的第一个数字仍整串替换，但会保留这个符号。
    mutating func toggleSign() {
        guard !text.isEmpty else { return }
        text = text.hasPrefix("-") ? String(text.dropFirst()) : "-" + text
    }

    mutating func backspace() {
        isPristine = false
        text = String(text.dropLast())
    }

    mutating func clear() {
        isPristine = false
        text = ""
    }

    private var decimalPlaces: Int {
        guard let dotIndex = text.firstIndex(of: ".") else { return 0 }
        return text[dotIndex...].dropFirst().count
    }
}

struct NumpadGrid: View {
    let onDigit: (Int) -> Void
    let onDot: () -> Void
    let onDelete: () -> Void
    var onClear: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                numpadButton("1") { onDigit(1) }
                numpadButton("2") { onDigit(2) }
                numpadButton("3") { onDigit(3) }
            }
            HStack(spacing: 8) {
                numpadButton("4") { onDigit(4) }
                numpadButton("5") { onDigit(5) }
                numpadButton("6") { onDigit(6) }
            }
            HStack(spacing: 8) {
                numpadButton("7") { onDigit(7) }
                numpadButton("8") { onDigit(8) }
                numpadButton("9") { onDigit(9) }
            }
            HStack(spacing: 8) {
                if let onClear {
                    numpadButton(action: onClear) {
                        Text("CE").font(.system(size: 16, weight: .medium))
                    }
                }
                numpadButton(".") { onDot() }
                numpadButton("0") { onDigit(0) }
                numpadButton(action: onDelete) {
                    Image(systemName: "delete.backward")
                        .font(.system(size: 20))
                }
                .accessibilityLabel(Text("删除"))
            }
        }
    }

    private func numpadButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.custom("JetBrainsMono-Medium", fixedSize: 24))
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(Color.designSurfaceContainer)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .foregroundStyle(Color.designOnSurface)
        }
        .buttonStyle(.plain)
    }

    private func numpadButton(action: @escaping () -> Void, @ViewBuilder label: () -> some View) -> some View {
        Button(action: action) {
            label()
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(Color.designSurfaceContainer)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .foregroundStyle(Color.designOnSurface)
        }
        .buttonStyle(.plain)
    }
}
