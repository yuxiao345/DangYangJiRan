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
        HStack(spacing: 2) {
            ForEach(0..<totalBlocks, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(blockColor(at: i))
            }
        }
    }

    private var filledCount: Int {
        Int((progress * Double(totalBlocks)).rounded())
    }

    private func blockColor(at index: Int) -> Color {
        if index < filledCount {
            return tint
        }
        return Color.gray.opacity(0.15)
    }
}
