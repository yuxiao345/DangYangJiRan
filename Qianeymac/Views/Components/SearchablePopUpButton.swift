import AppKit
import SwiftUI

/// 原生 `NSPopUpButton`，但点击不弹菜单——交给外层呈现自定义列表。
///
/// **为什么只能子类化**：官方没有「弹出按钮改弹别的」的机制。`NSPopUpButton` 只在鼠标按下时
/// 发 `willPopUpNotification`（通知，无法取消弹出），文档页里也没有任何可覆写的呈现钩子。
/// 覆写 `mouseDown` 是社区通行做法（改变弹出按钮点击行为的标准技巧）；
/// 用到的两个 API——`NSView` 子类化、SwiftUI 的 `.popover`（底层是 `NSPopover`）——都是官方的，
/// 只是 Apple 没有给这个组合的样例。
///
/// **保留原生控件的意义**：边框、下拉箭头、按下反馈、深浅色适配全部由 AppKit 绘制，
/// 与同表单其它原生弹出按钮按构造成一致，不靠调参对齐。
final class SearchablePopUpButton: NSPopUpButton {
    var onActivate: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        onActivate?()
    }
}

/// `SearchablePopUpButton` 的 SwiftUI 包装。
///
/// 菜单里始终只放「当前值」一项——不是为了真弹菜单，而是因为官方文档规定弹出按钮的
/// **标题与图标都取自选中菜单项**：
/// > Setting a pop up button's `image` property has no effect. The image displayed in a
/// > pop up button is taken from the selected menu item.
/// 所以当前值必须以菜单项的形式喂进去，图标才能显示。
struct SearchablePopUpButtonView: NSViewRepresentable {
    let title: String
    let icon: (name: String, color: Color)?
    let onActivate: () -> Void

    func makeNSView(context: Context) -> SearchablePopUpButton {
        // 尺寸与 `MacPopupPicker` 一致：同样是 .rounded bezel 的原生弹出按钮，
        // 高度由 AppKit 给出（实测自然高 24），不需要自己钉。
        let button = SearchablePopUpButton(frame: NSRect(x: 0, y: 0, width: 250, height: 24), pullsDown: false)
        button.bezelStyle = .rounded
        button.onActivate = onActivate
        applyCurrentValue(to: button)
        return button
    }

    func updateNSView(_ nsView: SearchablePopUpButton, context: Context) {
        nsView.onActivate = onActivate
        applyCurrentValue(to: nsView)
    }

    /// 菜单只放一项＝当前值；`mouseDown` 已拦下，这个菜单永远不会展开。
    /// 刻意不按「值是否变化」做缓存：判断图标颜色是否变化需要 Color 的比较，
    /// 而重建一个单项菜单的开销可以忽略，宁可每次都重建。
    private func applyCurrentValue(to button: NSPopUpButton) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        if let icon {
            item.image = TintedSymbolImage.make(systemName: icon.name, color: icon.color)
        }
        button.menu?.removeAllItems()
        button.menu?.addItem(item)
    }
}
