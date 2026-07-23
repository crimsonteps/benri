import Foundation

enum VaultStorage {
    static func defaultVaultFileURL(
        fileManager: FileManager = .default
    ) -> URL {
        applicationSupportDirectory(fileManager: fileManager)
            .appendingPathComponent("Benri", isDirectory: true)
            .appendingPathComponent("vault.qv")
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
