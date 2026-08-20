import SwiftUI

struct DatePickerButton: View {
    let title: LocalizedStringKey
    @Binding var date: Date
    var displayedComponents: DatePickerComponents = .date

    @State private var showPicker = false

    var body: some View {
        VStack {
            Button {
                withAnimation { showPicker.toggle() }
            } label: {
                HStack {
                    Text(title)
                        .foregroundStyle(.primary)
                    Spacer()
                    Text(date, style: .date)
                        .foregroundStyle(showPicker ? Color.designPrimary : .secondary)
                }
            }
            .buttonStyle(.plain)

            if showPicker {
                DatePicker(title, selection: $date, displayedComponents: displayedComponents)
                    .datePickerStyle(.graphical)
            }
        }
        .onChange(of: date) { oldValue, newValue in
            let cal = Calendar.current
            let oldDay = cal.component(.day, from: oldValue)
            let newDay = cal.component(.day, from: newValue)
            let oldMonth = cal.component(.month, from: oldValue)
            let newMonth = cal.component(.month, from: newValue)
            if oldDay != newDay && oldMonth == newMonth {
                withAnimation { showPicker = false }
            }
        }
    }
}
