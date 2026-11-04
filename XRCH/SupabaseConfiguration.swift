import Foundation

// Public client configuration loaded from the local build settings.
// Values embedded in an iOS app can be extracted. Never use service-role/GPU secrets.
enum SupabaseConfiguration {
    #if AUTH_TESTING
    // Reserved-domain fixtures for the offline authentication harness only.
    private static let projectHost = "example.invalid"
    static let publicKey = "mock-public-key"
    #else
    private static let projectHost = Bundle.main.object(forInfoDictionaryKey: "SupabaseProjectHost") as? String ?? ""
    static let publicKey = Bundle.main.object(forInfoDictionaryKey: "SupabaseAnonKey") as? String ?? ""
    #endif

    private static var configuredURL: URL? {
        guard !projectHost.isEmpty, !projectHost.contains("$("), projectHost != "your-project.supabase.co",
              let url = URL(string: "https://\(projectHost)"),
              url.scheme == "https", url.host == projectHost,
              url.user == nil, url.password == nil,
              url.path.isEmpty, url.query == nil, url.fragment == nil,
              !publicKey.isEmpty, !publicKey.contains("$("), !publicKey.hasPrefix("YOUR_") else { return nil }
        return url
    }

    // A missing configuration never falls back to a live service.
    static let projectURL = configuredURL ?? URL(string: "https://example.invalid")!
    static let functionsURL = projectURL.appendingPathComponent("functions/v1")
    static let authURL = projectURL.appendingPathComponent("auth/v1")

    static func validate() throws {
        guard configuredURL != nil else { throw ConfigurationError.missingConfiguration }
    }

    private enum ConfigurationError: LocalizedError {
        case missingConfiguration
        var errorDescription: String? {
            "Supabase 설정이 없습니다. Config/LocalSecrets.xcconfig에 본인 프로젝트의 공개 클라이언트 설정을 추가해 주세요."
        }
    }
}
