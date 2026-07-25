import Foundation

enum VaultStorage {
    static let legacyBundleIdentifier = "com.crimsonteps.quickvault"

    static func defaultVaultFileURL(
        fileManager: FileManager = .default
    ) -> URL {
        applicationSupportDirectory(fileManager: fileManager)
            .appendingPathComponent("Benri", isDirectory: true)
            .appendingPathComponent("vault.qv")
    }

    static func legacyDirectoryURL(
        fileManager: FileManager = .default
    ) -> URL {
        applicationSupportDirectory(fileManager: fileManager)
            .appendingPathComponent("QuickVault", isDirectory: true)
    }

    static func lockDirectoryURL(
        fileManager: FileManager = .default
    ) -> URL {
        applicationSupportDirectory(fileManager: fileManager)
            .appendingPathComponent(".BenriLocks", isDirectory: true)
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
