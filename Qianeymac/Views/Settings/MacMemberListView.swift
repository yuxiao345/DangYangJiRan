import SwiftUI
@preconcurrency import CoreData

struct MacMemberListView: View {
    @Environment(AppContainer.self) private var appContainer
    @Environment(\.managedObjectContext) private var modelContext
    let ledger: Ledger?
    @State private var members: [Member] = []
    @State private var showAddAlert = false
    @State private var newName = ""
    @State private var editingMember: Member?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("成员管理").font(.headline).foregroundStyle(Color.designOnSurface)
                    Spacer()
                    Button { showAddAlert = true } label: {
                        Image(systemName: "plus").fontWeight(.semibold)
                    }
                    .buttonStyle(.borderless)
                }

                ForEach(members) { member in
                    memberRow(member)
                }
                if members.isEmpty {
                    Text("暂无联系人").foregroundStyle(Color.designOnSurfaceVariant).padding(.top, 20)
                }
            }
            .padding(24).frame(maxWidth: 600)
        }
        .designScreen()
        .onAppear(perform: load)
        .alert("添加联系人", isPresented: $showAddAlert) {
            TextField("姓名", text: $newName)
            Button("取消", role: .cancel) { newName = "" }
            Button("添加") { addMember(); newName = "" }
                .disabled(newName.isEmpty)
        }
        .sheet(item: $editingMember) { member in
            MacMemberEditSheet(member: member)
        }
        .onChange(of: editingMember) { _, newValue in
            if newValue == nil { load() }
        }
    }

    private var effectiveLedger: Ledger? { ledger ?? appContainer.currentLedger }

    private func memberRow(_ member: Member) -> some View {
        HStack(spacing: 8) {
            Image(systemName: member.avatar)
                .foregroundStyle(Color.designPrimaryContainer)
            Text(LocalizedStringKey(member.name)).font(.body)
            if !member.isActive {
                Text("已停用").font(.caption).foregroundStyle(Color.designOnSurfaceVariant)
            }
            Spacer()
            Button {
                try? appContainer.memberService.deleteMember(member, context: modelContext)
                load()
            } label: {
                Image(systemName: "trash").foregroundStyle(Color.designAccentRed)
            }
            .buttonStyle(.borderless)
        }
        .padding(10)
        .background(Color.designGlassBg.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .onTapGesture { editingMember = member }
    }

    private func addMember() {
        guard let l = effectiveLedger else { return }
        let member = Member(name: newName, sortOrder: members.count, context: modelContext)
        try? appContainer.memberService.createMember(member, ledger: l, context: modelContext)
        load()
    }

    private func load() {
        guard let l = effectiveLedger else { return }
        members = (try? appContainer.memberService.fetchMembers(for: l, context: modelContext)) ?? []
    }
}

