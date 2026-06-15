import SwiftUI
@preconcurrency import CoreData

func progressColor(_ p: Double) -> Color {
    if p > 1.0 { return .red }
    if p > 0.8 { return .orange }
    if p > 0.5 { return .yellow }
    return .green
}

// View files split into Qianeymac/Views/:
//   MainSplitView.swift, Dashboard/, Accounts/, Transactions/, Reports/, Settings/, Sheets/, Budget/, Components/
