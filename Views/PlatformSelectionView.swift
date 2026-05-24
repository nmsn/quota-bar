import SwiftUI

struct PlatformSelectionView: View {
    @ObservedObject var viewModel: PlatformViewModel
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Select Platforms")
                .font(.headline)
                .padding(.bottom, 8)

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
                    HStack(alignment: .top, spacing: 4) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(platform.displayName)
                                .font(.body)
                            Text("At least one platform required")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .opacity(PlatformManager.shared.isLastEnabledPlatform(platform) && platform.isEnabled ? 1 : 0)
                        }
                        Spacer()
                    }
                }
                .disabled(PlatformManager.shared.isLastEnabledPlatform(platform) && platform.isEnabled)
            }

            Spacer()
        }
        .padding()
        .frame(width: 250, height: 200)
    }
}