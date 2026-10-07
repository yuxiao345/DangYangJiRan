import AppKit
import SwiftUI

/// 把 SF Symbol 染成指定颜色并固定字号，供 AppKit 控件（菜单项、弹出按钮）使用。
///
/// 单独提取是因为菜单项图标必须由 AppKit 画：`NSPopUpButton` 的文档明确写着
/// "Setting a pop up button's `image` property has no effect. The image displayed in a
/// pop up button is taken from the selected menu item."——所以字段按钮上的图标
/// 只能通过「菜单项的 image」提供，不能自己给按钮设图。
enum TintedSymbolImage {
    static func make(systemName: String, color: Color, pointSize: CGFloat = 12) -> NSImage? {
        guard let base = NSImage(systemSymbolName: systemName, accessibilityDescription: nil) else {
            return nil
        }
        let palette = NSImage.SymbolConfiguration(paletteColors: [NSColor(color)])
        let sized = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
        return base.withSymbolConfiguration(sized.applying(palette))
    }
}
