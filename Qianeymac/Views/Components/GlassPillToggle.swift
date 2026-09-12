import SwiftUI

/// 玻璃胶囊维度切换器。报表的「支出/收入」与预算的「本期/累计」共用同一控件，
/// 保证跨页面同一类操作的视觉与交互一致。
struct GlassPillToggle<Option: Hashable>: View {
    let options: [Option]
    @Binding var selection: Option
    /// 返回已本地化的标题（调用方负责 String(localized:) / NSLocalizedString）
    let label: (Option) -> String

    /// 激活项滑块在选项间复用同一个 id，切换时做几何过渡而不是硬切
    @Namespace private var indicator

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.self) { option in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        selection = option
                    }
                } label: {
                    Text(label(option))
                        .font(.designBodyMedium)
                        .foregroundStyle(
                            selection == option
                                ? Color.designOnSurface
                                : Color.designOnSurfaceVariant.opacity(0.7)
                        )
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .contentShape(Rectangle())
                        .background {
                            if selection == option {
                                activePill
                                    .matchedGeometryEffect(id: "glassPillIndicator", in: indicator)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == option ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(4)
        .background { Capsule().fill(Color.designGlassBg) }
        .background(.regularMaterial, in: Capsule())
        .overlay { Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1) }
        .overlay { Capsule().stroke(Color.white.opacity(0.04), lineWidth: 1).padding(1) }
        .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
    }

    /// 激活项：微白色浮雕卡片 + 极细描边 + 极浅投影
    private var activePill: some View {
        Capsule()
            .fill(Color.white.opacity(0.06))
            .background(.regularMaterial, in: Capsule())
            .overlay { Capsule().stroke(Color.white.opacity(0.15), lineWidth: 1) }
            .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
    }
}
