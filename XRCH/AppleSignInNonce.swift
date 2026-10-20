import CryptoKit
import Foundation
import Security

enum AppleSignInNonce {
    private static let alphabet = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")

    static func makeRawNonce(length: Int = 32) throws -> String {
        guard length > 0 else { throw NonceError.invalidLength }
        var bytes = [UInt8](repeating: 0, count: length)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else { throw NonceError.randomGenerationFailed(status) }
        return String(bytes.map { alphabet[Int($0) % alphabet.count] })
    }

    static func sha256(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    enum NonceError: LocalizedError {
        case invalidLength
        case randomGenerationFailed(OSStatus)

        var errorDescription: String? {
            switch self {
            case .invalidLength: "Apple 로그인 nonce 길이가 올바르지 않습니다."
            case .randomGenerationFailed: "Apple 로그인 nonce를 안전하게 생성하지 못했습니다."
            }
        }
    }
}
