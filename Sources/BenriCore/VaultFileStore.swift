import Darwin
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
        let stagingURL = directory.appendingPathComponent(
            ".\(fileURL.lastPathComponent).\(UUID().uuidString).tmp"
        )
        defer { try? FileManager.default.removeItem(at: stagingURL) }

        try encryptedData.write(to: stagingURL)
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

    public func remove() throws {
        guard exists else { return }
        try FileManager.default.removeItem(at: fileURL)
    }
}
