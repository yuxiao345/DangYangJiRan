import SwiftUI

/// 宽屏双栏布局的共享断点。总览、账户、流水三个页面必须用同一套规则，别再各写一份。
///
/// 断点由三件事共同决定，缺一不可：
/// - regular/regular：iPhone Duo 内屏实测可用区域只有 867×469pt，却报告 regular/regular；
/// - 宽 > 高：iPad 13 寸竖屏宽 1024pt，只看宽度会把竖屏也误判成双栏；
/// - 宽 ≥ `minWidth`：双栏至少需要「左栏 380 + 栏距 20 + 右栏最小 400 + 左右页边距 32」= 832，向上取整。
///
/// 辅助功能字号下固定宽度的左栏会被大号金额、指标卡撑到换行，因此一律退回单栏。
enum TwoColumnLayout {
    static let minWidth: CGFloat = 840

    /// 左栏宽度：随可用宽度缩放，再夹在 [min, max] 之间，避免 13 寸上过宽、mini 上过窄。
    static func leftWidth(
        for availableWidth: CGFloat,
        fraction: CGFloat,
        min minWidth: CGFloat,
        max maxWidth: CGFloat
    ) -> CGFloat {
        Swift.min(Swift.max(availableWidth * fraction, minWidth), maxWidth)
    }
}

/// 按可用尺寸在「单栏 / 双栏」之间切换，并把实测宽度交给双栏分支。
///
/// 首帧尺寸未知时先按单栏排，拿到尺寸后立即切换。测量只用 `.onGeometryChange`、不用
/// `GeometryReader` 包住内容：iOS 26 要求 ScrollView 是导航容器的直接内容，
/// 大标题折叠、内容从玻璃导航栏/标签栏下方滑过都依赖这一点（Apple DTS，论坛 thread 821675）。
/// 代价是尺寸刚变化的那一帧仍按旧布局排，通常不可见。
struct AdaptiveTwoColumnLayout<Compact: View, Regular: View>: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var containerSize: CGSize = .zero

    private let regular: (CGFloat) -> Regular
    private let compact: Compact
    /// 布局模式回调，参数为「当前是否双栏」。
    /// **不保证只触发一次**：模式真的变了会报，视图重新出现时也会按当前模式补报
    /// （补报是必需的，否则 iPad 横屏冷启动时初始值就已是双栏、等不到「变化」）。
    /// 所以调用方若要拿它初始化用户可手改的状态，必须自己记住上次的值做去重。
    private let onModeChange: ((Bool) -> Void)?

    init(
        onModeChange: ((Bool) -> Void)? = nil,
        @ViewBuilder regular: @escaping (CGFloat) -> Regular,
        @ViewBuilder compact: () -> Compact
    ) {
        self.regular = regular
        self.compact = compact()
        self.onModeChange = onModeChange
    }

    private var usesTwoColumn: Bool {
        horizontalSizeClass == .regular
            && verticalSizeClass == .regular
            && !dynamicTypeSize.isAccessibilitySize
            && containerSize.width > containerSize.height
            && containerSize.width >= TwoColumnLayout.minWidth
    }

    var body: some View {
        Group {
            if usesTwoColumn {
                regular(containerSize.width)
            } else {
                compact
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { containerSize = $0 }
        // `initial: true` 不是可选项：iPad 上标签页内容会先于首次布局就拿到真实尺寸，
        // 于是 `usesTwoColumn` 从第一次求值起就是 true，只监听「变化」的回调永远等不到触发
        // （实测：Duo 上正常、iPad 横屏冷启动不生效）。带 initial 后，出现时先按当前模式报一次。
        .onChange(of: usesTwoColumn, initial: true) { _, isTwoColumn in
            onModeChange?(isTwoColumn)
        }
    }
}
