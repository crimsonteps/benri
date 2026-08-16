import CryptoKit
import Darwin
import Foundation
import BenriCore

private func runVaultLockHolderIfRequested() {
    let arguments = CommandLine.arguments
    guard arguments.count == 4, arguments[1] == "--hold-vault-lock" else { return }

    do {
        let lock = try VaultFileLock.acquire(
            forVaultAt: URL(fileURLWithPath: arguments[2]),
            lockDirectoryURL: URL(fileURLWithPath: arguments[3])
        )
        print("READY")
        fflush(stdout)
        withExtendedLifetime(lock) {
            while true {
                _ = Darwin.pause()
            }
        }
    } catch {
        fputs("LOCK_ERROR: \(error.localizedDescription)\n", stderr)
        exit(2)
    }
}

runVaultLockHolderIfRequested()

private struct CheckRunner {
    private(set) var failures = 0
    private(set) var checks = 0

    mutating func expect(_ condition: @autoclosure () -> Bool, _ name: String) {
        checks += 1
        if condition() {
            print("✓ \(name)")
        } else {
            failures += 1
            print("✗ \(name)")
        }
    }

    mutating func expectThrows(_ name: String, _ operation: () throws -> Void) {
        checks += 1
        do {
            try operation()
            failures += 1
            print("✗ \(name)")
        } catch {
            print("✓ \(name)")
        }
    }
}

private var runner = CheckRunner()
private let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)

private func encryptRawVaultJSON(_ json: Data, keyData: Data) throws -> Data {
    let sealedBox = try AES.GCM.seal(json, using: SymmetricKey(data: keyData))
    guard let combined = sealedBox.combined else {
        throw VaultCryptoError.invalidFile
    }

    var output = Data("QVLT".utf8)
    output.append(1)
    output.append(combined)
    return output
}

private func writePrivateTestData(_ data: Data, to fileURL: URL) throws {
    try FileManager.default.createDirectory(
        at: fileURL.deletingLastPathComponent(),
        withIntermediateDirectories: true,
        attributes: [.posixPermissions: 0o700]
    )
    try data.write(to: fileURL, options: [.atomic])
    try FileManager.default.setAttributes(
        [.posixPermissions: 0o600],
        ofItemAtPath: fileURL.path
    )
}

private func checkModelRoundTrip() throws {
    let record = VaultRecord(
        name: "测试服务器",
        categoryID: VaultDefaults.serverCategoryID,
        content: "账号: deploy\n密码: s3cret",
        contentType: .bash,
        createdAt: fixedDate,
        updatedAt: fixedDate
    )
    let payload = VaultPayload(records: [record])
    let key = VaultCrypto.generateKeyData()
    let encrypted = try VaultCrypto.encrypt(payload, keyData: key)
    let decoded = try VaultCrypto.decrypt(encrypted, keyData: key)
    runner.expect(decoded == payload, "模型加密编解码往返一致")
}

private func checkSearchAndCategories() {
    let payload = VaultPayload(records: [
        VaultRecord(
            name: "Zulu Server",
            categoryID: VaultDefaults.serverCategoryID,
            content: "备注: needle"
        ),
        VaultRecord(name: "Apple ID", categoryID: VaultDefaults.personalCategoryID),
        VaultRecord(name: "Alpha Server", categoryID: VaultDefaults.serverCategoryID)
    ])

    runner.expect(
        payload.filteredRecords(categoryID: nil, query: "Zulu").map(\.name) == ["Zulu Server"],
        "仅按记录名称搜索"
    )
    runner.expect(
        payload.filteredRecords(categoryID: nil, query: "needle").isEmpty,
        "正文内容不会进入搜索"
    )
    runner.expect(
        payload.filteredRecords(categoryID: VaultDefaults.serverCategoryID, query: "").map(\.name)
            == ["Alpha Server", "Zulu Server"],
        "分类过滤后按名称排序"
    )

    let customID = UUID()
    var mutablePayload = VaultPayload(
        categories: VaultDefaults.categories + [VaultCategory(id: customID, name: "项目", sortOrder: 4)],
        records: [VaultRecord(name: "内网", categoryID: customID)]
    )
    mutablePayload.deleteCustomCategory(id: customID)
    runner.expect(
        mutablePayload.records.first?.categoryID == VaultDefaults.otherCategoryID,
        "删除自定义分类时记录迁移到其他"
    )

    var builtInPayload = VaultPayload(records: [
        VaultRecord(name: "工作账号", categoryID: VaultDefaults.workCategoryID)
    ])
    let replacementCategoryID = builtInPayload.deleteCategory(id: VaultDefaults.workCategoryID)
    runner.expect(
        replacementCategoryID == VaultDefaults.otherCategoryID
            && !builtInPayload.categories.contains(where: {
                $0.id == VaultDefaults.workCategoryID
            })
            && builtInPayload.records.first?.categoryID == VaultDefaults.otherCategoryID,
        "内置分类也可删除并迁移记录"
    )
    runner.expect(
        !builtInPayload.migrateToCurrentFormat()
            && !builtInPayload.categories.contains(where: {
                $0.id == VaultDefaults.workCategoryID
            }),
        "当前格式保留用户主动删除的内置分类"
    )
}

private func checkLegacyMigration() throws {
    let legacyJSON = """
    {
      "formatVersion": 1,
      "categories": [],
      "records": [
        {
          "id": "10000000-0000-4000-8000-000000000001",
          "name": "旧记录",
          "categoryID": "00000000-0000-4000-8000-000000000001",
          "fields": [
            {"label": "账号", "value": "deploy", "isSensitive": false, "sortOrder": 0},
            {"label": "密码", "value": "s3cret", "isSensitive": true, "sortOrder": 1}
          ],
          "createdAt": 0,
          "updatedAt": 0
        }
      ]
    }
    """

    var payload = try JSONDecoder().decode(VaultPayload.self, from: Data(legacyJSON.utf8))
    runner.expect(
        payload.records.first?.content == "账号: deploy\n密码: s3cret",
        "旧字段自动合并为正文"
    )
    runner.expect(payload.records.first?.contentType == .text, "旧记录默认迁移为文本类型")
    runner.expect(payload.migrateToCurrentFormat(), "旧格式版本会执行迁移")
    runner.expect(payload.formatVersion == VaultPayload.currentFormatVersion, "迁移后格式版本正确")
    runner.expect(
        Set(payload.categories.map(\.id)) == Set(VaultDefaults.categories.map(\.id)),
        "迁移会恢复缺失的内置分类"
    )

    let customCategory = VaultCategory(name: "保留分类", sortOrder: 10)
    let renamedPersonalCategory = VaultCategory(
        id: VaultDefaults.personalCategoryID,
        name: "私人",
        sortOrder: 0,
        isBuiltIn: true
    )
    var partialCategoriesPayload = VaultPayload(
        formatVersion: 1,
        categories: [renamedPersonalCategory, customCategory]
    )
    _ = partialCategoriesPayload.migrateToCurrentFormat()
    let migratedPersonalCategory = partialCategoriesPayload.categories.first(where: {
        $0.id == VaultDefaults.personalCategoryID
    })
    runner.expect(
        migratedPersonalCategory?.name == renamedPersonalCategory.name
            && migratedPersonalCategory?.iconName == "person.crop.circle"
            && partialCategoriesPayload.categories.contains(customCategory)
            && partialCategoriesPayload.categories.count == VaultDefaults.categories.count + 1,
        "迁移保留已有分类名称并补齐内置图标"
    )

    var previousPayloadWithMissingCategories = VaultPayload(
        formatVersion: VaultPayload.currentFormatVersion - 1,
        categories: []
    )
    runner.expect(
        previousPayloadWithMissingCategories.migrateToCurrentFormat()
            && previousPayloadWithMissingCategories.categories == VaultDefaults.categories,
        "旧版本升级时补回缺失的内置分类和图标"
    )

    var currentPayloadWithMissingCategories = VaultPayload(categories: [])
    runner.expect(
        !currentPayloadWithMissingCategories.migrateToCurrentFormat()
            && currentPayloadWithMissingCategories.categories.isEmpty,
        "当前格式不会恢复用户主动删除的分类"
    )
    runner.expect(!payload.migrateToCurrentFormat(), "完整当前格式无需重复迁移")

    let encoded = try JSONEncoder().encode(payload)
    let encodedText = String(decoding: encoded, as: UTF8.self)
    runner.expect(!encodedText.contains("\"fields\""), "新格式不再保存字段数组")
    runner.expect(encodedText.contains("\"contentType\""), "新格式保存内容类型")
    runner.expect(encodedText.contains("\"iconName\""), "新格式保存分类图标")
}

private func checkCrypto() throws {
    let secret = "do-not-store-this-in-plaintext"
    let payload = VaultPayload(records: [
        VaultRecord(
            name: "测试账号",
            categoryID: VaultDefaults.personalCategoryID,
            content: secret,
            createdAt: fixedDate,
            updatedAt: fixedDate
        )
    ])
    let key = VaultCrypto.generateKeyData()
    let encrypted = try VaultCrypto.encrypt(payload, keyData: key)

    runner.expect(encrypted.range(of: Data(secret.utf8)) == nil, "加密文件不包含字段明文")
    runner.expectThrows("错误密钥无法解密") {
        _ = try VaultCrypto.decrypt(encrypted, keyData: VaultCrypto.generateKeyData())
    }
    runner.expectThrows("普通文本不能伪装成保险库") {
        _ = try VaultCrypto.decrypt(Data("plain json".utf8), keyData: key)
    }

    runner.expectThrows("不会写入高于当前版本的保险库格式") {
        let futurePayload = VaultPayload(
            formatVersion: VaultPayload.currentFormatVersion + 1
        )
        _ = try VaultCrypto.encrypt(futurePayload, keyData: key)
    }

    let futureJSON = """
    {
      "formatVersion": \(VaultPayload.currentFormatVersion + 1),
      "categories": [],
      "records": [
        {
          "contentType": "totp",
          "futureSecret": "must-not-be-downgraded"
        }
      ],
      "futureRoot": "must-not-be-lost"
    }
    """
    let encryptedFuturePayload = try encryptRawVaultJSON(
        Data(futureJSON.utf8),
        keyData: key
    )
    do {
        _ = try VaultCrypto.decrypt(encryptedFuturePayload, keyData: key)
        runner.expect(false, "读取高版本保险库时明确拒绝")
    } catch VaultCryptoError.unsupportedFormat {
        runner.expect(true, "读取高版本保险库时明确拒绝")
    } catch {
        runner.expect(false, "读取高版本保险库时明确拒绝")
    }
}

private func checkFileStore() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("BenriChecks-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let fileURL = directory.appendingPathComponent("vault.qv")
    let key = VaultCrypto.generateKeyData()
    let store = VaultFileStore(fileURL: fileURL, keyData: key)
    let payload = VaultPayload(records: [
        VaultRecord(
            name: "本地记录",
            categoryID: VaultDefaults.workCategoryID,
            createdAt: fixedDate,
            updatedAt: fixedDate
        )
    ])

    try store.save(payload)
    runner.expect(store.exists, "原子写入创建保险库文件")
    let loadedPayload = try store.load()
    runner.expect(loadedPayload == payload, "保险库文件可正确重新载入")

    let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
    runner.expect(
        attributes[.posixPermissions] as? NSNumber == NSNumber(value: 0o600),
        "保险库文件权限为 0600"
    )

    let originalData = try Data(contentsOf: fileURL)
    let wrongStore = VaultFileStore(fileURL: fileURL, keyData: VaultCrypto.generateKeyData())
    runner.expectThrows("解密失败不会被当作空保险库") {
        _ = try wrongStore.load()
    }
    let dataAfterFailedLoad = try Data(contentsOf: fileURL)
    runner.expect(dataAfterFailedLoad == originalData, "解密失败后原文件未被覆盖")
}

private func checkLocalKeyStore() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("quick-vault-key-check-\(UUID().uuidString)")
    let keyURL = directory.appendingPathComponent("vault.key")
    let keyStore = VaultKeyStore(
        fileURL: keyURL,
        legacyKeychain: KeychainKeyStore(
            service: "com.crimsonteps.benri.checks.\(UUID().uuidString)"
        )
    )

    defer { try? FileManager.default.removeItem(at: directory) }

    let createdKey = try keyStore.loadOrCreateKey()
    runner.expect(createdKey.count == 32, "本地密钥长度为 32 字节")
    let loadedKey = try keyStore.loadKey()
    runner.expect(loadedKey == createdKey, "本地密钥可重复读取")

    let attributes = try FileManager.default.attributesOfItem(atPath: keyURL.path)
    let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue
    runner.expect(permissions == 0o600, "本地密钥文件权限为 0600")

    try keyStore.deleteKey()
    runner.expect(!FileManager.default.fileExists(atPath: keyURL.path), "重置会删除本地密钥")

    let recoveryService = "com.crimsonteps.benri.checks.recovery.\(UUID().uuidString)"
    let recoveryKeychain = KeychainKeyStore(service: recoveryService)
    defer { try? recoveryKeychain.deleteKey() }
    let keychainRecoveryKey = try recoveryKeychain.loadOrCreateKey()
    try writePrivateTestData(Data(repeating: 0, count: 31), to: keyURL)
    let recoveryKeyStore = VaultKeyStore(
        fileURL: keyURL,
        legacyKeychain: recoveryKeychain
    )
    let recoveredKey = try recoveryKeyStore.loadOrCreateKeyForRestore()
    let recoveredKeyFileData = try Data(contentsOf: keyURL)
    runner.expect(
        recoveredKey == keychainRecoveryKey
            && recoveredKeyFileData == keychainRecoveryKey,
        "恢复时本地密钥损坏会优先复用钥匙串密钥"
    )

    let replacementService = "com.crimsonteps.benri.checks.replacement.\(UUID().uuidString)"
    let replacementKeyStore = VaultKeyStore(
        fileURL: keyURL,
        legacyKeychain: KeychainKeyStore(service: replacementService)
    )
    try writePrivateTestData(Data(repeating: 0, count: 31), to: keyURL)
    let replacementKey = try replacementKeyStore.loadOrCreateKeyForRestore()
    let replacementKeyFileData = try Data(contentsOf: keyURL)
    runner.expect(
        replacementKey.count == 32
            && replacementKeyFileData == replacementKey,
        "恢复时本地和钥匙串均无有效密钥才生成替代密钥"
    )
}

private func checkLegacyPreferencesMigration() {
    let legacyDomain = "com.crimsonteps.quickvault.checks.\(UUID().uuidString)"
    let destinationDomain = "com.crimsonteps.benri.checks.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: destinationDomain) else {
        runner.expect(false, "可创建隔离的偏好设置测试域")
        return
    }
    defer {
        defaults.removePersistentDomain(forName: legacyDomain)
        defaults.removePersistentDomain(forName: destinationDomain)
    }

    defaults.removePersistentDomain(forName: destinationDomain)
    defaults.setPersistentDomain(
        [
            "appearanceMode": "dark",
            "globalHotKey": "optionSpace",
            "showsMenuBarIcon": false
        ],
        forName: legacyDomain
    )
    defaults.set("controlSpace", forKey: "globalHotKey")

    let changed = LegacyPreferencesMigrator.migrateIfNeeded(
        legacyDomainName: legacyDomain,
        destinationDefaults: defaults
    )
    runner.expect(
        changed
            && defaults.string(forKey: "appearanceMode") == "dark"
            && defaults.string(forKey: "globalHotKey") == "controlSpace"
            && defaults.object(forKey: "showsMenuBarIcon") as? Bool == false,
        "旧偏好只复制受支持的值且不覆盖新设置"
    )

    defaults.setPersistentDomain(
        [
            "appearanceMode": "light",
            "globalHotKey": "commandOptionSpace",
            "showsMenuBarIcon": true
        ],
        forName: legacyDomain
    )
    runner.expect(
        !LegacyPreferencesMigrator.migrateIfNeeded(
            legacyDomainName: legacyDomain,
            destinationDefaults: defaults
        )
            && defaults.string(forKey: "appearanceMode") == "dark"
            && defaults.string(forKey: "globalHotKey") == "controlSpace"
            && defaults.object(forKey: "showsMenuBarIcon") as? Bool == false,
        "旧偏好迁移只执行一次"
    )

    let invalidDestinationDomain = "com.crimsonteps.benri.checks.\(UUID().uuidString)"
    guard let invalidDefaults = UserDefaults(suiteName: invalidDestinationDomain) else {
        runner.expect(false, "可创建非法偏好测试域")
        return
    }
    defer { invalidDefaults.removePersistentDomain(forName: invalidDestinationDomain) }
    invalidDefaults.removePersistentDomain(forName: invalidDestinationDomain)
    invalidDefaults.setPersistentDomain(
        [
            "appearanceMode": "sepia",
            "globalHotKey": "commandShiftSpace",
            "showsMenuBarIcon": "yes"
        ],
        forName: legacyDomain
    )
    _ = LegacyPreferencesMigrator.migrateIfNeeded(
        legacyDomainName: legacyDomain,
        destinationDefaults: invalidDefaults
    )
    runner.expect(
        invalidDefaults.object(forKey: "appearanceMode") == nil
            && invalidDefaults.object(forKey: "globalHotKey") == nil
            && invalidDefaults.object(forKey: "showsMenuBarIcon") == nil,
        "旧偏好迁移忽略不受支持的值"
    )
}

private func checkVaultFileLock() throws {
    let rootDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("BenriLockChecks-\(UUID().uuidString)", isDirectory: true)
    let lockDirectory = rootDirectory.appendingPathComponent("Locks", isDirectory: true)
    let firstVaultURL = rootDirectory
        .appendingPathComponent("VaultA", isDirectory: true)
        .appendingPathComponent("vault.qv")
    let sameDirectoryVaultURL = firstVaultURL
        .deletingLastPathComponent()
        .appendingPathComponent("another.qv")
    let secondVaultURL = rootDirectory
        .appendingPathComponent("VaultB", isDirectory: true)
        .appendingPathComponent("vault.qv")
    defer { try? FileManager.default.removeItem(at: rootDirectory) }

    let firstLock = try VaultFileLock.acquire(
        forVaultAt: firstVaultURL,
        lockDirectoryURL: lockDirectory
    )
    runner.expect(
        FileManager.default.fileExists(atPath: firstLock.lockFileURL.path),
        "首次打开保险库可获取进程锁"
    )

    do {
        _ = try VaultFileLock.acquire(
            forVaultAt: firstVaultURL,
            lockDirectoryURL: lockDirectory
        )
        runner.expect(false, "同一保险库的第二个进程锁会被拒绝")
    } catch VaultFileLockError.alreadyInUse {
        runner.expect(true, "同一保险库的第二个进程锁会被拒绝")
    } catch {
        runner.expect(false, "同一保险库的第二个进程锁会被拒绝")
    }

    do {
        _ = try VaultFileLock.acquire(
            forVaultAt: sameDirectoryVaultURL,
            lockDirectoryURL: lockDirectory
        )
        runner.expect(false, "共享密钥目录的不同保险库文件也会冲突")
    } catch VaultFileLockError.alreadyInUse {
        runner.expect(true, "共享密钥目录的不同保险库文件也会冲突")
    } catch {
        runner.expect(false, "共享密钥目录的不同保险库文件也会冲突")
    }

    let independentLock = try VaultFileLock.acquire(
        forVaultAt: secondVaultURL,
        lockDirectoryURL: lockDirectory
    )
    runner.expect(
        independentLock.lockFileURL != firstLock.lockFileURL,
        "不同数据目录可以同时运行"
    )

    let lockAttributes = try FileManager.default.attributesOfItem(
        atPath: firstLock.lockFileURL.path
    )
    let lockDirectoryAttributes = try FileManager.default.attributesOfItem(
        atPath: lockDirectory.path
    )
    runner.expect(
        (lockAttributes[.posixPermissions] as? NSNumber)?.intValue == 0o600,
        "保险库锁文件权限为 0600"
    )
    runner.expect(
        (lockDirectoryAttributes[.posixPermissions] as? NSNumber)?.intValue == 0o700,
        "保险库锁目录权限为 0700"
    )

    firstLock.release()
    firstLock.release()
    let reacquiredLock = try VaultFileLock.acquire(
        forVaultAt: firstVaultURL,
        lockDirectoryURL: lockDirectory
    )
    runner.expect(
        reacquiredLock.lockFileURL == firstLock.lockFileURL,
        "首个实例退出后可以立即重新获取保险库锁"
    )

    let realDirectory = rootDirectory.appendingPathComponent("RealVault", isDirectory: true)
    let aliasDirectory = rootDirectory.appendingPathComponent("AliasVault", isDirectory: true)
    try FileManager.default.createDirectory(
        at: realDirectory,
        withIntermediateDirectories: true
    )
    try FileManager.default.createSymbolicLink(
        at: aliasDirectory,
        withDestinationURL: realDirectory
    )
    let realPathLock = try VaultFileLock.acquire(
        forVaultAt: realDirectory.appendingPathComponent("vault.qv"),
        lockDirectoryURL: lockDirectory
    )
    do {
        _ = try VaultFileLock.acquire(
            forVaultAt: aliasDirectory.appendingPathComponent("vault.qv"),
            lockDirectoryURL: lockDirectory
        )
        runner.expect(false, "符号链接别名会映射到同一保险库锁")
    } catch VaultFileLockError.alreadyInUse {
        runner.expect(true, "符号链接别名会映射到同一保险库锁")
    } catch {
        runner.expect(false, "符号链接别名会映射到同一保险库锁")
    }

    let upperCaseVaultURL = rootDirectory
        .appendingPathComponent("CaseVault", isDirectory: true)
        .appendingPathComponent("vault.qv")
    let lowerCaseVaultURL = rootDirectory
        .appendingPathComponent("casevault", isDirectory: true)
        .appendingPathComponent("vault.qv")
    let caseLock = try VaultFileLock.acquire(
        forVaultAt: upperCaseVaultURL,
        lockDirectoryURL: lockDirectory
    )
    do {
        _ = try VaultFileLock.acquire(
            forVaultAt: lowerCaseVaultURL,
            lockDirectoryURL: lockDirectory
        )
        runner.expect(false, "不存在目录的大小写别名也不会绕过保险库锁")
    } catch VaultFileLockError.alreadyInUse {
        runner.expect(true, "不存在目录的大小写别名也不会绕过保险库锁")
    } catch {
        runner.expect(false, "不存在目录的大小写别名也不会绕过保险库锁")
    }

    let childVaultURL = rootDirectory
        .appendingPathComponent("ChildVault", isDirectory: true)
        .appendingPathComponent("vault.qv")
    let childProcess = Process()
    let executableURL = URL(
        fileURLWithPath: CommandLine.arguments[0],
        relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    ).standardizedFileURL
    childProcess.executableURL = executableURL
    childProcess.arguments = [
        "--hold-vault-lock",
        childVaultURL.path,
        lockDirectory.path
    ]
    let childOutput = Pipe()
    childProcess.standardOutput = childOutput
    try childProcess.run()
    defer {
        if childProcess.isRunning {
            _ = Darwin.kill(childProcess.processIdentifier, SIGKILL)
            childProcess.waitUntilExit()
        }
    }
    let readyData = try childOutput.fileHandleForReading.read(upToCount: 6) ?? Data()
    runner.expect(
        String(decoding: readyData, as: UTF8.self).contains("READY"),
        "子进程可持有保险库锁"
    )
    do {
        _ = try VaultFileLock.acquire(
            forVaultAt: childVaultURL,
            lockDirectoryURL: lockDirectory
        )
        runner.expect(false, "跨进程的第二个保险库锁会被拒绝")
    } catch VaultFileLockError.alreadyInUse {
        runner.expect(true, "跨进程的第二个保险库锁会被拒绝")
    } catch {
        runner.expect(false, "跨进程的第二个保险库锁会被拒绝")
    }
    _ = Darwin.kill(childProcess.processIdentifier, SIGKILL)
    childProcess.waitUntilExit()
    let lockAfterForcedExit = try VaultFileLock.acquire(
        forVaultAt: childVaultURL,
        lockDirectoryURL: lockDirectory
    )
    runner.expect(
        !childProcess.isRunning,
        "子进程被强制结束后保险库锁由内核自动释放"
    )

    reacquiredLock.release()
    independentLock.release()
    realPathLock.release()
    caseLock.release()
    lockAfterForcedExit.release()
}

private func checkLegacyInstallationMigration() throws {
    let rootDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("BenriMigrationChecks-\(UUID().uuidString)", isDirectory: true)
    let legacyDirectory = rootDirectory.appendingPathComponent("QuickVault", isDirectory: true)
    let destinationDirectory = rootDirectory.appendingPathComponent("Benri", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: rootDirectory) }

    let key = VaultCrypto.generateKeyData()
    let legacyCategory = VaultCategory(
        id: VaultDefaults.personalCategoryID,
        name: "私人",
        iconName: nil,
        sortOrder: 0,
        isBuiltIn: true
    )
    let legacyPayload = VaultPayload(
        formatVersion: VaultPayload.currentFormatVersion - 1,
        categories: [legacyCategory],
        records: [
            VaultRecord(
                name: "旧版记录",
                categoryID: legacyCategory.id,
                content: "legacy-secret",
                createdAt: fixedDate,
                updatedAt: fixedDate
            )
        ]
    )
    let legacyVaultURL = legacyDirectory.appendingPathComponent("vault.qv")
    let legacyKeyURL = legacyDirectory.appendingPathComponent("vault.key")
    try VaultFileStore(fileURL: legacyVaultURL, keyData: key).save(legacyPayload)
    try writePrivateTestData(key, to: legacyKeyURL)

    let outcome = try LegacyInstallationMigrator.migrateIfNeeded(
        legacyDirectoryURL: legacyDirectory,
        destinationDirectoryURL: destinationDirectory,
        appVersion: "1.1.0 (2)",
        legacyKeychainKey: { nil },
        now: fixedDate
    )
    guard case let .migrated(backupURL) = outcome else {
        runner.expect(false, "旧 QuickVault 保险库可一次性迁移到 Benri")
        return
    }

    let migratedKeyURL = destinationDirectory.appendingPathComponent("vault.key")
    let migratedVaultURL = destinationDirectory.appendingPathComponent("vault.qv")
    let migratedKey = try Data(contentsOf: migratedKeyURL)
    let migratedPayload = try VaultFileStore(
        fileURL: migratedVaultURL,
        keyData: migratedKey
    ).load()
    var expectedPayload = legacyPayload
    _ = expectedPayload.migrateToCurrentFormat()
    runner.expect(
        migratedKey == key
            && migratedPayload == expectedPayload
            && !FileManager.default.fileExists(atPath: legacyDirectory.path),
        "旧 QuickVault 保险库可一次性迁移到 Benri"
    )

    let migrationBackup = try VaultBackupArchive.validate(at: backupURL)
    runner.expect(
        migrationBackup.payload == legacyPayload,
        "迁移前备份可完整校验并保留原始格式"
    )

    let destinationAttributes = try FileManager.default.attributesOfItem(
        atPath: destinationDirectory.path
    )
    let migratedVaultAttributes = try FileManager.default.attributesOfItem(
        atPath: migratedVaultURL.path
    )
    let migratedKeyAttributes = try FileManager.default.attributesOfItem(
        atPath: migratedKeyURL.path
    )
    runner.expect(
        (destinationAttributes[.posixPermissions] as? NSNumber)?.intValue == 0o700
            && (migratedVaultAttributes[.posixPermissions] as? NSNumber)?.intValue == 0o600
            && (migratedKeyAttributes[.posixPermissions] as? NSNumber)?.intValue == 0o600,
        "迁移后的数据目录和文件权限正确"
    )

    let secondOutcome = try LegacyInstallationMigrator.migrateIfNeeded(
        legacyDirectoryURL: legacyDirectory,
        destinationDirectoryURL: destinationDirectory,
        appVersion: "1.1.0 (2)",
        legacyKeychainKey: { nil }
    )
    runner.expect(
        secondOutcome == .currentVaultAlreadyExists,
        "已有 Benri 保险库时不会重复迁移"
    )

    let keychainRoot = rootDirectory.appendingPathComponent("KeychainFallback", isDirectory: true)
    let keychainLegacy = keychainRoot.appendingPathComponent("QuickVault", isDirectory: true)
    let keychainDestination = keychainRoot.appendingPathComponent("Benri", isDirectory: true)
    let keychainVaultURL = keychainLegacy.appendingPathComponent("vault.qv")
    try VaultFileStore(fileURL: keychainVaultURL, keyData: key).save(legacyPayload)
    let keychainOutcome = try LegacyInstallationMigrator.migrateIfNeeded(
        legacyDirectoryURL: keychainLegacy,
        destinationDirectoryURL: keychainDestination,
        appVersion: "1.1.0 (2)",
        legacyKeychainKey: { key },
        now: fixedDate
    )
    runner.expect(
        {
            if case .migrated = keychainOutcome { return true }
            return false
        }(),
        "旧密钥文件缺失时可从旧钥匙串迁移"
    )

    let failureRoot = rootDirectory.appendingPathComponent("WrongKey", isDirectory: true)
    let failureLegacy = failureRoot.appendingPathComponent("QuickVault", isDirectory: true)
    let failureDestination = failureRoot.appendingPathComponent("Benri", isDirectory: true)
    let failureVaultURL = failureLegacy.appendingPathComponent("vault.qv")
    let failureKeyURL = failureLegacy.appendingPathComponent("vault.key")
    try VaultFileStore(fileURL: failureVaultURL, keyData: key).save(legacyPayload)
    try writePrivateTestData(VaultCrypto.generateKeyData(), to: failureKeyURL)
    let originalFailureVault = try Data(contentsOf: failureVaultURL)
    let originalFailureKey = try Data(contentsOf: failureKeyURL)
    runner.expectThrows("旧保险库密钥不匹配时拒绝迁移") {
        _ = try LegacyInstallationMigrator.migrateIfNeeded(
            legacyDirectoryURL: failureLegacy,
            destinationDirectoryURL: failureDestination,
            appVersion: "1.1.0 (2)",
            legacyKeychainKey: { nil }
        )
    }
    let failureVaultAfterMigration = try Data(contentsOf: failureVaultURL)
    let failureKeyAfterMigration = try Data(contentsOf: failureKeyURL)
    runner.expect(
        !FileManager.default.fileExists(atPath: failureDestination.path)
            && failureVaultAfterMigration == originalFailureVault
            && failureKeyAfterMigration == originalFailureKey,
        "迁移失败不会创建新目录或改动旧数据"
    )

    let futureRoot = rootDirectory.appendingPathComponent("FutureFormat", isDirectory: true)
    let futureLegacy = futureRoot.appendingPathComponent("QuickVault", isDirectory: true)
    let futureDestination = futureRoot.appendingPathComponent("Benri", isDirectory: true)
    let futureVaultURL = futureLegacy.appendingPathComponent("vault.qv")
    let futureKeyURL = futureLegacy.appendingPathComponent("vault.key")
    let futureJSON = """
    {
      "formatVersion": \(VaultPayload.currentFormatVersion + 1),
      "categories": [],
      "records": []
    }
    """
    try writePrivateTestData(
        try encryptRawVaultJSON(Data(futureJSON.utf8), keyData: key),
        to: futureVaultURL
    )
    try writePrivateTestData(key, to: futureKeyURL)
    runner.expectThrows("未来格式的旧保险库不会被降级迁移") {
        _ = try LegacyInstallationMigrator.migrateIfNeeded(
            legacyDirectoryURL: futureLegacy,
            destinationDirectoryURL: futureDestination,
            appVersion: "1.1.0 (2)",
            legacyKeychainKey: { nil }
        )
    }
    runner.expect(
        !FileManager.default.fileExists(atPath: futureDestination.path)
            && FileManager.default.fileExists(atPath: futureLegacy.path),
        "未来格式迁移失败时保留旧目录"
    )

    let noLegacyRoot = rootDirectory.appendingPathComponent("NoLegacy", isDirectory: true)
    let noLegacyDirectory = noLegacyRoot.appendingPathComponent("QuickVault", isDirectory: true)
    let noLegacyDestination = noLegacyRoot.appendingPathComponent("Benri", isDirectory: true)
    let noLegacyOutcome = try LegacyInstallationMigrator.migrateIfNeeded(
        legacyDirectoryURL: noLegacyDirectory,
        destinationDirectoryURL: noLegacyDestination,
        appVersion: "1.1.0 (2)",
        legacyKeychainKey: { nil }
    )
    runner.expect(
        noLegacyOutcome == .noLegacyVault
            && !FileManager.default.fileExists(atPath: noLegacyDestination.path),
        "没有旧保险库时不会创建迁移产物"
    )

    let activeRoot = rootDirectory.appendingPathComponent("LegacyActive", isDirectory: true)
    let activeLegacy = activeRoot.appendingPathComponent("QuickVault", isDirectory: true)
    let activeDestination = activeRoot.appendingPathComponent("Benri", isDirectory: true)
    try VaultFileStore(
        fileURL: activeLegacy.appendingPathComponent("vault.qv"),
        keyData: key
    ).save(legacyPayload)
    try writePrivateTestData(key, to: activeLegacy.appendingPathComponent("vault.key"))
    runner.expectThrows("旧版仍在运行时迁移会在提交前停止") {
        _ = try LegacyInstallationMigrator.migrateIfNeeded(
            legacyDirectoryURL: activeLegacy,
            destinationDirectoryURL: activeDestination,
            appVersion: "1.1.0 (2)",
            legacyKeychainKey: { nil },
            legacySourceIsInactive: { false }
        )
    }
    runner.expect(
        FileManager.default.fileExists(atPath: activeLegacy.path)
            && !FileManager.default.fileExists(atPath: activeDestination.path),
        "旧版活跃导致迁移失败时旧目录保持不变"
    )

    let changedRoot = rootDirectory.appendingPathComponent("LegacyChanged", isDirectory: true)
    let changedLegacy = changedRoot.appendingPathComponent("QuickVault", isDirectory: true)
    let changedDestination = changedRoot.appendingPathComponent("Benri", isDirectory: true)
    let changedVaultURL = changedLegacy.appendingPathComponent("vault.qv")
    try VaultFileStore(fileURL: changedVaultURL, keyData: key).save(legacyPayload)
    try writePrivateTestData(key, to: changedLegacy.appendingPathComponent("vault.key"))
    var inactivityCheckCount = 0
    runner.expectThrows("旧数据在最终提交前发生变化时取消迁移") {
        _ = try LegacyInstallationMigrator.migrateIfNeeded(
            legacyDirectoryURL: changedLegacy,
            destinationDirectoryURL: changedDestination,
            appVersion: "1.1.0 (2)",
            legacyKeychainKey: { nil },
            legacySourceIsInactive: {
                inactivityCheckCount += 1
                if inactivityCheckCount == 3 {
                    var changedPayload = legacyPayload
                    changedPayload.records.append(
                        VaultRecord(
                            name: "迁移期间新增",
                            categoryID: legacyCategory.id
                        )
                    )
                    try! VaultFileStore(
                        fileURL: changedVaultURL,
                        keyData: key
                    ).save(changedPayload)
                }
                return true
            }
        )
    }
    let changedPayloadOnDisk = try VaultFileStore(
        fileURL: changedVaultURL,
        keyData: key
    ).load()
    runner.expect(
        changedPayloadOnDisk.records.count == legacyPayload.records.count + 1
            && !FileManager.default.fileExists(atPath: changedDestination.path),
        "迁移期间的新数据会保留且目标目录会回滚"
    )

    let extraFileRoot = rootDirectory.appendingPathComponent("ExtraLegacyFile", isDirectory: true)
    let extraFileLegacy = extraFileRoot.appendingPathComponent("QuickVault", isDirectory: true)
    let extraFileDestination = extraFileRoot.appendingPathComponent("Benri", isDirectory: true)
    try VaultFileStore(
        fileURL: extraFileLegacy.appendingPathComponent("vault.qv"),
        keyData: key
    ).save(legacyPayload)
    try writePrivateTestData(key, to: extraFileLegacy.appendingPathComponent("vault.key"))
    try writePrivateTestData(
        Data("keep-me".utf8),
        to: extraFileLegacy.appendingPathComponent("notes.txt")
    )
    runner.expectThrows("旧目录包含额外文件时不会永久删除") {
        _ = try LegacyInstallationMigrator.migrateIfNeeded(
            legacyDirectoryURL: extraFileLegacy,
            destinationDirectoryURL: extraFileDestination,
            appVersion: "1.1.0 (2)",
            legacyKeychainKey: { nil }
        )
    }
    runner.expect(
        FileManager.default.fileExists(atPath: extraFileLegacy.path)
            && FileManager.default.fileExists(
                atPath: extraFileLegacy.appendingPathComponent("notes.txt").path
            )
            && FileManager.default.fileExists(atPath: extraFileDestination.path),
        "额外旧文件会被保留且已验证的新保险库仍可使用"
    )

    let occupiedRoot = rootDirectory.appendingPathComponent("Occupied", isDirectory: true)
    let occupiedLegacy = occupiedRoot.appendingPathComponent("QuickVault", isDirectory: true)
    let occupiedDestination = occupiedRoot.appendingPathComponent("Benri", isDirectory: true)
    try VaultFileStore(
        fileURL: occupiedLegacy.appendingPathComponent("vault.qv"),
        keyData: key
    ).save(legacyPayload)
    try writePrivateTestData(key, to: occupiedLegacy.appendingPathComponent("vault.key"))
    try FileManager.default.createDirectory(
        at: occupiedDestination,
        withIntermediateDirectories: true
    )
    runner.expectThrows("目标目录已被占用时不会覆盖") {
        _ = try LegacyInstallationMigrator.migrateIfNeeded(
            legacyDirectoryURL: occupiedLegacy,
            destinationDirectoryURL: occupiedDestination,
            appVersion: "1.1.0 (2)",
            legacyKeychainKey: { nil }
        )
    }
}

private func checkBackupArchive() throws {
    let rootDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("BenriBackupChecks-\(UUID().uuidString)", isDirectory: true)
    let sourceDirectory = rootDirectory.appendingPathComponent("Source", isDirectory: true)
    let restoredDirectory = rootDirectory.appendingPathComponent("Restored", isDirectory: true)
    let backupURL = rootDirectory.appendingPathComponent(
        "Benri Test.\(VaultBackupArchive.fileExtension)",
        isDirectory: true
    )
    defer { try? FileManager.default.removeItem(at: rootDirectory) }

    let sourceVaultURL = sourceDirectory.appendingPathComponent("vault.qv")
    let sourceKeyURL = sourceDirectory.appendingPathComponent("vault.key")
    let sourceKey = VaultCrypto.generateKeyData()
    let sourcePayload = VaultPayload(records: [
        VaultRecord(
            name: "备份记录",
            categoryID: VaultDefaults.personalCategoryID,
            content: "backup-secret",
            createdAt: fixedDate,
            updatedAt: fixedDate
        )
    ])
    try VaultFileStore(fileURL: sourceVaultURL, keyData: sourceKey).save(sourcePayload)
    try FileManager.default.createDirectory(
        at: sourceDirectory,
        withIntermediateDirectories: true,
        attributes: [.posixPermissions: 0o700]
    )
    try sourceKey.write(to: sourceKeyURL, options: [.atomic])
    try FileManager.default.setAttributes(
        [.posixPermissions: 0o600],
        ofItemAtPath: sourceKeyURL.path
    )

    let manifest = try VaultBackupArchive.create(
        at: backupURL,
        vaultFileURL: sourceVaultURL,
        keyFileURL: sourceKeyURL,
        appVersion: "1.1.0 (2)",
        createdAt: fixedDate
    )
    let manifestText = try String(
        contentsOf: backupURL.appendingPathComponent("manifest.json"),
        encoding: .utf8
    )
    runner.expect(
        manifest.recordCount == 1
            && !manifestText.contains("备份记录")
            && !manifestText.contains("backup-secret"),
        "备份清单记录数据规模但不保存名称或正文"
    )

    let validated = try VaultBackupArchive.validate(at: backupURL)
    runner.expect(validated.payload == sourcePayload, "Benri 备份可完整校验和解密")

    let packageAttributes = try FileManager.default.attributesOfItem(atPath: backupURL.path)
    let backupVaultAttributes = try FileManager.default.attributesOfItem(
        atPath: backupURL.appendingPathComponent("vault.qv").path
    )
    let backupKeyAttributes = try FileManager.default.attributesOfItem(
        atPath: backupURL.appendingPathComponent("vault.key").path
    )
    runner.expect(
        packageAttributes[.posixPermissions] as? NSNumber == NSNumber(value: 0o700),
        "备份包目录权限为 0700"
    )
    runner.expect(
        backupVaultAttributes[.posixPermissions] as? NSNumber == NSNumber(value: 0o600)
            && backupKeyAttributes[.posixPermissions] as? NSNumber == NSNumber(value: 0o600),
        "备份包内数据和密钥权限为 0600"
    )

    let restoredVaultURL = restoredDirectory.appendingPathComponent("vault.qv")
    let restoredKeyURL = restoredDirectory.appendingPathComponent("vault.key")
    let oldKey = VaultCrypto.generateKeyData()
    try VaultFileStore(fileURL: restoredVaultURL, keyData: oldKey).save(
        VaultPayload(records: [
            VaultRecord(
                name: "将被替换",
                categoryID: VaultDefaults.otherCategoryID
            )
        ])
    )
    try writePrivateTestData(oldKey, to: restoredKeyURL)

    let destinationStore = VaultFileStore(
        fileURL: restoredVaultURL,
        keyData: oldKey
    )
    let restoreResult = try VaultBackupArchive.restore(
        validated,
        to: destinationStore
    )
    let restoredKey = try Data(contentsOf: restoredKeyURL)
    let restoredPayload = try destinationStore.load()
    let restoredVaultAttributes = try FileManager.default.attributesOfItem(
        atPath: restoredVaultURL.path
    )
    let restoredKeyAttributes = try FileManager.default.attributesOfItem(
        atPath: restoredKeyURL.path
    )
    runner.expect(
        restoreResult == sourcePayload
            && restoredPayload == sourcePayload
            && restoredKey == oldKey,
        "恢复使用当前活动密钥且只替换保险库"
    )
    runner.expect(
        restoredVaultAttributes[.posixPermissions] as? NSNumber == NSNumber(value: 0o600)
            && restoredKeyAttributes[.posixPermissions] as? NSNumber == NSNumber(value: 0o600),
        "恢复后的保险库和活动密钥权限为 0600"
    )
    runner.expectThrows("备份密钥不能解密恢复后的活动保险库") {
        _ = try VaultFileStore(
            fileURL: restoredVaultURL,
            keyData: sourceKey
        ).load()
    }

    let vaultBeforeFailedRestore = try Data(contentsOf: restoredVaultURL)
    let keyBeforeFailedRestore = try Data(contentsOf: restoredKeyURL)
    let invalidBackup = ValidatedVaultBackup(
        manifest: validated.manifest,
        payload: VaultPayload(
            formatVersion: VaultPayload.currentFormatVersion + 1
        )
    )
    runner.expectThrows("恢复内容无法重新加密时保留原保险库") {
        _ = try VaultBackupArchive.restore(invalidBackup, to: destinationStore)
    }
    let vaultAfterFailedRestore = try Data(contentsOf: restoredVaultURL)
    let keyAfterFailedRestore = try Data(contentsOf: restoredKeyURL)
    runner.expect(
        vaultAfterFailedRestore == vaultBeforeFailedRestore
            && keyAfterFailedRestore == keyBeforeFailedRestore,
        "恢复失败不会改动当前保险库或活动密钥"
    )

    try VaultBackupArchive.create(
        at: backupURL,
        vaultFileURL: sourceVaultURL,
        keyFileURL: sourceKeyURL,
        appVersion: "1.1.0 (2)",
        createdAt: fixedDate
    )
    let overwrittenBackup = try VaultBackupArchive.validate(at: backupURL)
    runner.expect(
        overwrittenBackup.payload == sourcePayload,
        "覆盖已有备份时仍保持完整可用"
    )

    let backupKeyURL = backupURL.appendingPathComponent("vault.key")
    try VaultCrypto.generateKeyData().write(to: backupKeyURL, options: [.atomic])
    runner.expectThrows("密钥不匹配的备份会被拒绝") {
        _ = try VaultBackupArchive.validate(at: backupURL)
    }
}

@MainActor
private func checkClipboardStore() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("BenriClipboardChecks-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let store = ClipboardStore(directoryURL: directory)
    store.addText("https://example.com/path", sourceBundleID: "com.apple.Safari")
    store.addText("hello searchable world", sourceBundleID: "com.apple.TextEdit")
    store.addText("person@example.com", sourceBundleID: nil)

    runner.expect(store.items.count == 3, "剪贴板文本写入 SQLite 缓存")
    runner.expect(
        store.search("searchable").first?.text == "hello searchable world",
        "剪贴板历史支持子串搜索"
    )
    runner.expect(
        store.search("").count == 3,
        "空搜索展示全部剪贴板历史"
    )

    if let item = store.items.first(where: { $0.text == "hello searchable world" }) {
        store.togglePinned(item)
        runner.expect(store.search("").first?.id == item.id, "固定记录置于历史顶部")
    } else {
        runner.expect(false, "固定记录置于历史顶部")
    }

    let imageData = Data([
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A
    ])
    let imageItem = try store.addImage(imageData, sourceBundleID: "com.apple.Preview")
    let imageURL = try XCTUnwrap(store.imageURL(for: imageItem))
    runner.expect(FileManager.default.fileExists(atPath: imageURL.path), "剪贴板图片独立写入缓存")
    let permissions = try FileManager.default.attributesOfItem(atPath: imageURL.path)[.posixPermissions]
        as? NSNumber
    runner.expect(permissions?.intValue == 0o600, "剪贴板图片缓存权限为 0600")

    let reloaded = ClipboardStore(directoryURL: directory)
    runner.expect(reloaded.items.count == 4, "剪贴板历史可跨 Store 实例重新载入")
    reloaded.clearAll()
    runner.expect(reloaded.items.isEmpty, "清空历史删除全部数据库记录")
    runner.expect(!FileManager.default.fileExists(atPath: imageURL.path), "清空历史删除自有图片文件")
}

private func XCTUnwrap<T>(_ value: T?) throws -> T {
    guard let value else {
        throw NSError(domain: "BenriChecks", code: 1)
    }
    return value
}

do {
    try checkModelRoundTrip()
    checkSearchAndCategories()
    try checkLegacyMigration()
    try checkCrypto()
    try checkFileStore()
    try checkLocalKeyStore()
    checkLegacyPreferencesMigration()
    try checkVaultFileLock()
    try checkLegacyInstallationMigration()
    try checkBackupArchive()
    try MainActor.assumeIsolated {
        try checkClipboardStore()
    }
} catch {
    print("✗ 测试运行异常：\(error.localizedDescription)")
    exit(1)
}

print("\n完成 \(runner.checks) 项检查，失败 \(runner.failures) 项。")
exit(runner.failures == 0 ? 0 : 1)
