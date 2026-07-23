import Foundation

public struct VaultFileStore: Sendable {
    public let fileURL: URL
    private let keyData: Data

    public init(fileURL: URL, keyData: Data) {
        self.fileURL = fileURL
        self.keyData = keyData
    }

    public var exists: Bool {
        FileManager.default.fileExists(atPath: fileURL.path)
    }

    public func load() throws -> VaultPayload {
        let encryptedData = try Data(contentsOf: fileURL)
        return try VaultCrypto.decrypt(encryptedData, keyData: keyData)
    }

    public func save(_ payload: VaultPayload) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )

        let encryptedData = try VaultCrypto.encrypt(payload, keyData: keyData)
        try encryptedData.write(to: fileURL, options: [.atomic])
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: fileURL.path
        )
    }

    public func remove() throws {
        guard exists else { return }
        try FileManager.default.removeItem(at: fileURL)
    }
}
