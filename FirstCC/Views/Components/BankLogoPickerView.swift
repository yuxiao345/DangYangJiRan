import SwiftUI

struct BankLogoPickerView: View {
    @Binding var selectedLogoID: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(BankLogoPresets.allByCategory, id: \.category) { section in
                    Section(section.category.rawValue) {
                        ForEach(section.logos) { logo in
                            Button {
                                selectedLogoID = logo.id
                                dismiss()
                            } label: {
                                HStack(spacing: 12) {
                                    Image(uiImage: logo.logoImage)
                                        .resizable()
                                        .frame(width: 36, height: 36)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))

                                    Text(logo.name)
                                        .font(.designBodyMedium)
                                        .foregroundStyle(Color.designOnSurface)

                                    Spacer()

                                    if selectedLogoID == logo.id {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(Color.designPrimaryFixedDim)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .designScreen()
            .scrollContentBackground(.hidden)
            .navigationTitle("选择Logo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }
}

private extension BankLogoPresets {
    static var allByCategory: [(category: BankLogoPreset.BankCategory, logos: [BankLogoPreset])] {
        let categories: [BankLogoPreset.BankCategory] = [.stateOwned, .nationalCommercial, .cityCommercial, .rural, .foreign, .online]
        return categories.compactMap { cat in
            let logos = all.filter { $0.category == cat }
            return logos.isEmpty ? nil : (cat, logos)
        }
    }
}
