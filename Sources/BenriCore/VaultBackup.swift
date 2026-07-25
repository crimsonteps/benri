import Foundation

public struct VaultBackupManifest: Codable, Equatable, Sendable {
    public static let currentFormatVersion = 1

    public let formatVersion: Int
    public let appVersion: String
    public let createdAt: Date
    public let vaultFormatVersion: Int
    public let categoryCount: Int
    public let recordCount: Int

    public init(
        formatVersion: Int = VaultBackupManifest.currentFormatVersion,
        appVersion: String,
        createdAt: Date = Date(),
        vaultFormatVersion: Int,
        categoryCount: Int,
        recordCount: Int
    ) {
        self.formatVersion = formatVersion
        self.appVersion = appVersion
        self.createdAt = createdAt
        self.vaultFormatVersion = vaultFormatVersion
        self.categoryCount = categoryCount
        self.recordCount = recordCount
    }
}

public struct ValidatedVaultBackup: Equatable, Sendable {
    public let manifest: VaultBackupManifest
    public let payload: VaultPayload

    public init(manifest: VaultBackupManifest, payload: VaultPayload) {
        self.manifest = manifest
        self.payload = payload
    }
}

public enum VaultBackupError: Error, LocalizedError, Equatable {
    case missingVault
    case missingKey
    case invalidPackage
    case unsupportedFormat(Int)
    case restoreFailed

    public var errorDescription: String? {
        switch self {
        case .missingVault:
            return "没有找到可备份的保险库文件。"
        case .missingKey:
            return "没有找到与保险库匹配的本地密钥。"
        case .invalidPackage:
            return "这个 Benri 备份无效、已损坏或密钥不匹配。"
        case let .unsupportedFormat(version):
            return "当前版本无法读取格式版本为 \(version) 的 Benri 备份。"
        case .restoreFailed:
            return "恢复保险库失败，原有数据已尽可能保留。"
        }
    }
}

public enum VaultBackupArchive {
    public static let fileExtension = "benribackup"

    private static let manifestFileName = "manifest.json"
    private static let vaultFileName = "vault.qv"
    private static let keyFileName = "vault.key"

    @discardableResult
    public static func create(
        at destinationURL: URL,
        vaultFileURL: URL,
        keyFileURL: URL,
        appVersion: String,
        createdAt: Date = Date(),
        fileManager: FileManager = .default
    ) throws -> VaultBackupManifest {
        guard fileManager.fileExists(atPath: vaultFileURL.path) else {
            throw VaultBackupError.missingVault
        }
        guard fileManager.fileExists(atPath: keyFileURL.path) else {
            throw VaultBackupError.missingKey
        }

        let vaultData = try Data(contentsOf: vaultFileURL)
        let keyData = try Data(contentsOf: keyFileURL)
        guard keyData.count == 32 else { throw VaultBackupError.invalidPackage }

        let payload: VaultPayload
        do {
            payload = try VaultCrypto.decrypt(vaultData, keyData: keyData)
        } catch {
            throw VaultBackupError.invalidPackage
        }

        let manifest = VaultBackupManifest(
            appVersion: appVersion,
            createdAt: createdAt,
            vaultFormatVersion: payload.formatVersion,
            categoryCount: payload.categories.count,
            recordCount: payload.records.count
        )
        let parentDirectory = destinationURL.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: parentDirectory,
            withIntermediateDirectories: true
        )

        let stagingURL = parentDirectory.appendingPathComponent(
            ".BenriBackup-\(UUID().uuidString)",
            isDirectory: true
        )
        let displacedURL = parentDirectory.appendingPathComponent(
            ".BenriBackupPrevious-\(UUID().uuidString)",
            isDirectory: true
        )

        do {
            try createPrivateDirectory(stagingURL, fileManager: fileManager)
            try writePrivate(
                vaultData,
                to: stagingURL.appendingPathComponent(vaultFileName),
                fileManager: fileManager
            )
            try writePrivate(
                keyData,
                to: stagingURL.appendingPathComponent(keyFileName),
                fileManager: fileManager
            )

            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try writePrivate(
                try encoder.encode(manifest),
                to: stagingURL.appendingPathComponent(manifestFileName),
                fileManager: fileManager
            )

            let destinationExists = fileManager.fileExists(atPath: destinationURL.path)
            if destinationExists {
                try fileManager.moveItem(at: destinationURL, to: displacedURL)
            }

            do {
                try fileManager.moveItem(at: stagingURL, to: destinationURL)
                if destinationExists {
                    try? fileManager.removeItem(at: displacedURL)
                }
            } catch {
                if destinationExists,
                   !fileManager.fileExists(atPath: destinationURL.path),
                   fileManager.fileExists(atPath: displacedURL.path) {
                    try? fileManager.moveItem(at: displacedURL, to: destinationURL)
                }
                throw error
            }
        } catch {
            try? fileManager.removeItem(at: stagingURL)
            throw error
        }

        return manifest
    }

    public static func validate(
        at backupURL: URL,
        fileManager: FileManager = .default
    ) throws -> ValidatedVaultBackup {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: backupURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else { throw VaultBackupError.invalidPackage }

        let manifestURL = backupURL.appendingPathComponent(manifestFileName)
        let vaultURL = backupURL.appendingPathComponent(vaultFileName)
        let keyURL = backupURL.appendingPathComponent(keyFileName)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let manifest: VaultBackupManifest
        do {
            manifest = try decoder.decode(
                VaultBackupManifest.self,
                from: Data(contentsOf: manifestURL)
            )
        } catch {
            throw VaultBackupError.invalidPackage
        }

        guard manifest.formatVersion <= VaultBackupManifest.currentFormatVersion else {
            throw VaultBackupError.unsupportedFormat(manifest.formatVersion)
        }

        let keyData: Data
        let vaultData: Data
        do {
            keyData = try Data(contentsOf: keyURL)
            vaultData = try Data(contentsOf: vaultURL)
        } catch {
            throw VaultBackupError.invalidPackage
        }
        guard keyData.count == 32 else { throw VaultBackupError.invalidPackage }

        let payload: VaultPayload
        do {
            payload = try VaultCrypto.decrypt(vaultData, keyData: keyData)
        } catch {
            throw VaultBackupError.invalidPackage
        }

        guard payload.formatVersion == manifest.vaultFormatVersion,
              payload.categories.count == manifest.categoryCount,
              payload.records.count == manifest.recordCount
        else { throw VaultBackupError.invalidPackage }

        return ValidatedVaultBackup(manifest: manifest, payload: payload)
    }

    @discardableResult
    public static func restore(
        _ validatedBackup: ValidatedVaultBackup,
        to destinationStore: VaultFileStore
    ) throws -> VaultPayload {
        var payload = validatedBackup.payload
        payload.migrateToCurrentFormat()
        do {
            try destinationStore.save(payload)
            guard try destinationStore.load() == payload else {
                throw VaultBackupError.restoreFailed
            }
        } catch {
            if let restoredPayload = try? destinationStore.load(),
               restoredPayload == payload {
                return payload
            }
            throw VaultBackupError.restoreFailed
        }

        return payload
    }

    private static func createPrivateDirectory(
        _ directory: URL,
        fileManager: FileManager
    ) throws {
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try fileManager.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: directory.path
        )
    }

    private static func writePrivate(
        _ data: Data,
        to fileURL: URL,
        fileManager: FileManager
    ) throws {
        try createPrivateDirectory(
            fileURL.deletingLastPathComponent(),
            fileManager: fileManager
        )
        try data.write(to: fileURL, options: [.atomic])
        try fileManager.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: fileURL.path
        )
    }
}
