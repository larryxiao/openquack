import Foundation
import Security

/// SPEC-044 — secret storage for remote endpoints, keyed by host. Keying by
/// host (not by profile) is the security invariant: a request can only ever be
/// sent the credential saved for the host it targets.
public protocol CredentialStore: Sendable {
    func secret(forHost host: String) -> String?
    func setSecret(_ secret: String?, forHost host: String)
}

/// Keychain-backed store. One generic-password item per host.
public struct KeychainCredentialStore: CredentialStore {
    public static let service = "org.openquack.remote-endpoint"

    public init() {}

    public func secret(forHost host: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: host,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func setSecret(_ secret: String?, forHost host: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: host,
        ]
        SecItemDelete(base as CFDictionary)
        guard let secret, !secret.isEmpty else { return }
        var add = base
        add[kSecValueData as String] = Data(secret.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }
}
