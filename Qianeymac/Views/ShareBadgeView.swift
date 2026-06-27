import SwiftUI

/// Toolbar share badge: participant avatars + share/manage button.
struct ShareBadgeView: View {
    let isShared: Bool
    let isCreatingShare: Bool
    let shareParticipants: [User]
    let participantAvatars: [UUID: NSImage]
    let onTap: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            if isShared {
                HStack(spacing: -6) {
                    ForEach(shareParticipants.prefix(3), id: \.id) { user in
                        avatarCircle(for: user)
                    }
                    if shareParticipants.count > 3 {
                        Circle()
                            .fill(Color.designSurfaceContainer)
                            .frame(width: 24, height: 24)
                            .overlay {
                                Text("+\(shareParticipants.count - 3)")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.secondary)
                            }
                            .overlay(Circle().stroke(Color.designGlassBg, lineWidth: 1.5))
                    }
                }
            }

            Button(action: onTap) {
                Image(systemName: isShared ? "person.2.badge.plus" : "person.badge.plus")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .disabled(isCreatingShare)
            .overlay {
                if isCreatingShare {
                    ProgressView().scaleEffect(0.5)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
    }

    // MARK: - Avatar

    @ViewBuilder
    private func avatarCircle(for user: User) -> some View {
        if let img = participantAvatars[user.id] {
            Circle()
                .fill(.clear)
                .frame(width: 24, height: 24)
                .overlay {
                    Image(nsImage: img)
                        .resizable().scaledToFill()
                        .clipShape(Circle())
                }
                .overlay(Circle().stroke(Color.designGlassBg, lineWidth: 1.5))
        } else {
            let initial = user.displayName.first.map(String.init) ?? "?"
            Circle()
                .fill(avatarColor(for: user))
                .frame(width: 24, height: 24)
                .overlay {
                    Text(initial)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                }
                .overlay(Circle().stroke(Color.designGlassBg, lineWidth: 1.5))
        }
    }

    private func avatarColor(for user: User) -> Color {
        let colors: [Color] = [.blue, .green, .orange, .purple, .pink, .teal, .indigo]
        let idx = abs(user.id.hashValue) % colors.count
        return colors[idx]
    }
}
