import SwiftUI
@preconcurrency import CoreData

struct MemberListView: View {
    @Environment(AppContainer.self) private var appContainer
    @Environment(\.managedObjectContext) private var modelContext
    @State private var members: [Member] = []
    @State private var showAddAlert = false
    @State private var newName = ""
    @State private var editingMember: Member?
    @State private var listVersion = 0

    let ledger: Ledger?
    private var effectiveLedger: Ledger? { ledger ?? appContainer.currentLedger }

    init(ledger: Ledger? = nil) {
        self.ledger = ledger
    }

    var body: some View {
        SearchableList(items: members, searchKey: \.name) { filteredMembers, isSearching in
            memberListView(filteredMembers, isSearching: isSearching)
        }
        .onAppear(perform: loadMembers)
    }

    @ViewBuilder
    private func memberListView(_ members: [Member], isSearching: Bool) -> some View {
        List {
            if members.isEmpty {
                ContentUnavailableView(
                    isSearching ? "无匹配结果" : "暂无联系人",
                    systemImage: "person.crop.circle.badge.plus",
                    description: Text("点击右上角 + 添加联系人")
                )
            }
            ForEach(members) { member in
                Button { editingMember = member } label: {
                    HStack {
                        Image(systemName: member.avatar)
                            .foregroundStyle(Color.designPrimaryContainer)
                        Text(LocalizedStringKey(member.name))
                        Spacer()
                        if !member.isActive {
                            Text("已停用")
                                .font(.designBodySmall)
                                .foregroundStyle(Color.designOnSurfaceVariant)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .swipeActions {
                    Button(role: .destructive) {
                        try? appContainer.memberService.deleteMember(member, context: modelContext)
                        loadMembers()
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                }
            }
        }
        .navigationTitle("联系人管理")
        .id(listVersion)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showAddAlert = true } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel(Text("添加联系人"))
            }
        }
        .alert("添加联系人", isPresented: $showAddAlert) {
            TextField("姓名", text: $newName)
            Button("取消", role: .cancel) { newName = "" }
            Button("添加") {
                addMember()
                newName = ""
            }
            .disabled(newName.isEmpty)
        }
        .sheet(item: $editingMember) { member in
            EditMemberView(member: member)
        }
        .onChange(of: editingMember) { _, newValue in
            if newValue == nil { listVersion += 1; loadMembers() }
        }
    }

    private func addMember() {
        guard let ledger = effectiveLedger else { return }
        let member = Member(name: newName, sortOrder: members.count, context: modelContext)
        try? appContainer.memberService.createMember(member, ledger: ledger, context: modelContext)
        loadMembers()
    }

    private func loadMembers() {
        guard let ledger = effectiveLedger else { return }
        members = (try? appContainer.memberService.fetchMembers(for: ledger, context: modelContext)) ?? []
    }
}

struct EditMemberView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var modelContext
    @Environment(AppContainer.self) private var appContainer
    let member: Member
    @State private var name: String
    @State private var avatar: String
    @State private var isActive: Bool

    init(member: Member) {
        self.member = member
        _name = State(initialValue: member.name)
        _avatar = State(initialValue: member.avatar)
        _isActive = State(initialValue: member.isActive)
    }

    private let avatarOptions = [
        "person.circle", "person.circle.fill", "face.smiling", "heart.circle",
        "star.circle", "figure.child", "figure.walk", "teddybear"
    ]

    var body: some View {
        NavigationStack {
            Form {
                TextField("姓名", text: $name)
                Picker("头像", selection: $avatar) {
                    ForEach(avatarOptions, id: \.self) { icon in
                        Label(icon, systemImage: icon)
                    }
                }
                Toggle("启用", isOn: $isActive)
            }
            .navigationTitle("编辑联系人")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("保存") { save() } }
            }
        }
    }

    private func save() {
        member.name = name
        member.avatar = avatar
        member.isActive = isActive
        try? appContainer.memberService.updateMember(member, context: modelContext)
        dismiss()
    }
}
