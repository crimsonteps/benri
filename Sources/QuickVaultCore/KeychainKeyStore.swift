import Foundation
import Security

public enum KeychainError: Error, LocalizedError {
    case unexpectedStatus(OSStatus)
    case invalidData

    public var errorDescription: String? {
        switch self {
        case let .unexpectedStatus(status):
            return "无法访问本机钥匙串，错误码：\(status)。"
        case .invalidData:
            return "钥匙串中的保险库密钥无效。"
        }
    }
}

public struct KeychainKeyStore: Sendable {
    public let service: String
    public let account: String

    public init(
        service: String = "com.crimsonteps.quickvault",
        account: String = "vault-key"
    ) {
        self.service = service
        self.account = account
    }

    public func loadKey() throws -> Data? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard let data = result as? Data, data.count == 32 else {
                throw KeychainError.invalidData
            }
            return data
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.unexpectedStatus(status)
        }
    }

    public func loadOrCreateKey() throws -> Data {
        if let existing = try loadKey() {
            return existing
        }

        let keyData = VaultCrypto.generateKeyData()
        var query = baseQuery
        query[kSecValueData as String] = keyData
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
        return keyData
    }

    public func deleteKey() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any
        ]
    }
}
