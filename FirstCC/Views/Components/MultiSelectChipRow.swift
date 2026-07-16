import SwiftUI

// MARK: - NameProviding (shared protocol, also in AddEditTransactionView for iOS)
#if os(macOS)
protocol NameProviding { var name: String { get } }
extension Category: NameProviding {}
extension Member: NameProviding {}
extension Merchant: NameProviding {}
extension Project: NameProviding {}
#endif

/// Multi-select chip row — generalizes the `recentPickerRow` pattern
/// Tap a chip to toggle its UUID in selectedIDs. Shows up to 4 chips + "更多" button.
struct MultiSelectChipRow<Item: Identifiable & Hashable>: View where Item.ID == UUID {
    let title: LocalizedStringKey
    let items: [Item]
    let itemIcon: (Item) -> String
    let itemColor: (Item) -> Color
    let recentKey: String
    @Binding var selectedIDs: Set<UUID>
    let onMore: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text(title)
                    .font(.designLabel)
                    .foregroundStyle(Color.designPrimary.opacity(0.8))
                Spacer()
                Button { onMore() } label: {
                    HStack(spacing: 2) {
                        Text("更多")
                        Image(systemName: "chevron.right")
                    }
                    .font(.designLabel)
                    .foregroundStyle(Color.designAccentGreen)
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 8) {
                ForEach(topItems, id: \.id) { item in
                    let isSelected = selectedIDs.contains(item.id)
                    Button {
                        selectedIDs.toggle(item.id)
                        if selectedIDs.contains(item.id) {
                            saveRecentID("\(item.id)", forKey: recentKey)
                        }
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: itemIcon(item))
                                .font(.system(size: 18))
                                .foregroundStyle(isSelected
                                    ? Color.designPrimaryFixedDim
                                    : Color.designOnSurfaceVariant)
                            if let np = item as? (any NameProviding) {
                                Text(np.name)
                                    .font(.system(size: 10)).lineLimit(1)
                                    .foregroundStyle(isSelected
                                        ? Color.designPrimaryFixedDim
                                        : Color.designOnSurfaceVariant)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(isSelected
                                    ? Color.designPrimaryFixedDim.opacity(0.12)
                                    : Color.designSurfaceContainer)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(isSelected
                                    ? Color.designPrimaryFixedDim.opacity(0.5)
                                    : Color.clear,
                                    lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Top Items (selected + recent + fill)

    private var topItems: [Item] {
        let recentIDs = UserDefaults.standard.stringArray(forKey: recentKey) ?? []
        var result: [Item] = []

        // 1. Selected items first
        for id in selectedIDs {
            if let item = items.first(where: { $0.id == id }) { result.append(item) }
            if result.count >= 4 { break }
        }

        // 2. Recent items
        for idStr in recentIDs {
            guard result.count < 4 else { break }
            if let item = items.first(where: { "\($0.id)" == idStr }),
               !selectedIDs.contains(item.id) {
                result.append(item)
            }
        }

        // 3. Fill from list
        if result.count < 4 {
            for item in items {
                guard result.count < 4 else { break }
                if !result.contains(where: { $0.id == item.id }) { result.append(item) }
            }
        }

        return Array(result.prefix(4))
    }

    private func saveRecentID(_ id: String, forKey key: String) {
        var ids = UserDefaults.standard.stringArray(forKey: key) ?? []
        ids.removeAll { $0 == id }
        ids.insert(id, at: 0)
        UserDefaults.standard.set(Array(ids.prefix(8)), forKey: key)
    }
}
