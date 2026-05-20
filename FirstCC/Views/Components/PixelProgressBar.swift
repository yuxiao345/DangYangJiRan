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
                        color: i < filledCount ? tint.opacity(0.4) : .clear,
                        radius: i < filledCount ? 4 : 0
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

    private var filledCount: Int {
        Int((progress * Double(totalBlocks)).rounded())
    }

    private func blockColor(at index: Int) -> Color {
        if index < filledCount {
            return tint
        }
        return Color.designOnSurfaceVariant.opacity(0.2)
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
