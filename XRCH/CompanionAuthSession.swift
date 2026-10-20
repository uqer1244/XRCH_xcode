import Combine
import Foundation
import Security

private struct StoredCompanionSession: Codable {
    let userId: String
    let email: String?
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date
    // Optional for compatibility with sessions stored before guest support.
    let isAnonymous: Bool?
    let nickname: String?
    let isAdmin: Bool?
}

private struct AuthResponse: Decodable {
    let success: Bool
    let message: String?
    let userId: String?
    let email: String?
    let accessToken: String?
    let refreshToken: String?
    let accessExpiresIn: Int?
    let nickname: String?
    let isAdmin: Bool?
    let isAnonymous: Bool?
}

private struct SupabaseAuthResponse: Decodable {
    struct User: Decodable {
        let id: String
        let email: String?
        let isAnonymous: Bool
        enum CodingKeys: String, CodingKey {
            case id, email
            case isAnonymous = "is_anonymous"
        }
    }
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int
    let user: User
    enum CodingKeys: String, CodingKey {
        case user
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
    }
}

enum CompanionAuthError: LocalizedError {
    case loginRequired, invalidResponse
    case server(String)
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .loginRequired: "인증 세션이 변경되었습니다. 다시 시도해 주세요."
        case .invalidResponse: "인증 서버 응답을 읽을 수 없습니다."
        case .server(let message): message
        case .keychain: "인증 정보를 안전하게 저장할 수 없습니다."
        }
    }
}

@MainActor
final class CompanionAuthSession: ObservableObject {
    @Published private(set) var email: String?
    @Published private(set) var status = "게스트 연결 준비 중"
    @Published private(set) var isWorking = false
    @Published private(set) var isGuest = false
    @Published private(set) var nickname: String?
    @Published private(set) var isAdmin = false
    @Published private(set) var usage: CompanionUsage?
    @Published private(set) var usageStatus = "사용량 확인 중"

    private let storage: CompanionSessionStorage
    private let guestStorage: CompanionSessionStorage
    private let network: URLSession
    private var session: StoredCompanionSession?
    private var tokenTask: Task<String, Error>?
    private var tokenTaskID: UUID?
    private var revision = UUID()
    private var storageReadFailed = false

    // A guest has a server-authenticated session but has not signed in to an account.
    var isAuthenticated: Bool { session != nil && !isGuest }
    var hasSession: Bool { session != nil }

    init(storage: CompanionSessionStorage = KeychainCompanionSessionStorage(),
         guestStorage: CompanionSessionStorage = KeychainCompanionSessionStorage(account: "guest-user"),
         network: URLSession = .shared) {
        self.storage = storage
        self.guestStorage = guestStorage
        self.network = network
        do {
            session = try readStoredSession()
            updatePublishedSession()
        } catch {
            storageReadFailed = true
            status = error.localizedDescription
        }
    }

    func prepareGuestSession() async {
        do {
            _ = try await validAccessToken()
            await refreshUsage()
        } catch {
            status = "연결 실패: \(error.localizedDescription)"
        }
    }

    func signIn(email: String, password: String) async throws {
        guard !isWorking else { throw CompanionAuthError.server("인증 처리 중입니다. 잠시 후 다시 시도해 주세요.") }
        invalidatePendingRequest()
        let currentRevision = revision
        isWorking = true
        defer { isWorking = false }
        let response = try await sendFunction("login", body: ["email": email, "password": password])
        guard revision == currentRevision else { throw CompanionAuthError.loginRequired }
        try save(response)
        await refreshUsage()
    }

    func signInWithApple(idToken: String, nonce: String, fullName: String?) async throws {
        guard !isWorking else { throw CompanionAuthError.server("인증 처리 중입니다. 잠시 후 다시 시도해 주세요.") }
        invalidatePendingRequest()
        let currentRevision = revision
        isWorking = true
        defer { isWorking = false }
        var body = ["provider": "apple", "idToken": idToken, "nonce": nonce]
        if let fullName, !fullName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            body["fullName"] = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let response = try await sendFunction("login", body: body)
        guard revision == currentRevision else { throw CompanionAuthError.loginRequired }
        try save(response)
        await refreshUsage()
    }

    func signUp(email: String, password: String, nickname: String) async throws {
        guard !isWorking else { throw CompanionAuthError.server("인증 처리 중입니다. 잠시 후 다시 시도해 주세요.") }
        invalidatePendingRequest()
        let currentRevision = revision
        isWorking = true
        defer { isWorking = false }
        let response = try await sendFunction("signup", body: [
            "email": email, "password": password, "nickname": nickname, "language": "ko"
        ])
        guard revision == currentRevision else { throw CompanionAuthError.loginRequired }
        if response.accessToken != nil, response.refreshToken != nil {
            try save(response)
            await refreshUsage()
        } else {
            status = "가입되었습니다. 이메일 인증 후 로그인해 주세요."
        }
    }

    func validAccessToken(forceRefresh: Bool = false) async throws -> String {
        // A locked or corrupt Keychain is not proof that no previous identity exists.
        if storageReadFailed {
            session = try readStoredSession()
            storageReadFailed = false
            updatePublishedSession()
        }
        if !forceRefresh, let session, session.expiresAt.timeIntervalSinceNow > 60 { return session.accessToken }
        if let tokenTask { return try await tokenTask.value }
        let taskID = UUID()
        let currentRevision = revision
        let existing = session
        tokenTaskID = taskID
        isWorking = true
        let task = Task<String, Error> { [self] in
            defer {
                if tokenTaskID == taskID {
                    tokenTask = nil
                    tokenTaskID = nil
                    isWorking = false
                }
            }
            // An unavailable network never discards the old session or creates a new identity.
            let response: SupabaseAuthResponse
            if let existing {
                response = try await sendAuth("token?grant_type=refresh_token",
                    body: ["refresh_token": existing.refreshToken])
                guard response.user.id == existing.userId else { throw CompanionAuthError.invalidResponse }
            } else {
                response = try await sendAuth("signup", body: [:])
                guard response.user.isAnonymous else { throw CompanionAuthError.invalidResponse }
            }
            try Task.checkCancellation()
            guard revision == currentRevision else { throw CompanionAuthError.loginRequired }
            let record = StoredCompanionSession(userId: response.user.id, email: response.user.email,
                accessToken: response.accessToken, refreshToken: response.refreshToken,
                expiresAt: Date().addingTimeInterval(TimeInterval(response.expiresIn)),
                isAnonymous: response.user.isAnonymous, nickname: nil, isAdmin: false)
            try writeStoredSession(record)
            session = record
            updatePublishedSession()
            return record.accessToken
        }
        tokenTask = task
        return try await task.value
    }

    func signOut() async throws {
        guard session != nil, !isGuest, !isWorking else { return }
        // Revoke the current registered session before switching back to the same guest.
        let token = try await validAccessToken()
        let currentRevision = revision
        var request = URLRequest(url: SupabaseConfiguration.authURL.appendingPathComponent("logout")
            .appending(queryItems: [URLQueryItem(name: "scope", value: "local")]))
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue(SupabaseConfiguration.publicKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        isWorking = true
        defer { isWorking = false }
        let (_, response) = try await network.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw CompanionAuthError.invalidResponse }
        guard (200...299).contains(http.statusCode) || http.statusCode == 401 else {
            throw CompanionAuthError.server("로그아웃에 실패했습니다. 다시 시도해 주세요.")
        }
        guard revision == currentRevision else { throw CompanionAuthError.loginRequired }
        let guest = try guestStorage.read().map { try JSONDecoder().decode(StoredCompanionSession.self, from: $0) }
        if let guest {
            guard guest.isAnonymous == true else { throw CompanionAuthError.invalidResponse }
            try writeStoredSession(guest)
        } else {
            try storage.delete()
        }
        invalidatePendingRequest()
        session = guest
        usage = nil
        updatePublishedSession()
        await prepareGuestSession()
    }

    // Refresh once on a rejected access token, never on 429/5xx/timeouts.
    func authenticatedRequest(_ original: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let currentRevision = revision
        var token = try await validAccessToken()
        for attempt in 0...1 {
            var request = original
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue(SupabaseConfiguration.publicKey, forHTTPHeaderField: "apikey")
            let (data, response) = try await network.data(for: request)
            guard revision == currentRevision else { throw CompanionAuthError.loginRequired }
            guard let http = response as? HTTPURLResponse else { throw CompanionAuthError.invalidResponse }
            let errorCode = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["code"] as? String
            // Older ARCH deployments require the key issued to this same Auth user.
            // Read only our own RLS-protected profile; never mint or share a key.
            if http.statusCode == 401, errorCode == "API_KEY_REQUIRED" {
                guard let userID = session?.userId else { return (data, http) }
                var components = URLComponents(url: SupabaseConfiguration.projectURL.appendingPathComponent("rest/v1/profiles"), resolvingAgainstBaseURL: false)!
                components.queryItems = [URLQueryItem(name: "select", value: "api_key"),
                                        URLQueryItem(name: "id", value: "eq.\(userID)"),
                                        URLQueryItem(name: "limit", value: "1")]
                var profileRequest = URLRequest(url: components.url!)
                profileRequest.timeoutInterval = 15
                profileRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                profileRequest.setValue(SupabaseConfiguration.publicKey, forHTTPHeaderField: "apikey")
                let (profileData, profileResponse) = try await network.data(for: profileRequest)
                guard revision == currentRevision else { throw CompanionAuthError.loginRequired }
                guard let profileHTTP = profileResponse as? HTTPURLResponse,
                      (200...299).contains(profileHTTP.statusCode),
                      let rows = try? JSONSerialization.jsonObject(with: profileData) as? [[String: Any]],
                      let ownKey = rows.first?["api_key"] as? String,
                      ownKey.hasPrefix("arch_live_") else {
                    throw CompanionAuthError.server("게스트 인증은 준비됐지만 서버가 요구하는 본인 API 키를 조회하지 못했습니다. profiles 자동 발급 및 본인 조회 정책 확인이 필요합니다.")
                }
                var compatibleRequest = request
                compatibleRequest.setValue(ownKey, forHTTPHeaderField: "x-api-key")
                let (compatibleData, compatibleResponse) = try await network.data(for: compatibleRequest)
                guard revision == currentRevision else { throw CompanionAuthError.loginRequired }
                guard let compatibleHTTP = compatibleResponse as? HTTPURLResponse else {
                    throw CompanionAuthError.invalidResponse
                }
                if let snapshot = CompanionUsage(response: compatibleHTTP) {
                    usage = snapshot
                    usageStatus = snapshot.summary
                }
                return (compatibleData, compatibleHTTP)
            }
            if http.statusCode == 401, attempt == 0 {
                // Another request may already have refreshed this access token.
                if let current = session, current.accessToken != token {
                    token = try await validAccessToken()
                } else {
                    token = try await validAccessToken(forceRefresh: true)
                }
                continue
            }
            if let snapshot = CompanionUsage(response: http) {
                usage = snapshot
                usageStatus = snapshot.summary
            }
            return (data, http)
        }
        throw CompanionAuthError.invalidResponse
    }

    @discardableResult
    func refreshUsage() async -> Bool {
        let currentRevision = revision
        do {
            var request = URLRequest(url: SupabaseConfiguration.functionsURL.appendingPathComponent("usage"))
            request.timeoutInterval = 15
            let (data, http) = try await authenticatedRequest(request)
            guard (200...299).contains(http.statusCode) else {
                throw CompanionAuthError.server("사용량 확인 실패 (HTTP \(http.statusCode))")
            }
            let snapshot = try JSONDecoder().decode(CompanionUsage.self, from: data)
            guard revision == currentRevision else { return false }
            usage = snapshot
            usageStatus = snapshot.summary
            return true
        } catch {
            guard revision == currentRevision else { return false }
            usageStatus = "사용량을 확인할 수 없습니다. 잠시 후 다시 시도해 주세요."
            return false
        }
    }

    private func invalidatePendingRequest() {
        revision = UUID()
        tokenTask?.cancel()
        tokenTask = nil
        tokenTaskID = nil
        isWorking = false
    }

    private func updatePublishedSession() {
        email = session?.email
        isGuest = session?.isAnonymous == true
        nickname = session?.nickname
        isAdmin = session?.isAdmin == true
        status = session == nil ? "게스트 연결 준비 중" : (isGuest ? "게스트로 사용 중" : "로그인됨")
    }

    private func save(_ response: AuthResponse) throws {
        guard let userId = response.userId, let accessToken = response.accessToken,
              let refreshToken = response.refreshToken else { throw CompanionAuthError.invalidResponse }
        let record = StoredCompanionSession(userId: userId, email: response.email,
            accessToken: accessToken, refreshToken: refreshToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(response.accessExpiresIn ?? 3600)),
            isAnonymous: response.isAnonymous ?? false,
            nickname: response.nickname, isAdmin: response.isAdmin ?? false)
        // Returning from account login must not create a fresh guest budget.
        if let guest = session, guest.isAnonymous == true {
            try guestStorage.write(JSONEncoder().encode(guest))
        }
        try writeStoredSession(record)
        session = record
        usage = nil
        usageStatus = "사용량 확인 중"
        updatePublishedSession()
    }

    private func sendAuth(_ path: String, body: [String: String]) async throws -> SupabaseAuthResponse {
        guard let url = URL(string: "\(SupabaseConfiguration.authURL.absoluteString)/\(path)") else {
            throw CompanionAuthError.invalidResponse
        }
        let data = try await sendRequest(url: url, body: body)
        return try JSONDecoder().decode(SupabaseAuthResponse.self, from: data)
    }

    private func sendFunction(_ function: String, body: [String: String]) async throws -> AuthResponse {
        let data = try await sendRequest(url: SupabaseConfiguration.functionsURL.appendingPathComponent(function), body: body)
        let response = try JSONDecoder().decode(AuthResponse.self, from: data)
        guard response.success else { throw CompanionAuthError.server(response.message ?? "인증 요청에 실패했습니다.") }
        return response
    }

    private func sendRequest(url: URL, body: [String: String]) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(SupabaseConfiguration.publicKey, forHTTPHeaderField: "apikey")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await network.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw CompanionAuthError.invalidResponse }
        guard (200...299).contains(http.statusCode) else {
            let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let message = object?["msg"] as? String ?? object?["message"] as? String
                ?? object?["error_description"] as? String ?? "인증 요청 실패 (HTTP \(http.statusCode))"
            throw CompanionAuthError.server(message)
        }
        return data
    }

    private func readStoredSession() throws -> StoredCompanionSession? {
        guard let data = try storage.read() else { return nil }
        return try JSONDecoder().decode(StoredCompanionSession.self, from: data)
    }

    private func writeStoredSession(_ record: StoredCompanionSession) throws {
        try storage.write(JSONEncoder().encode(record))
    }

}

protocol CompanionSessionStorage {
    func read() throws -> Data?
    func write(_ data: Data) throws
    func delete() throws
}

struct KeychainCompanionSessionStorage: CompanionSessionStorage {
    var account = "current-user"
    private func baseQuery() -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "com.personalteam.XRCH.supabase-session",
         kSecAttrAccount as String: account]
    }

    func read() throws -> Data? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw CompanionAuthError.keychain(status)
        }
        return data
    }

    func write(_ data: Data) throws {
        let query = baseQuery()
        let attributes: [String: Any] = [kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let updated = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updated == errSecSuccess { return }
        guard updated == errSecItemNotFound else { throw CompanionAuthError.keychain(updated) }
        var newQuery = query
        newQuery.merge(attributes) { _, new in new }
        let status = SecItemAdd(newQuery as CFDictionary, nil)
        guard status == errSecSuccess else { throw CompanionAuthError.keychain(status) }
    }

    func delete() throws {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw CompanionAuthError.keychain(status)
        }
    }
}
