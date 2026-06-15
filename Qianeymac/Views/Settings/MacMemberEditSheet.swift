import SwiftUI
@preconcurrency import CoreData

struct MacMemberEditSheet: View {
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
        VStack(spacing: 16) {
            Text("编辑联系人").font(.title2.weight(.semibold))
            Form {
                TextField("姓名", text: $name)
                Picker("头像", selection: $avatar) {
                    ForEach(avatarOptions, id: \.self) { icon in
                        Label(icon, systemImage: icon).tag(icon)
                    }
                }
                Toggle("启用", isOn: $isActive)
            }
            .formStyle(.grouped)
            HStack(spacing: 12) {
                Button("取消") { dismiss() }.keyboardShortcut(.escape)
                Button("保存") { save() }.keyboardShortcut(.return).disabled(name.isEmpty)
            }
        }
        .padding(24).frame(width: 360, height: 320)
    }

    private func save() {
        member.name = name
        member.avatar = avatar
        member.isActive = isActive
        try? appContainer.memberService.updateMember(member, context: modelContext)
        dismiss()
    }
}

