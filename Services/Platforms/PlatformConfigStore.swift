import Foundation

final class PlatformConfigStore {
    let platformType: PlatformType

    private(set) var apiBaseURL: String
    private(set) var apiBaseURLInternational: String?
    private(set) var authHeader: String
    private(set) var authPrefix: String
    private(set) var apiKey: String?
    private(set) var region: String  // "domestic" or "international"

    private let defaultsKey: String

    var isConfigured: Bool {
        guard let key = apiKey else { return false }
        return !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    init(platformType: PlatformType) {
        self.platformType = platformType
        self.defaultsKey = "quotabar.platform.\(platformType.rawValue)"

        self.apiBaseURL = ""
        self.apiBaseURLInternational = nil
        self.authHeader = "Authorization"
        self.authPrefix = "Bearer "
        self.region = "domestic"

        load()
        fillDefaultsFromTemplateIfNeeded()
    }

    func toConfigData() -> PlatformConfigData {
        PlatformConfigData(
            platformType: platformType,
            apiBaseURL: apiBaseURL,
            authHeader: authHeader,
            authPrefix: authPrefix,
            apiKey: apiKey ?? "",
            region: region,
            apiBaseURLInternational: apiBaseURLInternational
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

    func setRegion(_ newRegion: String) {
        region = newRegion
        save()
    }

    // MARK: - Private

    private func load() {
        guard let anyValue = UserDefaults.standard.object(forKey: defaultsKey) else { return }
        guard var dict = anyValue as? [String: Any] else {
            // Data corruption: stored value is not a dictionary, reset it
            UserDefaults.standard.removeObject(forKey: defaultsKey)
            return
        }
        // Strip NSNull values left by a previous bug and re-save the cleaned dict
        let hasNSNull = dict.values.contains { $0 is NSNull }
        if hasNSNull {
            dict = dict.filter { !($0.value is NSNull) }
            UserDefaults.standard.set(dict, forKey: defaultsKey)
        }
        apiBaseURL = dict["api_base_url"] as? String ?? ""
        apiBaseURLInternational = dict["api_base_url_international"] as? String
        authHeader = dict["auth_header"] as? String ?? "Authorization"
        authPrefix = dict["auth_prefix"] as? String ?? "Bearer "
        apiKey = dict["api_key"] as? String
        region = dict["region"] as? String ?? "domestic"
    }

    private func save() {
        var dict: [String: Any] = [
            "api_base_url": apiBaseURL,
            "auth_header": authHeader,
            "auth_prefix": authPrefix,
            "region": region
        ]
        if let intlURL = apiBaseURLInternational {
            dict["api_base_url_international"] = intlURL
        }
        dict["api_key"] = apiKey ?? ""
        UserDefaults.standard.set(dict, forKey: defaultsKey)
    }

    private func fillDefaultsFromTemplateIfNeeded() {
        guard apiBaseURL.isEmpty else { return }

        // Template name based on base platform (minimax, glm, etc.)
        let templatePlatformName: String
        switch platformType {
        case .minimax_cn, .minimax_en:
            templatePlatformName = "minimax"
        case .glm_cn, .glm_en:
            templatePlatformName = "glm"
        default:
            templatePlatformName = platformType.rawValue
        }
        let templateName = "\(templatePlatformName).template"
        guard let templateURL = Bundle.main.url(forResource: templateName, withExtension: "json"),
              let data = try? Data(contentsOf: templateURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        if let baseURL = json["api_base_url"] as? String, !baseURL.isEmpty {
            apiBaseURL = baseURL
        }
        if let intlURL = json["api_base_url_international"] as? String {
            apiBaseURLInternational = intlURL
        }
        if let header = json["auth_header"] as? String {
            authHeader = header
        }
        if let prefix = json["auth_prefix"] as? String {
            authPrefix = prefix
        }
        if let templateRegion = json["region"] as? String {
            region = templateRegion
        }
        save()
    }
}

extension PlatformType {
    var isEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: "quotabar.platform.\(rawValue).enabled") == nil {
                return self == .minimax_cn  // Only MiniMax CN enabled by default
            }
            return UserDefaults.standard.bool(forKey: "quotabar.platform.\(rawValue).enabled")
        }
        set { UserDefaults.standard.set(newValue, forKey: "quotabar.platform.\(rawValue).enabled") }
    }
}
