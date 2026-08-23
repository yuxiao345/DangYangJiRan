import SwiftUI

extension View {
    func errorAlert(_ title: LocalizedStringKey, message: Binding<String?>) -> some View {
        // No buttons — SwiftUI automatically renders a system OK button to dismiss.
        alert(title, isPresented: Binding(
            get: { message.wrappedValue != nil },
            set: { if !$0 { message.wrappedValue = nil } }
        )) {
            // System default OK button (no explicit Button needed).
        } message: {
            Text(message.wrappedValue ?? "")
        }
    }
}
