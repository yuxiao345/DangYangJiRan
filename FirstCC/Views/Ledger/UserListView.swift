import SwiftUI
import SwiftData

struct UserListView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appContainer: AppContainer

    let ledger: Ledger?
    @State private var users: [User] = []

    private var effectiveLedger: Ledger? { ledger ?? appContainer.currentLedger }

    var body: some View {
        List {
            if users.isEmpty {
                Text("暂无共享成员").foregroundStyle(Color.designOnSurfaceVariant)
            }
            ForEach(users) { user in
                HStack {
                    Image(systemName: user.role == .owner ? "crown.fill" : "person.fill")
                        .foregroundStyle(user.role == .owner ? .yellow : Color.designPrimaryContainer)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(user.displayName)
                        Text(user.role.displayName)
                            .font(.designBodySmall)
                            .foregroundStyle(Color.designOnSurfaceVariant)
                    }
                    Spacer()
                    Text(user.cloudKitUserRecordID)
                        .font(.designBodySmall)
                        .foregroundStyle(Color.designOnSurfaceVariant.opacity(0.5))
                        .lineLimit(1)
                }
            }
        }
        .navigationTitle("共享成员")
        .task { loadUsers() }
    }

    private func loadUsers() {
        guard let ledger = effectiveLedger else { return }
        let ledgerID = ledger.id
        let descriptor = FetchDescriptor<User>(
            predicate: #Predicate { $0.ledger?.id == ledgerID },
            sortBy: [SortDescriptor(\.joinedAt)]
        )
        users = (try? modelContext.fetch(descriptor)) ?? []
    }
}
