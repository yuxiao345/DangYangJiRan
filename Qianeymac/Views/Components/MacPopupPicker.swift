import SwiftUI
import AppKit

/// Apple-standard `NSPopUpButton` wrapper that uses `NSMenuItem.indentationLevel`
/// for hierarchical menu indentation — the official macOS API since 10.0.
/// `parentId` ensures parent-child families stay together when splitting
/// into "最近使用" / "全部" sections.
struct MacPopupPicker<T: Identifiable & Hashable>: NSViewRepresentable {
    @Binding var selection: T?
    let items: [T]
    let icon: (T) -> String
    let name: (T) -> String
    let color: (T) -> Color
    let indent: ((T) -> Int)?
    let parentId: ((T) -> T.ID?)?
    let recentKey: String?
    let onSelect: (T) -> Void

    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 250, height: 24), pullsDown: false)
        button.bezelStyle = .rounded
        button.target = context.coordinator
        button.action = #selector(Coordinator.selectionChanged(_:))
        context.coordinator.owner = button
        rebuild(button, context: context)
        return button
    }

    func updateNSView(_ nsView: NSPopUpButton, context: Context) {
        context.coordinator.parent = self
        context.coordinator.owner = nsView
        rebuild(nsView, context: context)
    }

    // MARK: - Menu Rebuild

    private func rebuild(_ button: NSPopUpButton, context: Context) {
        guard let menu = button.menu else { return }
        menu.removeAllItems()

        let recentIDs: Set<String> = recentKey.map { key in
            Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
        } ?? []
        let hasRecent = !recentIDs.isEmpty

        // Partition: "最近使用" is a convenience subset (kept in family units),
        // "全部" always shows everything including recent items.
        let recentItems: [T] = {
            guard hasRecent else { return [] }
            var recent: [T] = []
            if let pid = parentId {
                var recentFamilyIDs = Set<T.ID>()
                for item in items where recentIDs.contains(String(describing: item.id)) {
                    let root = familyRoot(of: item, pid: pid)
                    recentFamilyIDs.insert(root.id)
                }
                var seenRoots = Set<T.ID>()
                for item in items {
                    let root = familyRoot(of: item, pid: pid)
                    if recentFamilyIDs.contains(root.id) {
                        if root.id != item.id || !seenRoots.contains(root.id) {
                            recent.append(item)
                        }
                        if root.id == item.id { seenRoots.insert(root.id) }
                    }
                }
            } else {
                for item in items where recentIDs.contains(String(describing: item.id)) {
                    recent.append(item)
                }
            }
            return Array(recent.prefix(5))
        }()

        // "无" — always first
        menu.addItem(noneMenuItem())

        if hasRecent {
            menu.addItem(.sectionHeader(title: String(localized: "最近使用")))
            for item in recentItems {
                menu.addItem(menuItem(for: item, useIndent: false))
            }
            menu.addItem(.sectionHeader(title: String(localized: "全部")))
            let recentIDs = Set(recentItems.map { $0.id })
            for item in items where !recentIDs.contains(item.id) {
                menu.addItem(menuItem(for: item, useIndent: true))
            }
        } else {
            menu.addItem(.separator())
            for item in items {
                menu.addItem(menuItem(for: item, useIndent: true))
            }
        }

        // Restore selection
        if let sel = selection, let idx = menu.items.firstIndex(where: { ($0.representedObject as? T)?.id == sel.id }) {
            button.selectItem(at: idx)
        } else {
            button.selectItem(at: 0)
        }
    }

    /// Walk up the parent chain to find the root of the family
    private func familyRoot(of item: T, pid: (T) -> T.ID?) -> T {
        var current = item
        while let p = pid(current), let pItem = items.first(where: { $0.id == p }) {
            current = pItem
        }
        return current
    }

    // MARK: - Menu Item Builders

    private func noneMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: String(localized: "无"), action: nil, keyEquivalent: "")
        item.representedObject = nil
        return item
    }

    private func menuItem(for value: T, useIndent: Bool) -> NSMenuItem {
        let item = NSMenuItem(title: name(value), action: nil, keyEquivalent: "")
        item.image = tintedIcon(systemName: icon(value), color: color(value))
        item.representedObject = value
        // indentationLevel — Apple standard API (macOS 10.0+), indents icon + text together
        item.indentationLevel = useIndent ? (indent?(value) ?? 0) : 0
        return item
    }

    private func tintedIcon(systemName: String, color: Color) -> NSImage? {
        guard let base = NSImage(systemSymbolName: systemName, accessibilityDescription: nil) else { return nil }
        let paletteConfig = NSImage.SymbolConfiguration(paletteColors: [NSColor(color)])
        let sized = NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)
        return base.withSymbolConfiguration(sized.applying(paletteConfig))
    }

    // MARK: - Coordinator

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject {
        var parent: MacPopupPicker
        weak var owner: NSPopUpButton?

        init(parent: MacPopupPicker) {
            self.parent = parent
        }

        @objc func selectionChanged(_ sender: NSPopUpButton) {
            guard let obj = sender.selectedItem?.representedObject as? T else {
                parent.selection = nil
                return
            }
            parent.selection = obj
            parent.onSelect(obj)
        }
    }
}
