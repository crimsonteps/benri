import CryptoKit
import Darwin
import Foundation
import QuickVaultCore

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
    runner.expect(
        partialCategoriesPayload.categories.contains(renamedPersonalCategory)
            && partialCategoriesPayload.categories.contains(customCategory)
            && partialCategoriesPayload.categories.count == VaultDefaults.categories.count + 1,
        "迁移保留已有同 ID 分类与自定义分类"
    )

    var currentPayloadWithMissingCategories = VaultPayload(categories: [])
    runner.expect(
        currentPayloadWithMissingCategories.migrateToCurrentFormat()
            && currentPayloadWithMissingCategories.categories == VaultDefaults.categories,
        "已升级版本也会补回缺失的内置分类"
    )
    runner.expect(!payload.migrateToCurrentFormat(), "完整当前格式无需重复迁移")

    let encoded = try JSONEncoder().encode(payload)
    let encodedText = String(decoding: encoded, as: UTF8.self)
    runner.expect(!encodedText.contains("\"fields\""), "新格式不再保存字段数组")
    runner.expect(encodedText.contains("\"contentType\""), "新格式保存内容类型")
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
        .appendingPathComponent("QuickVaultChecks-\(UUID().uuidString)", isDirectory: true)
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
            service: "com.crimsonteps.quickvault.checks.\(UUID().uuidString)"
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
}

do {
    try checkModelRoundTrip()
    checkSearchAndCategories()
    try checkLegacyMigration()
    try checkCrypto()
    try checkFileStore()
    try checkLocalKeyStore()
} catch {
    print("✗ 测试运行异常：\(error.localizedDescription)")
    exit(1)
}

print("\n完成 \(runner.checks) 项检查，失败 \(runner.failures) 项。")
exit(runner.failures == 0 ? 0 : 1)
