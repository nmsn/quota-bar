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
                    }
                )) {
                    Text(platform.displayName)
                        .font(.body)
                }
                .toggleStyle(.checkbox)
            }

            Spacer()
        }
        .padding()
        .frame(width: 250, height: 180)
    }
}