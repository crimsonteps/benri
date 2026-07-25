import Foundation

public enum LegacyInstallationMigrationOutcome: Equatable, Sendable {
    case noLegacyVault
    case currentVaultAlreadyExists
    case migrated(backupURL: URL)
}

public enum LegacyInstallationMigrationError: Error, LocalizedError, Equatable, Sendable {
    case destinationDirectoryAlreadyExists
    case missingLegacyKey
    case invalidLegacyKey
    case verificationFailed
    case legacySourceChanged
    case legacyCleanupFailed(String)

    public var errorDescription: String? {
        switch self {
        case .destinationDirectoryAlreadyExists:
            return "Benri 数据目录已存在，但其中没有保险库。为避免覆盖现有文件，旧数据未迁移。"
        case .missingLegacyKey:
            return "找到了旧 QuickVault 保险库，但没有找到对应的解密密钥。"
        case .invalidLegacyKey:
            return "旧 QuickVault 保险库的解密密钥无效。"
        case .verificationFailed:
            return "旧 QuickVault 保险库迁移后的数据校验失败。"
        case .legacySourceChanged:
            return "迁移期间旧 QuickVault 保险库仍在使用或发生了变化。旧数据未删除，请退出旧版后重试。"
        case let .legacyCleanupFailed(reason):
            return "旧数据已迁移到 Benri，但无法删除 QuickVault 数据目录：\(reason)"
        }
    }
}

public enum LegacyInstallationMigrator {
    public static func migrateIfNeeded(
        legacyDirectoryURL: URL,
        destinationDirectoryURL: URL,
        appVersion: String,
        legacyKeychainKey: () throws -> Data?,
        legacySourceIsInactive: () -> Bool = { true },
        now: Date = Date(),
        fileManager: FileManager = .default
    ) throws -> LegacyInstallationMigrationOutcome {
        let destinationVaultURL = destinationDirectoryURL.appendingPathComponent("vault.qv")
        if fileManager.fileExists(atPath: destinationVaultURL.path) {
            return .currentVaultAlreadyExists
        }

        if fileManager.fileExists(atPath: destinationDirectoryURL.path) {
            throw LegacyInstallationMigrationError.destinationDirectoryAlreadyExists
        }

        let legacyVaultURL = legacyDirectoryURL.appendingPathComponent("vault.qv")
        guard fileManager.fileExists(atPath: legacyVaultURL.path) else {
            return .noLegacyVault
        }
        let legacyVaultData = try Data(contentsOf: legacyVaultURL)

        let legacyKeyURL = legacyDirectoryURL.appendingPathComponent("vault.key")
        let legacyKeyFileExisted = fileManager.fileExists(atPath: legacyKeyURL.path)
        let keyData: Data
        if legacyKeyFileExisted {
            keyData = try Data(contentsOf: legacyKeyURL)
        } else {
            guard let keychainKey = try legacyKeychainKey() else {
                throw LegacyInstallationMigrationError.missingLegacyKey
            }
            keyData = keychainKey
        }
        guard keyData.count == 32 else {
            throw LegacyInstallationMigrationError.invalidLegacyKey
        }

        let legacyPayload = try VaultCrypto.decrypt(legacyVaultData, keyData: keyData)
        var migratedPayload = legacyPayload
        migratedPayload.migrateToCurrentFormat()

        let destinationParentURL = destinationDirectoryURL.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: destinationParentURL,
            withIntermediateDirectories: true
        )
        let stagingDirectoryURL = destinationParentURL.appendingPathComponent(
            ".BenriMigration-\(UUID().uuidString)",
            isDirectory: true
        )
        var committed = false
        defer {
            if !committed,
               fileManager.fileExists(atPath: stagingDirectoryURL.path) {
                try? fileManager.removeItem(at: stagingDirectoryURL)
            }
        }

        try createPrivateDirectory(stagingDirectoryURL, fileManager: fileManager)
        let stagingKeyURL = stagingDirectoryURL.appendingPathComponent("vault.key")
        try writePrivate(keyData, to: stagingKeyURL, fileManager: fileManager)

        let backupsDirectoryURL = stagingDirectoryURL.appendingPathComponent(
            "Backups",
            isDirectory: true
        )
        try createPrivateDirectory(backupsDirectoryURL, fileManager: fileManager)
        let backupFileName = "Before Benri migration \(backupTimestamp(now)).\(VaultBackupArchive.fileExtension)"
        let stagingBackupURL = backupsDirectoryURL.appendingPathComponent(
            backupFileName,
            isDirectory: true
        )
        try VaultBackupArchive.create(
            at: stagingBackupURL,
            vaultFileURL: legacyVaultURL,
            keyFileURL: stagingKeyURL,
            appVersion: appVersion,
            createdAt: now,
            fileManager: fileManager
        )
        let validatedBackup = try VaultBackupArchive.validate(
            at: stagingBackupURL,
            fileManager: fileManager
        )
        guard validatedBackup.payload == legacyPayload else {
            throw LegacyInstallationMigrationError.verificationFailed
        }

        let stagingVaultURL = stagingDirectoryURL.appendingPathComponent("vault.qv")
        try VaultFileStore(fileURL: stagingVaultURL, keyData: keyData).save(migratedPayload)
        try verifyInstallation(
            directoryURL: stagingDirectoryURL,
            expectedKey: keyData,
            expectedPayload: migratedPayload,
            backupURL: stagingBackupURL,
            expectedBackupPayload: legacyPayload,
            fileManager: fileManager
        )
        guard legacySourceIsInactive(),
              try legacySourceIsUnchanged(
                vaultURL: legacyVaultURL,
                expectedVaultData: legacyVaultData,
                keyURL: legacyKeyURL,
                keyFileExisted: legacyKeyFileExisted,
                expectedKeyData: keyData,
                fileManager: fileManager
              )
        else { throw LegacyInstallationMigrationError.legacySourceChanged }

        try fileManager.moveItem(at: stagingDirectoryURL, to: destinationDirectoryURL)
        committed = true

        let finalBackupURL = destinationDirectoryURL
            .appendingPathComponent("Backups", isDirectory: true)
            .appendingPathComponent(backupFileName, isDirectory: true)
        do {
            try verifyInstallation(
                directoryURL: destinationDirectoryURL,
                expectedKey: keyData,
                expectedPayload: migratedPayload,
                backupURL: finalBackupURL,
                expectedBackupPayload: legacyPayload,
                fileManager: fileManager
            )
            guard legacySourceIsInactive(),
                  try legacySourceIsUnchanged(
                    vaultURL: legacyVaultURL,
                    expectedVaultData: legacyVaultData,
                    keyURL: legacyKeyURL,
                    keyFileExisted: legacyKeyFileExisted,
                    expectedKeyData: keyData,
                    fileManager: fileManager
                  )
            else { throw LegacyInstallationMigrationError.legacySourceChanged }
        } catch {
            try? fileManager.removeItem(at: destinationDirectoryURL)
            committed = false
            throw error
        }

        let cleanupDirectoryURL = legacyDirectoryURL
            .deletingLastPathComponent()
            .appendingPathComponent(
                ".QuickVaultMigrated-\(UUID().uuidString)",
                isDirectory: true
            )
        var legacyDirectoryWasMoved = false
        do {
            try fileManager.moveItem(at: legacyDirectoryURL, to: cleanupDirectoryURL)
            legacyDirectoryWasMoved = true
            let cleanupVaultURL = cleanupDirectoryURL.appendingPathComponent("vault.qv")
            let cleanupKeyURL = cleanupDirectoryURL.appendingPathComponent("vault.key")
            guard legacySourceIsInactive(),
                  !fileManager.fileExists(atPath: legacyDirectoryURL.path),
                  try legacySourceIsUnchanged(
                    vaultURL: cleanupVaultURL,
                    expectedVaultData: legacyVaultData,
                    keyURL: cleanupKeyURL,
                    keyFileExisted: legacyKeyFileExisted,
                    expectedKeyData: keyData,
                    fileManager: fileManager
                  )
            else { throw LegacyInstallationMigrationError.legacySourceChanged }
            guard try containsOnlyKnownLegacyFiles(
                cleanupDirectoryURL,
                fileManager: fileManager
            ) else {
                throw LegacyInstallationMigrationError.legacyCleanupFailed(
                    "目录中包含 vault.qv、vault.key 之外的文件，Benri 已保留该目录以避免误删。"
                )
            }
            try fileManager.removeItem(at: cleanupDirectoryURL)
        } catch let error as LegacyInstallationMigrationError {
            if legacyDirectoryWasMoved,
               !fileManager.fileExists(atPath: legacyDirectoryURL.path),
               fileManager.fileExists(atPath: cleanupDirectoryURL.path) {
                try? fileManager.moveItem(
                    at: cleanupDirectoryURL,
                    to: legacyDirectoryURL
                )
            }
            if case .legacySourceChanged = error {
                try? fileManager.removeItem(at: destinationDirectoryURL)
                committed = false
                throw error
            }
            throw error
        } catch {
            if legacyDirectoryWasMoved,
               !fileManager.fileExists(atPath: legacyDirectoryURL.path),
               fileManager.fileExists(atPath: cleanupDirectoryURL.path) {
                try? fileManager.moveItem(
                    at: cleanupDirectoryURL,
                    to: legacyDirectoryURL
                )
            }
            throw LegacyInstallationMigrationError.legacyCleanupFailed(
                error.localizedDescription
            )
        }

        return .migrated(backupURL: finalBackupURL)
    }

    private static func containsOnlyKnownLegacyFiles(
        _ directoryURL: URL,
        fileManager: FileManager
    ) throws -> Bool {
        let knownFileNames: Set<String> = ["vault.qv", "vault.key", ".DS_Store"]
        let contents = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil
        )
        return contents.allSatisfy { knownFileNames.contains($0.lastPathComponent) }
    }

    private static func legacySourceIsUnchanged(
        vaultURL: URL,
        expectedVaultData: Data,
        keyURL: URL,
        keyFileExisted: Bool,
        expectedKeyData: Data,
        fileManager: FileManager
    ) throws -> Bool {
        guard fileManager.fileExists(atPath: vaultURL.path),
              try Data(contentsOf: vaultURL) == expectedVaultData
        else { return false }

        let keyFileExistsNow = fileManager.fileExists(atPath: keyURL.path)
        guard keyFileExistsNow == keyFileExisted else { return false }
        if keyFileExisted {
            return try Data(contentsOf: keyURL) == expectedKeyData
        }
        return true
    }

    private static func verifyInstallation(
        directoryURL: URL,
        expectedKey: Data,
        expectedPayload: VaultPayload,
        backupURL: URL,
        expectedBackupPayload: VaultPayload,
        fileManager: FileManager
    ) throws {
        let keyURL = directoryURL.appendingPathComponent("vault.key")
        let vaultURL = directoryURL.appendingPathComponent("vault.qv")
        let installedKey = try Data(contentsOf: keyURL)
        guard installedKey == expectedKey else {
            throw LegacyInstallationMigrationError.verificationFailed
        }

        let installedPayload = try VaultFileStore(
            fileURL: vaultURL,
            keyData: installedKey
        ).load()
        guard installedPayload == expectedPayload else {
            throw LegacyInstallationMigrationError.verificationFailed
        }

        let validatedBackup = try VaultBackupArchive.validate(
            at: backupURL,
            fileManager: fileManager
        )
        guard validatedBackup.payload == expectedBackupPayload else {
            throw LegacyInstallationMigrationError.verificationFailed
        }
    }

    private static func createPrivateDirectory(
        _ directoryURL: URL,
        fileManager: FileManager
    ) throws {
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try fileManager.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: directoryURL.path
        )
    }

    private static func writePrivate(
        _ data: Data,
        to fileURL: URL,
        fileManager: FileManager
    ) throws {
        try data.write(to: fileURL, options: [.atomic])
        try fileManager.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: fileURL.path
        )
    }

    private static func backupTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss.SSS"
        return formatter.string(from: date)
    }
}
