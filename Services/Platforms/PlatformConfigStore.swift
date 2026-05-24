import Foundation

final class PlatformConfigStore {
    let platformType: PlatformType

    private(set) var apiBaseURL: String
    private(set) var authHeader: String
    private(set) var authPrefix: String
    private(set) var apiKey: String?

    private let defaultsKey: String

    var isConfigured: Bool {
        guard let key = apiKey else { return false }
        return !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    init(platformType: PlatformType) {
        self.platformType = platformType
        self.defaultsKey = "quotabar.platform.\(platformType.rawValue)"

        self.apiBaseURL = ""
        self.authHeader = "Authorization"
        self.authPrefix = "Bearer "

        load()
        fillDefaultsFromTemplateIfNeeded()
    }

    func toConfigData() -> PlatformConfigData {
        PlatformConfigData(
            platformType: platformType,
            apiBaseURL: apiBaseURL,
            authHeader: authHeader,
            authPrefix: authPrefix,
            apiKey: apiKey ?? ""
        )
    }

    func setAPIKey(_ key: String) {
        apiKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        save()
    }

    func resetAPIKey() {
        apiKey = nil
        save()
    }

    // MARK: - Private

    private func load() {
        guard let dict = UserDefaults.standard.dictionary(forKey: defaultsKey) else { return }
        apiBaseURL = dict["api_base_url"] as? String ?? ""
        authHeader = dict["auth_header"] as? String ?? "Authorization"
        authPrefix = dict["auth_prefix"] as? String ?? "Bearer "
        apiKey = dict["api_key"] as? String
    }

    private func save() {
        var dict: [String: Any] = [
            "api_base_url": apiBaseURL,
            "auth_header": authHeader,
            "auth_prefix": authPrefix
        ]
        dict["api_key"] = apiKey ?? ""
        UserDefaults.standard.set(dict, forKey: defaultsKey)
    }

    private func fillDefaultsFromTemplateIfNeeded() {
        guard apiBaseURL.isEmpty else { return }

        let templateName = "\(platformType.rawValue).template"
        guard let templateURL = Bundle.main.url(forResource: templateName, withExtension: "json"),
              let data = try? Data(contentsOf: templateURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        if let baseURL = json["api_base_url"] as? String, !baseURL.isEmpty {
            apiBaseURL = baseURL
        }
        if let header = json["auth_header"] as? String {
            authHeader = header
        }
        if let prefix = json["auth_prefix"] as? String {
            authPrefix = prefix
        }
        save()
    }
}

extension PlatformType {
    var isEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: "quotabar.platform.\(rawValue).enabled") == nil {
                return self == .minimax  // Only MiniMax enabled by default
            }
            return UserDefaults.standard.bool(forKey: "quotabar.platform.\(rawValue).enabled")
        }
        set { UserDefaults.standard.set(newValue, forKey: "quotabar.platform.\(rawValue).enabled") }
    }
}
