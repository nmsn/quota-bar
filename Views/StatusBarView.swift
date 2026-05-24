import SwiftUI

struct StatusBarView: View {
    let platformData: PlatformUsageData?
    var displayMode: DisplayMode = .used

    // Legacy support
    let usageData: UsageData?

    init(platformData: PlatformUsageData?, displayMode: DisplayMode = .used) {
        self.platformData = platformData
        self.displayMode = displayMode
        self.usageData = nil
    }

    // Legacy init
    init(usageData: UsageData?, displayMode: DisplayMode = .used) {
        self.platformData = nil
        self.usageData = usageData
        self.displayMode = displayMode
    }

    private var primaryPercent: String {
        if let data = platformData, let metric = data.metrics.first {
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

        // Legacy fallback
        guard let data = usageData else { return "--" }
        let percentage: Double
        switch displayMode {
        case .used:
            percentage = data.dailyUsedPercentage
        case .remaining:
            percentage = 1.0 - data.dailyUsedPercentage
        }
        return "\(Int(percentage * 100))%"
    }

    private var secondaryPercent: String? {
        if let data = platformData, data.metrics.count > 1 {
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

        // Legacy fallback
        guard let data = usageData else { return nil }
        let percentage: Double
        switch displayMode {
        case .used:
            percentage = data.weeklyUsedPercentage
        case .remaining:
            percentage = 1.0 - data.weeklyUsedPercentage
        }
        return "\(Int(percentage * 100))%"
    }

    private var statusColor: Color {
        if let data = platformData {
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

        // Legacy fallback
        guard let data = usageData, data.dailyTotal > 0 else { return .green }
        let remainingRatio = Double(data.dailyRemaining) / Double(data.dailyTotal)
        if remainingRatio < 0.1 {
            return .red
        } else if remainingRatio < 0.5 {
            return .yellow
        } else {
            return .green
        }
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
        .frame(minWidth: 36, idealWidth: 60, maxWidth: .infinity, minHeight: 22, idealHeight: 22, maxHeight: 22, alignment: .leading)
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
