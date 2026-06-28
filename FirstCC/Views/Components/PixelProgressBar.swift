import SwiftUI

struct PixelProgressBar: View {
    let progress: Double  // 0...1
    let totalBlocks: Int
    let tint: Color

    init(progress: Double, tint: Color, totalBlocks: Int = 20) {
        self.progress = max(0, min(1, progress))
        self.tint = tint
        self.totalBlocks = totalBlocks
    }

    var body: some View {
        HStack(spacing: blockGap) {
            ForEach(0..<totalBlocks, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(blockColor(at: i))
                    .frame(height: 12)
                    .shadow(
                        color: blockGlowColor(at: i),
                        radius: blockGlowOpacity(at: i) > 0 ? 4 : 0
                    )
            }
        }
        .padding(blockGap * 2)
        .background {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.designSurfaceContainer.opacity(0.5))
                .overlay {
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.designGlassBorderHighlight, lineWidth: 1)
                }
        }
    }

    private var blockGap: CGFloat { 1.5 }

    /// How many full blocks (integer count) based on current progress
    private var fullBlocks: Int {
        Int(progress * Double(totalBlocks))
    }

    /// Fractional part of the currently-filling block (0…1)
    private var fillFraction: Double {
        (progress * Double(totalBlocks)) - Double(fullBlocks)
    }

    private func blockColor(at index: Int) -> Color {
        if index < fullBlocks {
            return tint  // fully filled
        }
        if index == fullBlocks {
            return tint.opacity(fillFraction)  // filling now
        }
        return Color.designOnSurfaceVariant.opacity(0.2)  // empty
    }

    private func blockGlowOpacity(at index: Int) -> Double {
        if index < fullBlocks { return 1 }
        if index == fullBlocks { return fillFraction }
        return 0
    }

    private func blockGlowColor(at index: Int) -> Color {
        let o = blockGlowOpacity(at: index)
        return o > 0 ? tint.opacity(0.4 * o) : .clear
    }
}

struct PixelBlock: View {
    let color: Color
    let size: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(color)
            .frame(width: size, height: size)
    }
}
