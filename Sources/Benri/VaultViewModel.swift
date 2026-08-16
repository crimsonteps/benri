import AppKit
import Foundation
import BenriCore

struct RecordEditorContext: Identifiable, Equatable {
    let id = UUID()
    let recordID: UUID?
}

struct CategoryEditorContext: Identifiable, Equatable {
    let id = UUID()
    let categoryID: UUID?
}

struct VaultRestoreResult {
    let backup: ValidatedVaultBackup
    let recoveryBackupURL: URL?
}

enum KeyboardPane {
    case categories
    case records
    case value
}

enum KeyboardActionTarget: Equatable {
    case category(UUID)
    case record(UUID)
}

enum RecordPanelMode: Equatable {
    case closed
    case preview
    case edit
}

enum VaultAlert: Identifiable, Equatable {
    case saveError(String)
    case confirmReset
    case confirmDeleteRecord(UUID)
    case confirmDeleteCategory(UUID)

    var id: String {
        switch self {
        case let .saveError(message):
            return "save-\(message)"
        case .confirmReset:
            return "reset"
        case let .confirmDeleteRecord(id):
            return "record-\(id.uuidString)"
        case let .confirmDeleteCategory(id):
            return "category-\(id.uuidString)"
        }
    }
}

enum VaultBootstrapError: Error, LocalizedError {
    case missingKey

    var errorDescription: String? {
        switch self {
        case .missingKey:
            return "保险库文件存在，但本地解密密钥已丢失。"
        }
    }
}

enum VaultOperationError: Error, LocalizedError {
    case unsavedChanges
    case restoreFailed
    case activeKeyUnavailable

    var errorDescription: String? {
        switch self {
        case .unsavedChanges:
            return "当前修改尚未成功保存，请先解决保存错误。"
        case .restoreFailed:
            return "Benri 无法确认恢复后的保险库状态。为避免覆盖磁盘数据，当前窗口已停止写入。"
        case .activeKeyUnavailable:
            return "无法确认当前保险库的持久化密钥。为避免生成下次启动无法解密的数据，恢复已停止。"
        }
    }
}

@MainActor
final class VaultViewModel: ObservableObject {
    @Published private(set) var payload = VaultPayload.empty
    @Published var selectedCategoryID: UUID?
    @Published var selectedRecordID: UUID?
    @Published var searchText = ""
    @Published var fatalErrorMessage: String?
    @Published var recordEditor: RecordEditorContext?
    @Published var categoryEditor: CategoryEditorContext?
    @Published var alert: VaultAlert?
    @Published private(set) var keyboardPane: KeyboardPane = .records
    @Published private(set) var recordPanelMode: RecordPanelMode = .closed
    @Published var isEditingRecordName = false
    @Published private(set) var isSearchFocused = false

    let vaultFileURL: URL

    var keyFileURL: URL {
        keyStore.fileURL
    }

    private let keyStore: VaultKeyStore
    private var fileStore: VaultFileStore?
    private var recordSaveWorkItem: DispatchWorkItem?
    private var hasUnsavedChanges = false

    init(
        vaultFileURL: URL? = nil,
        keyStore: VaultKeyStore? = nil,
        startupFailureMessage: String? = nil
    ) {
        let resolvedVaultFileURL = vaultFileURL
            ?? VaultStorage.defaultVaultFileURL()
        self.vaultFileURL = resolvedVaultFileURL
        self.keyStore = keyStore ?? VaultKeyStore(
            fileURL: resolvedVaultFileURL
                .deletingLastPathComponent()
                .appendingPathComponent("vault.key")
        )

        if let startupFailureMessage {
            fatalErrorMessage = startupFailureMessage
        } else {
            bootstrap()
        }
    }

    var sortedCategories: [VaultCategory] {
        payload.categories.sorted {
            if $0.sortOrder == $1.sortOrder {
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
            return $0.sortOrder < $1.sortOrder
        }
    }

    var filteredRecords: [VaultRecord] {
        payload.filteredRecords(categoryID: nil, query: searchText)
    }

    var selectedRecord: VaultRecord? {
        guard let selectedRecordID else { return nil }
        return payload.records.first(where: { $0.id == selectedRecordID })
    }

    var keyboardActionTarget: KeyboardActionTarget? {
        switch keyboardPane {
        case .categories:
            return selectedCategoryID.map(KeyboardActionTarget.category)
        case .records:
            return selectedRecordID.map(KeyboardActionTarget.record)
        case .value:
            return nil
        }
    }

    var canEditKeyboardSelection: Bool {
        guard canModifyVault, let target = keyboardActionTarget else { return false }
        switch target {
        case let .category(id):
            return category(id: id) != nil
        case let .record(id):
            return record(id: id) != nil
        }
    }

    var canDeleteKeyboardSelection: Bool {
        guard canModifyVault, let target = keyboardActionTarget else { return false }
        switch target {
        case let .category(id):
            return payload.categories.count > 1 && category(id: id) != nil
        case let .record(id):
            return record(id: id) != nil
        }
    }

    var canModifyVault: Bool {
        fatalErrorMessage == nil && fileStore != nil
    }

    var canCreateRecoveryBackup: Bool {
        fatalErrorMessage == nil
            && FileManager.default.fileExists(atPath: vaultFileURL.path)
            && FileManager.default.fileExists(atPath: keyStore.fileURL.path)
    }

    var preferredCategoryID: UUID {
        if payload.categories.contains(where: { $0.id == VaultDefaults.personalCategoryID }) {
            return VaultDefaults.personalCategoryID
        }
        return sortedCategories.first?.id ?? VaultDefaults.personalCategoryID
    }

    func record(id: UUID) -> VaultRecord? {
        payload.records.first(where: { $0.id == id })
    }

    func category(id: UUID) -> VaultCategory? {
        payload.categories.first(where: { $0.id == id })
    }

    func categoryName(for id: UUID) -> String {
        payload.categoryName(for: id)
    }

    func recordCount(for categoryID: UUID?) -> Int {
        guard let categoryID else { return payload.records.count }
        return payload.records.filter { $0.categoryID == categoryID }.count
    }

    func selectCategory(_ categoryID: UUID?) {
        closeRecordPanel()
        selectedCategoryID = categoryID
        keyboardPane = .categories
        ensureSelection()
    }

    func moveCategorySelection(_ direction: Int) {
        closeRecordPanel()
        let categoryIDs: [UUID?] = [nil] + sortedCategories.map { Optional($0.id) }
        guard !categoryIDs.isEmpty else { return }

        let currentIndex = categoryIDs.firstIndex(where: { $0 == selectedCategoryID }) ?? 0
        let nextIndex = (currentIndex + direction + categoryIDs.count) % categoryIDs.count
        selectedCategoryID = categoryIDs[nextIndex]
        keyboardPane = .categories
        ensureSelection()
    }

    func moveKeyboardPaneLeft() {
        guard recordPanelMode != .edit else { return }
        if recordPanelMode == .preview {
            closeRecordPanel()
            return
        }

        switch keyboardPane {
        case .categories:
            break
        case .records:
            break
        case .value:
            keyboardPane = .records
        }
    }

    func moveKeyboardPaneRight() {
        guard recordPanelMode != .edit else { return }
        switch keyboardPane {
        case .categories:
            keyboardPane = .records
        case .records:
            showSelectedRecordPreview()
        case .value:
            break
        }
    }

    func setSearchFocused(_ focused: Bool) {
        isSearchFocused = focused
        if focused {
            closeRecordPanel()
            keyboardPane = .records
        }
    }

    func activateRecordNavigation() {
        guard recordPanelMode != .edit else { return }
        keyboardPane = .records
    }

    func handleFilterChange() {
        closeRecordPanel()
        keyboardPane = .records
        ensureSelection()
    }

    func activateRecordEditingFocus() {
        guard recordPanelMode == .edit else { return }
        keyboardPane = .value
    }

    func ensureSelection() {
        let records = filteredRecords
        if let selectedRecordID, records.contains(where: { $0.id == selectedRecordID }) {
            return
        }
        selectedRecordID = records.first?.id
    }

    func moveSelection(_ direction: Int) {
        guard keyboardPane == .records,
              recordPanelMode == .closed || recordPanelMode == .preview
        else { return }

        let records = filteredRecords
        guard !records.isEmpty else {
            selectedRecordID = nil
            return
        }

        guard let selectedRecordID,
              let currentIndex = records.firstIndex(where: { $0.id == selectedRecordID }) else {
            self.selectedRecordID = records.first?.id
            return
        }

        let nextIndex = min(max(currentIndex + direction, 0), records.count - 1)
        self.selectedRecordID = records[nextIndex].id
    }

    func selectRecord(_ id: UUID) {
        guard filteredRecords.contains(where: { $0.id == id }) else { return }
        let selectionChanged = selectedRecordID != id

        if selectionChanged, recordPanelMode == .edit {
            closeRecordPanel()
        }

        selectedRecordID = id
        keyboardPane = .records
    }

    func showSelectedRecordPreview() {
        guard selectedRecord != nil, recordPanelMode != .edit else { return }
        recordPanelMode = .preview
        keyboardPane = .records
    }

    func beginEditingRecord(_ id: UUID) {
        guard canModifyVault, record(id: id) != nil else { return }
        flushPendingRecordSave()
        closeRecordPanel()
        selectedRecordID = id
        keyboardPane = .records
        recordEditor = RecordEditorContext(recordID: id)
    }

    func closeRecordPanel() {
        if recordPanelMode == .edit {
            flushPendingRecordSave()
            isEditingRecordName = false
        }
        recordPanelMode = .closed
        keyboardPane = .records
    }

    func beginNewRecord() {
        guard canModifyVault else { return }
        closeRecordPanel()
        keyboardPane = .records
        recordEditor = RecordEditorContext(recordID: nil)
    }

    func beginNewCategory() {
        guard canModifyVault else { return }
        closeRecordPanel()
        keyboardPane = .categories
        categoryEditor = CategoryEditorContext(categoryID: nil)
    }

    func beginEditingCategory(_ id: UUID) {
        guard canModifyVault,
              category(id: id) != nil
        else { return }
        selectCategory(id)
        categoryEditor = CategoryEditorContext(categoryID: id)
    }

    func dismissEditors() {
        recordEditor = nil
        categoryEditor = nil
    }

    func saveRecord(
        id: UUID?,
        name: String,
        categoryID: UUID,
        content: String
    ) {
        guard canModifyVault else { return }
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return }

        let safeCategoryID: UUID
        if payload.categories.contains(where: { $0.id == categoryID }) {
            safeCategoryID = categoryID
        } else {
            safeCategoryID = payload.categories.first(where: {
                $0.id == VaultDefaults.otherCategoryID
            })?.id ?? preferredCategoryID
        }

        let recordID: UUID
        if let id, let index = payload.records.firstIndex(where: { $0.id == id }) {
            payload.records[index].name = cleanName
            payload.records[index].categoryID = safeCategoryID
            payload.records[index].content = content
            payload.records[index].updatedAt = Date()
            recordID = id
        } else {
            let record = VaultRecord(
                name: cleanName,
                categoryID: safeCategoryID,
                content: content
            )
            payload.records.append(record)
            recordID = record.id
        }

        selectedCategoryID = nil
        selectedRecordID = recordID
        recordPanelMode = .closed
        keyboardPane = .records
        persistChanges()
    }

    func beginEditingKeyboardSelection() -> Bool {
        guard canEditKeyboardSelection, let target = keyboardActionTarget else { return false }
        switch target {
        case let .category(id):
            beginEditingCategory(id)
        case let .record(id):
            beginEditingRecord(id)
        }
        return true
    }

    func requestDeleteKeyboardSelection() -> Bool {
        guard canDeleteKeyboardSelection, let target = keyboardActionTarget else { return false }
        switch target {
        case let .category(id):
            requestDeleteCategory(id)
        case let .record(id):
            requestDeleteRecord(id)
        }
        return true
    }

    func finishInlineRecordEditing() -> Bool {
        guard recordPanelMode == .edit else { return false }
        closeRecordPanel()
        return true
    }

    func requestDeleteRecord(_ id: UUID) {
        guard canModifyVault, record(id: id) != nil else { return }
        selectRecord(id)
        alert = .confirmDeleteRecord(id)
    }

    func deleteRecord(_ id: UUID) {
        guard canModifyVault else { return }
        let visibleRecordIDs = filteredRecords.map(\.id)
        let deletedIndex = visibleRecordIDs.firstIndex(of: id)
        let deletedSelectedRecord = selectedRecordID == id
        if deletedSelectedRecord {
            closeRecordPanel()
        }
        flushPendingRecordSave()
        payload.records.removeAll(where: { $0.id == id })
        if deletedSelectedRecord {
            let remainingRecords = filteredRecords
            if let deletedIndex, !remainingRecords.isEmpty {
                selectedRecordID = remainingRecords[
                    min(deletedIndex, remainingRecords.count - 1)
                ].id
            } else {
                selectedRecordID = remainingRecords.first?.id
            }
        } else {
            ensureSelection()
        }
        keyboardPane = .records
        persistChanges()
    }

    func updateRecordName(id: UUID, name: String) {
        guard canModifyVault else { return }
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty,
              let index = payload.records.firstIndex(where: { $0.id == id }),
              payload.records[index].name != cleanName
        else { return }

        payload.records[index].name = cleanName
        payload.records[index].updatedAt = Date()
        scheduleRecordSave()
    }

    func updateRecordContent(id: UUID, content: String) {
        guard canModifyVault,
              let index = payload.records.firstIndex(where: { $0.id == id }),
              payload.records[index].content != content
        else { return }

        payload.records[index].content = content
        payload.records[index].updatedAt = Date()

        scheduleRecordSave()
    }

    func updateRecordCategory(id: UUID, categoryID: UUID) {
        guard canModifyVault,
              payload.categories.contains(where: { $0.id == categoryID }),
              let index = payload.records.firstIndex(where: { $0.id == id }),
              payload.records[index].categoryID != categoryID
        else { return }

        payload.records[index].categoryID = categoryID
        payload.records[index].updatedAt = Date()

        if selectedCategoryID != nil {
            selectedCategoryID = categoryID
        }
        scheduleRecordSave()
    }

    func flushPendingRecordSave() {
        recordSaveWorkItem?.cancel()
        recordSaveWorkItem = nil
        persistIfNeeded()
    }

    private func scheduleRecordSave() {
        hasUnsavedChanges = true
        recordSaveWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.recordSaveWorkItem = nil
            self?.persistIfNeeded()
        }
        recordSaveWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: workItem)
    }

    func saveCategory(id: UUID?, name: String, iconName: String) {
        guard canModifyVault else { return }
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return }

        let savedCategoryID: UUID
        if let id,
           let index = payload.categories.firstIndex(where: { $0.id == id }) {
            payload.categories[index].name = cleanName
            payload.categories[index].iconName = iconName
            savedCategoryID = id
        } else {
            let nextOrder = (payload.categories.map(\.sortOrder).max() ?? -1) + 1
            let category = VaultCategory(
                name: cleanName,
                iconName: iconName,
                sortOrder: nextOrder
            )
            payload.categories.append(category)
            savedCategoryID = category.id
        }

        closeRecordPanel()
        selectedCategoryID = savedCategoryID
        keyboardPane = .categories
        ensureSelection()
        persistChanges()
    }

    func requestDeleteCategory(_ id: UUID) {
        guard canModifyVault,
              payload.categories.count > 1,
              category(id: id) != nil
        else { return }
        selectCategory(id)
        alert = .confirmDeleteCategory(id)
    }

    func deleteCategory(_ id: UUID) {
        guard canModifyVault,
              let replacementCategoryID = payload.deleteCategory(id: id)
        else { return }
        if selectedCategoryID == id {
            closeRecordPanel()
            selectedCategoryID = replacementCategoryID
        }
        keyboardPane = .categories
        ensureSelection()
        persistChanges()
    }

    @discardableResult
    func copySelectedRecord() -> Bool {
        guard let record = selectedRecord, !record.content.isEmpty else { return false }
        return copy(record.content)
    }

    @discardableResult
    func copy(_ value: String) -> Bool {
        let item = NSPasteboardItem()
        item.setString("1", forType: BenriPasteboard.internalType)
        item.setString(value, forType: .string)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.writeObjects([item])
    }

    func openDataFolder() {
        let directory = vaultFileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        NSWorkspace.shared.activateFileViewerSelecting([vaultFileURL])
    }

    func createBackup(
        at destinationURL: URL,
        appVersion: String
    ) throws -> VaultBackupManifest {
        flushPendingRecordSave()
        guard !hasUnsavedChanges else { throw VaultOperationError.unsavedChanges }

        return try VaultBackupArchive.create(
            at: destinationURL,
            vaultFileURL: vaultFileURL,
            keyFileURL: keyStore.fileURL,
            appVersion: appVersion
        )
    }

    func validateBackup(at backupURL: URL) throws -> ValidatedVaultBackup {
        try VaultBackupArchive.validate(at: backupURL)
    }

    func restoreBackup(
        _ validatedBackup: ValidatedVaultBackup,
        appVersion: String
    ) throws -> VaultRestoreResult {
        flushPendingRecordSave()
        guard !hasUnsavedChanges else { throw VaultOperationError.unsavedChanges }

        let recoveryBackupURL = try createRecoveryBackupIfPossible(appVersion: appVersion)
        let restoreStore = try fileStoreForRestore()
        closeRecordPanel()
        dismissEditors()

        let payloadBeforeRestore = payload
        let restoredPayload: VaultPayload
        do {
            restoredPayload = try VaultBackupArchive.restore(
                validatedBackup,
                to: restoreStore
            )
        } catch {
            if (try? restoreStore.load()) != payloadBeforeRestore {
                fileStore = nil
                hasUnsavedChanges = false
                fatalErrorMessage = VaultOperationError.restoreFailed.localizedDescription
            }
            throw error
        }
        selectedCategoryID = nil
        selectedRecordID = nil
        searchText = ""
        keyboardPane = .records
        recordPanelMode = .closed
        payload = restoredPayload
        fileStore = restoreStore
        fatalErrorMessage = nil
        hasUnsavedChanges = false
        ensureSelection()

        return VaultRestoreResult(
            backup: validatedBackup,
            recoveryBackupURL: recoveryBackupURL
        )
    }

    func requestReset() {
        alert = .confirmReset
    }

    func resetVault() {
        recordSaveWorkItem?.cancel()
        recordSaveWorkItem = nil
        hasUnsavedChanges = false
        fileStore = nil
        payload = .empty
        selectedCategoryID = nil
        selectedRecordID = nil
        recordPanelMode = .closed
        dismissEditors()

        do {
            if FileManager.default.fileExists(atPath: vaultFileURL.path) {
                try FileManager.default.removeItem(at: vaultFileURL)
            }
            try keyStore.deleteKey()
            fatalErrorMessage = nil
            bootstrap()
        } catch {
            fatalErrorMessage = "重置保险库失败：\(error.localizedDescription)"
            alert = .saveError(error.localizedDescription)
        }
    }

    private func bootstrap() {
        recordSaveWorkItem?.cancel()
        recordSaveWorkItem = nil
        hasUnsavedChanges = false
        fileStore = nil

        do {
            let fileExists = FileManager.default.fileExists(atPath: vaultFileURL.path)
            let keyData: Data

            if fileExists {
                guard let existingKey = try keyStore.loadKey() else {
                    throw VaultBootstrapError.missingKey
                }
                keyData = existingKey
            } else {
                keyData = try keyStore.loadOrCreateKey()
            }

            let store = VaultFileStore(fileURL: vaultFileURL, keyData: keyData)
            let loadedPayload: VaultPayload

            if store.exists {
                var candidate = try store.load()
                if candidate.migrateToCurrentFormat() {
                    try store.save(candidate)
                }
                loadedPayload = candidate
            } else {
                let emptyPayload = VaultPayload.empty
                try store.save(emptyPayload)
                loadedPayload = emptyPayload
            }

            payload = loadedPayload
            fileStore = store
            fatalErrorMessage = nil
            ensureSelection()
        } catch {
            fileStore = nil
            fatalErrorMessage = error.localizedDescription
        }
    }

    private func createRecoveryBackupIfPossible(appVersion: String) throws -> URL? {
        guard canCreateRecoveryBackup else { return nil }

        let backupsDirectory = vaultFileURL
            .deletingLastPathComponent()
            .appendingPathComponent("Backups", isDirectory: true)
        try FileManager.default.createDirectory(
            at: backupsDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: backupsDirectory.path
        )
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss.SSS"
        let backupURL = backupsDirectory.appendingPathComponent(
            "Before restore \(formatter.string(from: Date())).\(VaultBackupArchive.fileExtension)",
            isDirectory: true
        )

        try VaultBackupArchive.create(
            at: backupURL,
            vaultFileURL: vaultFileURL,
            keyFileURL: keyStore.fileURL,
            appVersion: appVersion
        )
        return backupURL
    }

    private func fileStoreForRestore() throws -> VaultFileStore {
        if fileStore != nil {
            guard let persistedKey = try keyStore.loadKey() else {
                throw VaultOperationError.activeKeyUnavailable
            }
            let persistedStore = VaultFileStore(
                fileURL: vaultFileURL,
                keyData: persistedKey
            )
            do {
                guard try persistedStore.load() == payload else {
                    throw VaultOperationError.activeKeyUnavailable
                }
            } catch {
                throw VaultOperationError.activeKeyUnavailable
            }
            return persistedStore
        }

        let keyData = try keyStore.loadOrCreateKeyForRestore()
        return VaultFileStore(fileURL: vaultFileURL, keyData: keyData)
    }

    private func persistChanges() {
        hasUnsavedChanges = true
        persistIfNeeded()
    }

    private func persistIfNeeded() {
        guard hasUnsavedChanges,
              canModifyVault,
              let fileStore
        else { return }

        do {
            try fileStore.save(payload)
            hasUnsavedChanges = false
            if case .saveError = alert {
                alert = nil
            }
        } catch {
            alert = .saveError(error.localizedDescription)
        }
    }

}
