import Foundation

/// Provides runtime access to app version information from Bundle.
enum AppVersion {
    static var marketingVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    static var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
    }

    static var fullVersion: String {
        "\(marketingVersion) (\(buildNumber))"
    }
}
