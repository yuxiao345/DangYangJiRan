import SwiftUI

/// `MacSearchablePicker` 的一行选项。
///
/// `item == nil` 表示「无」行（清除选择）。层级缩进由 `depth` 给出，
/// 与 iOS `SearchablePickerView.itemRow` 同一套信息层级：一级分类顶格、
/// 子分类右移；同时子分类用次要前景色，避免缩进在视觉上被忽略。
struct MacSearchablePickerRow<T: Identifiable & Hashable>: View {
    let item: T?
    let displayName: (T) -> String
    let icon: (T) -> String
    let color: (T) -> Color
    let depth: (T) -> Int
    let isSelected: Bool
    let isHighlighted: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: item.map(icon) ?? "nosign")
                .font(.system(size: 12))
                .foregroundStyle(item.map(color) ?? Color.secondary)
                .frame(width: 16)
            Text(item.map(displayName) ?? String(localized: "无"))
                .font(.designBodyMedium)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(foreground)
            Spacer(minLength: 8)
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }
        }
        .padding(.leading, 10 + CGFloat(item.map(depth) ?? 0) * 16)
        .padding(.trailing, 10)
        .frame(height: 24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isHighlighted ? Color.accentColor.opacity(0.14) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { action() }
    }

    private var foreground: Color {
        if isSelected { return .accentColor }
        guard let item else { return .secondary }
        return depth(item) > 0 ? Color.secondary : Color.primary
    }
}

/// `MacSearchablePicker` 里「最近使用」/「全部」/「搜索结果」的分节标题。
struct MacSearchablePickerSectionHeader: View {
    let title: LocalizedStringKey

    var body: some View {
        Text(title)
            .font(.designBodyCaption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 3)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
