import SwiftUI
@preconcurrency import CoreData

struct EmptySelectionView: View {
    let message: String
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "cursorarrow.motionlines")
                .font(.system(size: 36))
                .foregroundStyle(Color.designOnSurfaceVariant.opacity(0.3))
            Text(message).foregroundStyle(Color.designOnSurfaceVariant)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .designScreen()
    }
}
