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

struct ReportDetailContent: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.bar.xaxis").font(.system(size: 48))
                .foregroundStyle(Color.designOnSurfaceVariant.opacity(0.4))
            Text("报表功能即将上线").font(.designHeadlineMedium).foregroundStyle(Color.designOnSurfaceVariant)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .designScreen()
    }
}
