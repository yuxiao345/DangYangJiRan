import SwiftUI
@preconcurrency import CoreData

enum ReportType: String, CaseIterable, Identifiable {
    case trend = "收支趋势"
    case category = "分类占比"
    case assets = "资产变化"
    case budget = "预算执行"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .trend: "chart.line.uptrend.xyaxis"
        case .category: "chart.pie"
        case .assets: "chart.bar"
        case .budget: "gauge.with.dots.needle.33percent"
        }
    }
}

struct ReportTypeContent: View {
    @State private var selectedReport: ReportType?
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        List(ReportType.allCases, selection: $selectedReport) { report in
            Label(report.rawValue, systemImage: report.icon)
                .padding(.vertical, 4)
        }
        .scrollContentBackground(.hidden)
        .designScreen()
    }
}

struct ReportDetailContent: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.bar.xaxis").font(.system(size: 48))
                .foregroundStyle(Color.designOnSurfaceVariant.opacity(0.4))
            Text("报表功能即将上线").font(.title3).foregroundStyle(Color.designOnSurfaceVariant)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .designScreen()
    }
}

