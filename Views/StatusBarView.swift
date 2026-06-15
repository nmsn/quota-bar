import SwiftUI

struct StatusBarView: View {
    let platformData: PlatformUsageData?
    var displayMode: DisplayMode = .used

    init(platformData: PlatformUsageData?, displayMode: DisplayMode = .used) {
        self.platformData = platformData
        self.displayMode = displayMode
    }

    private var primaryPercent: String {
        guard let data = platformData, let metric = data.metrics.first else { return "--" }
        if let total = metric.totalValue, total > 0 {
            let percentage: Double
            switch displayMode {
            case .remaining:
                percentage = metric.currentValue / total
            case .used:
                percentage = (total - metric.currentValue) / total
            }
            return "\(Int(percentage * 100))%"
        } else {
            // Balance display (no total value = likely currency balance)
            return formatBalance(metric.currentValue, unit: nil)
        }
    }

    private var secondaryPercent: String? {
        guard let data = platformData, data.metrics.count > 1 else { return nil }
        let metric = data.metrics[1]
        if let total = metric.totalValue, total > 0 {
            let percentage: Double
            switch displayMode {
            case .remaining:
                percentage = metric.currentValue / total
            case .used:
                percentage = (total - metric.currentValue) / total
            }
            return "\(Int(percentage * 100))%"
        } else {
            return formatBalance(metric.currentValue, unit: nil)
        }
    }

    private var statusColor: Color {
        guard let data = platformData else { return .secondary }
        // 无 metrics (API 结构变化/字段缺失): 灰色, 不要因 isHealthy 假报红色
        if data.metrics.isEmpty { return .secondary }
        if let metric = data.metrics.first, let total = metric.totalValue, total > 0 {
            let remainingRatio = metric.currentValue / total
            if remainingRatio < 0.1 {
                return .red
            } else if remainingRatio < 0.5 {
                return .yellow
            } else {
                return .green
            }
        }
        return data.isHealthy ? .green : .red
    }

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: "circle.fill")
                .font(.system(size: 12))
                .frame(width: 12)
                .foregroundColor(statusColor)

            VStack(alignment: .leading, spacing: 0) {
                Text(primaryPercent)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .lineLimit(1)
                if let secondary = secondaryPercent {
                    Text(secondary)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: secondaryPercent != nil ? .topLeading : .center)
        }
        .padding(.horizontal, 2)
        .frame(minWidth: 36, idealWidth: 44, maxWidth: .infinity, minHeight: 22, idealHeight: 22, maxHeight: 22, alignment: .leading)
    }

    private func formatBalance(_ value: Double, unit: String?) -> String {
        if value >= 1000 {
            return String(format: "%.1fK", value / 1000)
        } else if value >= 100 {
            return String(format: "%.0f", value)
        } else {
            return String(format: "%.1f", value)
        }
    }
}

#Preview {
    StatusBarView(platformData: nil)
}
