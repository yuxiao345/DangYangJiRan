import SwiftUI

struct NumpadGrid: View {
    let onDigit: (Int) -> Void
    let onDot: () -> Void
    let onDelete: () -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
            ForEach(1...9, id: \.self) { n in
                numpadButton("\(n)") { onDigit(n) }
            }
            numpadButton(".") { onDot() }
            numpadButton("0") { onDigit(0) }
            numpadButton(action: onDelete) {
                Image(systemName: "delete.backward")
                    .font(.system(size: 20))
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
