import SwiftUI

/// 等宽分段选择条：玻璃卡片底 + 选中项圆角高亮。
/// 报表页的「分类占比/收支趋势/多维分析」与预算明细页的「本期/累计」共用同一控件，
/// 保证同一类操作的样式只有一个来源。
///
/// 只进 iOS target —— Mac 端的同功能控件是 ``GlassPillToggle``（玻璃胶囊），
/// 两端各自的样式不同是既定设计，所以本文件不随 DesignSystem 一起进 Mac target。
struct DesignSegmentedBar<Option: Hashable>: View {
    let options: [Option]
    @Binding var selection: Option
    /// 返回已本地化的标题（调用方负责 String(localized:) / NSLocalizedString）
    let label: (Option) -> String

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.self) { option in
                Button {
                    selection = option
                } label: {
                    Text(label(option))
                        .font(.designLabel)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            selection == option
                                ? Color.designPrimaryContainer.opacity(0.25)
                                : Color.clear,
                            in: RoundedRectangle(cornerRadius: 10)
                        )
                }
                .foregroundStyle(
                    selection == option
                        ? Color.designOnSurface
                        : Color.designOnSurfaceVariant
                )
                .buttonStyle(.plain)
                // 选中态只靠颜色区分，VoiceOver 需要显式告知
                .accessibilityAddTraits(selection == option ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(4)
        .glassCard(cornerRadius: 14)
    }
}
