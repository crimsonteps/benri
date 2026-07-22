import Foundation
import OSLog

private let vaultStorageLogger = Logger(
    subsystem: "com.crimsonteps.quickvault",
    category: "Storage"
)

private enum VaultStorageMigrationError: Error, LocalizedError {
    case verificationFailed(String)

    var errorDescription: String? {
        switch self {
        case let .verificationFailed(fileName):
            return "迁移后的 \(fileName) 与原文件不一致。"
        }
    }
}

struct PreparedVaultStorage {
    let vaultFileURL: URL
    let legacyDirectoryToRemove: URL?
}

enum VaultStorage {
    static func defaultVaultFileURL(
        fileManager: FileManager = .default
    ) -> URL {
        applicationSupportDirectory(fileManager: fileManager)
            .appendingPathComponent("Benri", isDirectory: true)
            .appendingPathComponent("vault.qv")
    }

    static func prepareDefaultLocation(
        fileManager: FileManager = .default
    ) -> PreparedVaultStorage {
        let applicationSupport = applicationSupportDirectory(fileManager: fileManager)
        let vaultFileURL = defaultVaultFileURL(fileManager: fileManager)
        let vaultDirectory = vaultFileURL.deletingLastPathComponent()
        let legacyDirectory = applicationSupport
            .appendingPathComponent("QuickVault", isDirectory: true)
        let legacyVaultFileURL = legacyDirectory.appendingPathComponent("vault.qv")

        guard
            !fileManager.fileExists(atPath: vaultFileURL.path),
            fileManager.fileExists(atPath: legacyVaultFileURL.path)
        else {
            return PreparedVaultStorage(
                vaultFileURL: vaultFileURL,
                legacyDirectoryToRemove: nil
            )
        }

        let legacyKeyFileURL = legacyDirectory.appendingPathComponent("vault.key")
        let keyFileURL = vaultDirectory.appendingPathComponent("vault.key")
        let directoryExisted = fileManager.fileExists(atPath: vaultDirectory.path)
        var copiedFiles: [URL] = []

        do {
            try fileManager.createDirectory(
                at: vaultDirectory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )

            try fileManager.copyItem(at: legacyVaultFileURL, to: vaultFileURL)
            copiedFiles.append(vaultFileURL)

            if fileManager.fileExists(atPath: legacyKeyFileURL.path) {
                try fileManager.copyItem(at: legacyKeyFileURL, to: keyFileURL)
                copiedFiles.append(keyFileURL)
            }

            try verifyCopy(
                from: legacyVaultFileURL,
                to: vaultFileURL,
                fileManager: fileManager
            )
            if fileManager.fileExists(atPath: legacyKeyFileURL.path) {
                try verifyCopy(
                    from: legacyKeyFileURL,
                    to: keyFileURL,
                    fileManager: fileManager
                )
            }

            try fileManager.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: vaultDirectory.path
            )
            for copiedFile in copiedFiles {
                try fileManager.setAttributes(
                    [.posixPermissions: 0o600],
                    ofItemAtPath: copiedFile.path
                )
            }

            vaultStorageLogger.info("Copied legacy QuickVault storage into Benri")
            return PreparedVaultStorage(
                vaultFileURL: vaultFileURL,
                legacyDirectoryToRemove: legacyDirectory
            )
        } catch {
            for copiedFile in copiedFiles.reversed() {
                try? fileManager.removeItem(at: copiedFile)
            }
            if !directoryExisted {
                try? fileManager.removeItem(at: vaultDirectory)
            }
            vaultStorageLogger.error(
                "Legacy storage migration failed: \(error.localizedDescription, privacy: .public)"
            )
            return PreparedVaultStorage(
                vaultFileURL: legacyVaultFileURL,
                legacyDirectoryToRemove: nil
            )
        }
    }

    static func removeLegacyDirectory(
        _ legacyDirectory: URL,
        fileManager: FileManager = .default
    ) {
        do {
            try fileManager.removeItem(at: legacyDirectory)
            vaultStorageLogger.info("Removed verified legacy QuickVault storage")
        } catch {
            vaultStorageLogger.error(
                "Unable to remove legacy storage: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    private static func verifyCopy(
        from sourceURL: URL,
        to destinationURL: URL,
        fileManager: FileManager
    ) throws {
        guard fileManager.contentsEqual(
            atPath: sourceURL.path,
            andPath: destinationURL.path
        ) else {
            throw VaultStorageMigrationError.verificationFailed(sourceURL.lastPathComponent)
        }
    }

    private static func applicationSupportDirectory(
        fileManager: FileManager
    ) -> URL {
        fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? fileManager.homeDirectoryForCurrentUser
    }
}
