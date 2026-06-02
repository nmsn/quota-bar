import SwiftUI

struct PlatformSelectionView: View {
    @ObservedObject var viewModel: PlatformViewModel
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(I18nService.shared.translate("popover.selectPlatforms"))
                .font(.headline)
                .padding(.bottom, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(PlatformType.allCases, id: \.self) { platform in
                        Toggle(isOn: Binding(
                            get: { platform.isEnabled },
                            set: { newValue in
                                PlatformManager.shared.setPlatformEnabled(newValue, for: platform)
                                if newValue {
                                    viewModel.switchActivePlatform(platform)
                                }
                                viewModel.fetchAllUsage()
                            }
                        )) {
                            HStack {
                                Text(platform.displayName)
                                    .font(.body)
                                Spacer()
                            }
                        }
                        .disabled(PlatformManager.shared.isLastEnabledPlatform(platform) && platform.isEnabled)
                    }
                }
            }

            if PlatformType.allCases.allSatisfy({ !$0.isEnabled }) {
                Text(I18nService.shared.translate("popover.atLeastOnePlatform"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .frame(width: 250, height: 280)
    }
}