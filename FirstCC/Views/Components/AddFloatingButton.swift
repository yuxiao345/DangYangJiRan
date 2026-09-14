import SwiftUI

/// 页面右下角的「记一笔 / 添加账户」悬浮按钮。
///
/// 总览、账户、流水三页共用同一份实现和同一组边距，保证按钮在各页落在完全相同的
/// 屏幕坐标上（圆心 pt (353.7, 742.7)，直径 56pt）。
///
/// 历史教训：这个按钮原本在导航栏里（`ToolbarItem(placement: .primaryAction)`），
/// 尺寸、着色、圆形玻璃底**全部由 toolbar 环境提供**，代码只是一个裸的
/// `Image(systemName: "plus")`。后来把它移到右下角浮层，这些"免费"的东西就没了，
/// 只能手绘——手绘时又把 `designPrimary`（前景色 token，深色下是近白的 `#f0ffed`）
/// 当成大圆填充色，于是整块泛白、跟导航栏里的查找图标完全不像。
///
/// 现在改用 iOS 26 的 Liquid Glass 按钮样式：材质和着色重新交回系统，
/// 与 `MainTabView` 上 `.tint(Color.designAccentGreen)` 的取值路径一致，
/// 因此和查找图标同色同材质。
struct AddFloatingButton: View {
    let title: LocalizedStringKey
    let identifier: String
    let action: () -> Void

    /// 可见玻璃圆的直径。
    private static let diameter: CGFloat = 56
    /// 交给 label 的边长。`.buttonStyle(.glass)` 会在 label 之外再包一层自己的内边距，
    /// 实测「可见圆直径 = label 边长 + 14」，所以这里反过来减掉 14。
    private static let labelSide: CGFloat = diameter - 14

    var body: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            button
        }
        // 实测标定值，使圆心落在 pt (353.7, 742.7)——与迁移前 ZStack 版的位置一致。
        // 横向用 15 而不是 20：玻璃样式在可见圆之外还留了约 5pt 不可见的布局边距，
        // 直接写 20 会得到约 25pt 的视觉间隙。
        .padding(.trailing, 15)
        .padding(.bottom, 20)
    }

    @ViewBuilder
    private var button: some View {
        if #available(iOS 26.0, *) {
            Button {
                action()
            } label: {
                glyph(side: Self.labelSide)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .accessibilityLabel(Text(title))
            .accessibilityIdentifier(identifier)
        } else {
            Button {
                action()
            } label: {
                glyph(side: Self.diameter)
                    .foregroundStyle(Color.designOnPrimary)
                    .background(Circle().fill(Color.designPrimary))
            }
            .accessibilityLabel(Text(title))
            .accessibilityIdentifier(identifier)
        }
    }

    private func glyph(side: CGFloat) -> some View {
        Image(systemName: "plus")
            .font(.system(size: 24, weight: .semibold))
            .frame(width: side, height: side)
    }
}
