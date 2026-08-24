import SwiftUI

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
