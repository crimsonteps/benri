import Darwin
import Foundation

public enum VaultKeyStoreError: Error, LocalizedError {
    case invalidData

    public var errorDescription: String? {
        switch self {
        case .invalidData:
            return "本地保险库密钥无效。"
        }
    }
}

public struct VaultKeyStore: Sendable {
    public let fileURL: URL
    private let legacyKeychain: KeychainKeyStore

    public init(
        fileURL: URL,
        legacyKeychain: KeychainKeyStore = KeychainKeyStore()
    ) {
        self.fileURL = fileURL
        self.legacyKeychain = legacyKeychain
    }

    public func loadKey() throws -> Data? {
        if FileManager.default.fileExists(atPath: fileURL.path) {
            let data = try Data(contentsOf: fileURL)
            guard data.count == 32 else { throw VaultKeyStoreError.invalidData }
            return data
        }

        guard let legacyKey = try legacyKeychain.loadKey() else { return nil }
        try save(legacyKey)
        return legacyKey
    }

    public func loadOrCreateKey() throws -> Data {
        if let existing = try loadKey() {
            return existing
        }

        let keyData = VaultCrypto.generateKeyData()
        try save(keyData)
        return keyData
    }

    public func loadOrCreateKeyForRestore() throws -> Data {
        do {
            if let existing = try loadKey() {
                return existing
            }
        } catch VaultKeyStoreError.invalidData {
            return try loadLegacyKeyOrCreateReplacement()
        } catch KeychainError.invalidData {
            return try createReplacementKey()
        }

        return try createReplacementKey()
    }

    public func deleteKey() throws {
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
        try legacyKeychain.deleteKey()
    }

    private func save(_ keyData: Data) throws {
        guard keyData.count == 32 else { throw VaultKeyStoreError.invalidData }

        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )

        let stagingURL = directory.appendingPathComponent(
            ".\(fileURL.lastPathComponent).\(UUID().uuidString).tmp"
        )
        defer { try? FileManager.default.removeItem(at: stagingURL) }

        try keyData.write(to: stagingURL)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: stagingURL.path
        )

        let renameResult = stagingURL.path.withCString { sourcePath in
            fileURL.path.withCString { destinationPath in
                Darwin.rename(sourcePath, destinationPath)
            }
        }
        guard renameResult == 0 else {
            let code = errno
            throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
        }
    }

    private func loadLegacyKeyOrCreateReplacement() throws -> Data {
        do {
            if let legacyKey = try legacyKeychain.loadKey() {
                try save(legacyKey)
                return legacyKey
            }
        } catch KeychainError.invalidData {
            return try createReplacementKey()
        }

        return try createReplacementKey()
    }

    private func createReplacementKey() throws -> Data {
        let keyData = VaultCrypto.generateKeyData()
        try save(keyData)
        return keyData
    }
}
