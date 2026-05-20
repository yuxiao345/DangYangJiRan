import SwiftUI

struct JoinLedgerView: View {
    @State private var inviteCode = ""

    var body: some View {
        Form {
            Section("加入已有账本") {
                TextField("输入邀请码或粘贴分享链接", text: $inviteCode)
            }
            Section {
                Text("请让账本拥有者通过 iMessage 分享邀请链接给您。")
                    .font(.designBodySmall)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("加入账本")
    }
}
