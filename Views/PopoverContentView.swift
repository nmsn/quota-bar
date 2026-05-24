import SwiftUI

struct PopoverContentView: View {
    @ObservedObject var viewModel: PlatformViewModel
    @State private var showPlatformSelection = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerSection

            if viewModel.showingConfig {
                configSection
            } else {
                platformNavigator
                platformContent
            }

            Spacer()

            footerSection
        }
        .padding()
        .frame(width: 280, height: 320)
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack {
            Text("QuotaBar")
                .font(.headline)
            Spacer()
            if viewModel.isActivePlatformLoading {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12))
                    .rotationEffect(.degrees(360))
                    .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: viewModel.isActivePlatformLoading)
            }

            Button(action: { showPlatformSelection = true }) {
                Image(systemName: "checkmark.circle")
                    .foregroundColor(.secondary)
            }
            .popover(isPresented: $showPlatformSelection) {
                PlatformSelectionView(viewModel: viewModel)
            }
        }
    }

    // MARK: - Platform Navigator

    private var platformNavigator: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(viewModel.allPlatforms, id: \.self) { platform in
                    platformTab(platform)
                }
            }
        }
    }

    private func platformTab(_ platform: PlatformType) -> some View {
        let isActive = platform == viewModel.activePlatform
        let isConfigured = viewModel.isConfigured(platform)

        return Button(action: {
            viewModel.switchActivePlatform(platform)
        }) {
            HStack(spacing: 4) {
                Text(viewModel.platformDisplayName(platform))
                    .font(.caption.bold())
                if !isConfigured {
                    Image(systemName: "gear")
                        .font(.system(size: 8))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(isActive ? Color.accentColor : Color.gray.opacity(0.2))
            .foregroundColor(isActive ? .white : .primary)
            .cornerRadius(4)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Platform Content

    @ViewBuilder
    private var platformContent: some View {
        let platform = viewModel.activePlatform

        if !viewModel.isConfigured(platform) {
            unconfiguredSection(platform)
        } else if let error = viewModel.platformErrors[platform] {
            errorSection(error)
        } else if let data = viewModel.platformData[platform] {
            metricsSection(data)
        } else if viewModel.isLoading[platform] == true {
            loadingSection
        } else {
            emptySection
        }
    }

    // MARK: - Metrics Display

    private func metricsSection(_ data: PlatformUsageData) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(data.metrics.indices, id: \.self) { index in
                metricCard(data.metrics[index])
            }

            statusSection(data.isHealthy)
        }
    }

    private func metricCard(_ metric: UsageMetric) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(metric.label, systemImage: metricIcon(metric))
                .font(.caption.bold())

            HStack {
                if let total = metric.totalValue, total > 0 {
                    Text("\(I18nService.shared.translate("popover.remaining")): \(Int(metric.currentValue))/\(Int(total)) \(metric.unit)")
                        .font(.caption)
                } else {
                    Text("\(metric.currentValue, specifier: "%.2f") \(metric.unit)")
                        .font(.caption)
                }
                Spacer()
            }

            if let resetTime = metric.resetTime {
                Text(I18nService.shared.translate("popover.reset") + ": " + formatResetTime(resetTime))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(8)
        .background(metricColor(metric).opacity(0.15))
        .cornerRadius(6)
    }

    private func metricIcon(_ metric: UsageMetric) -> String {
        switch metric.label {
        case "Daily": return "sun.max"
        case "Weekly": return "calendar"
        case "Balance": return "dollarsign.circle"
        default: return "chart.bar"
        }
    }

    private func metricColor(_ metric: UsageMetric) -> Color {
        switch metric.label {
        case "Daily": return .orange
        case "Weekly": return .blue
        case "Balance": return .green
        default: return .gray
        }
    }

    // MARK: - Status

    private func statusSection(_ isHealthy: Bool) -> some View {
        HStack {
            if isHealthy {
                Label(I18nService.shared.translate("popover.normal"), systemImage: "checkmark.circle.fill")
                    .font(.caption.bold())
                    .foregroundColor(.green)
            } else {
                Label(I18nService.shared.translate("popover.low"), systemImage: "exclamationmark.circle.fill")
                    .font(.caption.bold())
                    .foregroundColor(.red)
            }
            Spacer()
        }
    }

    // MARK: - Config Section

    private var configSection: some View {
        VStack(spacing: 12) {
            Text(String(format: I18nService.shared.translate("popover.configurePlatform"), viewModel.configPlatform?.displayName ?? ""))
                .font(.subheadline.bold())

            HStack(spacing: 8) {
                PasteableTextField(text: $viewModel.apiKeyInput, placeholder: I18nService.shared.translate("popover.inputPlaceholder"), isSecure: !viewModel.showingAPIKey)
                    .frame(height: 60)

                Button(action: { viewModel.showingAPIKey.toggle() }) {
                    Image(systemName: viewModel.showingAPIKey ? "eye.slash" : "eye")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }

            if viewModel.configPlatform == .glm {
                regionPicker
            }

            HStack {
                Button(action: { viewModel.cancelConfig() }) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.bordered)

                Button(action: { viewModel.saveAPIKey() }) {
                    Image(systemName: "checkmark")
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
        .background(Color.accentColor.opacity(0.08))
        .cornerRadius(8)
    }

    private var regionPicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(I18nService.shared.translate("config.region"))
                .font(.caption.bold())
            Picker("", selection: $viewModel.regionInput) {
                Text(I18nService.shared.translate("config.regionDomestic")).tag("domestic")
                Text(I18nService.shared.translate("config.regionInternational")).tag("international")
            }
            .pickerStyle(.segmented)
        }
    }

    // MARK: - Unconfigured Section

    private func unconfiguredSection(_ platform: PlatformType) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(String(format: I18nService.shared.translate("popover.platformNotConfigured"), platform.displayName), systemImage: "gear")
                .font(.subheadline.bold())

            Button(action: { viewModel.configureAPIKey(for: platform) }) {
                Text(I18nService.shared.translate("popover.configureNow"))
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
    }

    // MARK: - Error Section

    private func errorSection(_ error: PlatformError) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(I18nService.shared.translate("popover.error"), systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.bold())
                .foregroundColor(.red)
            Text(error.localizedDescription)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.1))
        .cornerRadius(8)
    }

    // MARK: - Loading & Empty

    private var loadingSection: some View {
        VStack {
            Spacer()
            ProgressView()
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var emptySection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(I18nService.shared.translate("popover.notConfigured"), systemImage: "gear")
                .font(.subheadline.bold())
            Text(I18nService.shared.translate("popover.configureFirst"))
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
    }

    // MARK: - Footer

    private var footerSection: some View {
        HStack(spacing: 8) {
            if viewModel.showingConfig {
                Button(action: { viewModel.cancelConfig() }) {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.bordered)
            } else {
                if viewModel.isConfigured(viewModel.activePlatform) {
                    Button(action: {
                        viewModel.fetchAllUsage()
                    }) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                }

                Button(action: { viewModel.configureAPIKey(for: viewModel.activePlatform) }) {
                    Image(systemName: "gear")
                }
                .buttonStyle(.bordered)
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }

    // MARK: - Helpers

    private func formatResetTime(_ date: Date) -> String {
        let interval = date.timeIntervalSinceNow
        guard interval > 0 else { return I18nService.shared.translate("daily.reset.soon") }

        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60

        if hours > 24 {
            let days = hours / 24
            let remainingHours = hours % 24
            return String(format: I18nService.shared.translate("weekly.reset.remaining"), days, remainingHours)
        } else if hours > 0 {
            return String(format: I18nService.shared.translate("daily.reset.remaining"), hours, minutes)
        } else {
            return String(format: I18nService.shared.translate("daily.reset.minutesonly"), minutes)
        }
    }
}
