import SwiftUI

struct PhotoItem: Identifiable {
    let id = UUID()
    let data: Data
}

struct FullScreenPhotoView: View {
    @Environment(\.dismiss) private var dismiss
    let data: Data

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                    Text("无法加载图片")
                }
                .foregroundStyle(.white)
            }
        }
        .overlay(alignment: .topTrailing) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title)
                    .foregroundStyle(.white)
                    .padding(16)
            }
            .accessibilityLabel(Text("关闭"))
        }
        .statusBarHidden(true)
    }
}
