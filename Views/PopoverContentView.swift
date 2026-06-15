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
            Text(I18nService.shared.translate("app.name"))
                .font(.headline)
            Spacer()
            if viewModel.isActivePlatformLoading {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12))
                    .rotationEffect(.degrees(360))
                    .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: viewModel.isActivePlatformLoading)
            }

            Button(action: { showPlatformSelection = true }) {
                Image(systemName: "checklist")
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
        } else if let data = viewModel.platformData[platform] {
            // 有数据就显示数据 (和状态栏一致). metrics 空 → 无数据; 否则正常显示,
            // 若同时有刷新错误则附带提示, 让用户知道数值可能不是最新的.
            if data.metrics.isEmpty {
                noDataSection
            } else {
                metricsSection(data, refreshError: viewModel.platformErrors[platform])
            }
        } else if let error = viewModel.platformErrors[platform] {
            errorSection(error)
        } else if viewModel.isLoading[platform] == true {
            loadingSection
        } else {
            emptySection
        }
    }

    // MARK: - Metrics Display

    private func metricsSection(_ data: PlatformUsageData, refreshError: PlatformError? = nil) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(data.metrics.indices, id: \.self) { index in
                metricCard(data.metrics[index])
            }

            statusSection(data.isHealthy)

            if let refreshError {
                refreshErrorHint(refreshError)
            }
        }
    }

    // 有数据但最近一次刷新失败时的小提示: 数值仍是旧缓存, 让用户知道可能不是最新.
    private func refreshErrorHint(_ error: PlatformError) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "wifi.exclamationmark")
                .foregroundColor(.orange)
            Text(I18nService.shared.translate("popover.staleData"))
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    private func metricCard(_ metric: UsageMetric) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(metricDisplayLabel(metric), systemImage: metricIcon(metric))
                .font(.caption.bold())

            HStack {
                if metric.unit == "%" {
                    Text("\(I18nService.shared.translate("popover.remaining")): \(Int(metric.currentValue))%")
                        .font(.caption)
                } else if let total = metric.totalValue, total > 0 {
                    Text("\(I18nService.shared.translate("popover.remaining")): \(formatCredits(metric.currentValue))/\(formatCredits(total)) \(metric.unit)")
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
        case "five_hour": return "clock"
        case "weekly_limit": return "calendar"
        case "mcp_monthly": return "wrench.and.screwdriver"  // MCP 月度调用次数
        case "monthly_usage": return "calendar.badge.clock"  // MiMo 本月用量
        case "compensation_quota": return "gift"  // MiMo 补偿额度
        default: return "dollarsign.circle"  // 货币余额 (DeepSeek CNY/USD 等)
        }
    }

    private func metricColor(_ metric: UsageMetric) -> Color {
        switch metric.label {
        case "five_hour": return .orange
        case "weekly_limit": return .blue
        case "mcp_monthly": return .purple  // MCP 月度
        case "monthly_usage": return .teal  // MiMo 本月用量
        case "compensation_quota": return .indigo  // MiMo 补偿额度
        default: return .green  // 货币余额
        }
    }

    /// 把 service 生成的 key (five_hour / weekly_limit / 货币代码) 翻译成本地化文本
    private func metricDisplayLabel(_ metric: UsageMetric) -> String {
        let key = "metric." + metric.label
        let translated = I18nService.shared.translate(key)
        // 翻译命中: i18n 返回 localized string; 未命中时返回 key 自身, 此时回退到原始 label (如货币代码 CNY/USD)
        return translated == key ? metric.label : translated
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

            // StepFun 用账号密码登录, 其他平台用 API Key
            if viewModel.configPlatform == .stepfun {
                stepfunCredentialFields
            } else {
                HStack(spacing: 8) {
                    PasteableTextField(text: $viewModel.apiKeyInput, placeholder: I18nService.shared.translate("popover.inputPlaceholder"), isSecure: !viewModel.showingAPIKey)
                        .frame(height: 60)

                    Button(action: { viewModel.showingAPIKey.toggle() }) {
                        Image(systemName: viewModel.showingAPIKey ? "eye.slash" : "eye")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
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
                .disabled(!configSaveButtonEnabled)
            }
        }
        .padding()
        .background(Color.accentColor.opacity(0.08))
        .cornerRadius(8)
    }

    // StepFun 账号密码输入: 手机号 + 密码 两个独立输入框
    private var stepfunCredentialFields: some View {
        VStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(I18nService.shared.translate("popover.stepfunUsername"))
                    .font(.caption.bold())
                    .foregroundColor(.secondary)
                PasteableTextField(text: $viewModel.usernameInput, placeholder: I18nService.shared.translate("popover.stepfunUsernamePlaceholder"), isSecure: false)
                    .frame(height: 36)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(I18nService.shared.translate("popover.stepfunPassword"))
                    .font(.caption.bold())
                    .foregroundColor(.secondary)
                HStack(spacing: 8) {
                    PasteableTextField(text: $viewModel.passwordInput, placeholder: I18nService.shared.translate("popover.stepfunPasswordPlaceholder"), isSecure: !viewModel.showingAPIKey)
                        .frame(height: 36)
                    Button(action: { viewModel.showingAPIKey.toggle() }) {
                        Image(systemName: viewModel.showingAPIKey ? "eye.slash" : "eye")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            Text(I18nService.shared.translate("popover.stepfunHint"))
                .font(.caption2)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // 保存按钮是否可用: StepFun 需要账号密码都填, 其他平台填了 API Key 即可
    private var configSaveButtonEnabled: Bool {
        guard let platform = viewModel.configPlatform else { return false }
        if platform == .stepfun {
            return !viewModel.usernameInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                   !viewModel.passwordInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return !viewModel.apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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

    // 已配置但解析出的 metrics 为空 (API 结构变化/字段缺失): 灰色"无数据",
    // 区别于"额度告急"的红色, 避免误导用户.
    private var noDataSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(I18nService.shared.translate("popover.noData"), systemImage: "questionmark.circle")
                .font(.subheadline.bold())
                .foregroundColor(.secondary)
            Text(I18nService.shared.translate("error.invalidResponse"))
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
                        Task { await viewModel.fetchAllUsage() }
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

    /// 把大额 Credits 数字格式化成易读的中文 (亿/万).
    /// 例: 32_851_959_146 → "328.52亿", 5_148_040_854 → "51.48亿", 932 → "932"
    private func formatCredits(_ value: Double) -> String {
        let v = Int(value)
        if v >= 100_000_000 {
            // 亿: 除以 1e8, 保留两位小数
            return String(format: "%.2f亿", Double(v) / 1e8)
        } else if v >= 10_000 {
            // 万
            return String(format: "%.2f万", Double(v) / 1e4)
        } else {
            return "\(v)"
        }
    }
}
