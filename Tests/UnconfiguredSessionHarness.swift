import Foundation

private final class EmptyStorage: CompanionSessionStorage {
    var writes = 0
    func read() throws -> Data? { nil }
    func write(_ data: Data) throws { writes += 1 }
    func delete() throws {}
}

private final class RejectNetwork: URLProtocol {
    static var requests = 0
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests += 1
        client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
    }
    override func stopLoading() {}
}

// Compile without AUTH_TESTING. A command-line executable has no configured app Info.plist.
@main
private struct UnconfiguredSessionHarness {
    @MainActor static func main() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [RejectNetwork.self]
        let network = URLSession(configuration: config)
        defer { network.invalidateAndCancel() }
        let storage = EmptyStorage()
        let auth = CompanionAuthSession(storage: storage, guestStorage: EmptyStorage(), network: network)
        guard SupabaseConfiguration.projectURL.host == "example.invalid" else {
            fatalError("Unconfigured application points to a live host")
        }
        do {
            _ = try await auth.validAccessToken()
            fatalError("Unconfigured authentication unexpectedly succeeded")
        } catch {
            guard RejectNetwork.requests == 0, storage.writes == 0 else {
                fatalError("Unconfigured authentication contacted the network or changed identity")
            }
        }
        do {
            try await auth.signIn(email: "test@example.invalid", password: "test-only")
            fatalError("Unconfigured account login unexpectedly succeeded")
        } catch {
            guard RejectNetwork.requests == 0, storage.writes == 0 else {
                fatalError("Unconfigured login contacted the network or changed identity")
            }
        }
        print("PASS missing configuration makes zero network requests and zero session writes")
    }
}
