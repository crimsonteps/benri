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

enum KeyboardPane {
    case categories
    case records
    case value
}

enum RecordPanelMode: Equatable {
    case closed
    case preview
    case edit
}

enum VaultAlert: Identifiable, Equatable {
    case saveError(String)
    case confirmReset
    case confirmDeleteCategory(UUID)

    var id: String {
        switch self {
        case let .saveError(message):
            return "save-\(message)"
        case .confirmReset:
            return "reset"
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
    @Published var keyboardPane: KeyboardPane = .records
    @Published var recordPanelMode: RecordPanelMode = .closed
    @Published var isEditingRecordName = false

    let vaultFileURL: URL

    private let keyStore: VaultKeyStore
    private var fileStore: VaultFileStore?
    private var recordSaveWorkItem: DispatchWorkItem?
    private var hasUnsavedChanges = false

    init(
        vaultFileURL: URL? = nil,
        keyStore: VaultKeyStore? = nil
    ) {
        let resolvedVaultFileURL = vaultFileURL
            ?? VaultStorage.defaultVaultFileURL()
        self.vaultFileURL = resolvedVaultFileURL
        self.keyStore = keyStore ?? VaultKeyStore(
            fileURL: resolvedVaultFileURL
                .deletingLastPathComponent()
                .appendingPathComponent("vault.key")
        )

        bootstrap()
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
        payload.filteredRecords(categoryID: selectedCategoryID, query: searchText)
    }

    var selectedRecord: VaultRecord? {
        guard let selectedRecordID else { return nil }
        return payload.records.first(where: { $0.id == selectedRecordID })
    }

    var canModifyVault: Bool {
        fatalErrorMessage == nil && fileStore != nil
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
        switch keyboardPane {
        case .categories:
            break
        case .records:
            keyboardPane = .categories
        case .value:
            keyboardPane = .records
        }
    }

    func moveKeyboardPaneRight() {
        switch keyboardPane {
        case .categories:
            keyboardPane = .records
        case .records, .value:
            break
        }
    }

    func ensureSelection() {
        let records = filteredRecords
        if let selectedRecordID, records.contains(where: { $0.id == selectedRecordID }) {
            return
        }
        selectedRecordID = records.first?.id
    }

    func moveSelection(_ direction: Int) {
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
        selectedRecordID = id
        recordPanelMode = .edit
        keyboardPane = .value
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
        recordEditor = RecordEditorContext(recordID: nil)
    }

    func beginNewCategory() {
        guard canModifyVault else { return }
        closeRecordPanel()
        categoryEditor = CategoryEditorContext(categoryID: nil)
    }

    func beginEditingCategory(_ id: UUID) {
        guard canModifyVault,
              category(id: id) != nil
        else { return }
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

        selectedCategoryID = safeCategoryID
        selectedRecordID = recordID
        recordPanelMode = .closed
        persistChanges()
    }

    func deleteRecord(_ id: UUID) {
        guard canModifyVault else { return }
        if selectedRecordID == id {
            closeRecordPanel()
        }
        flushPendingRecordSave()
        payload.records.removeAll(where: { $0.id == id })
        ensureSelection()
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

        if let id,
           let index = payload.categories.firstIndex(where: { $0.id == id }) {
            payload.categories[index].name = cleanName
            payload.categories[index].iconName = iconName
        } else {
            let nextOrder = (payload.categories.map(\.sortOrder).max() ?? -1) + 1
            let category = VaultCategory(
                name: cleanName,
                iconName: iconName,
                sortOrder: nextOrder
            )
            payload.categories.append(category)
            selectedCategoryID = category.id
        }

        ensureSelection()
        persistChanges()
    }

    func requestDeleteCategory(_ id: UUID) {
        guard canModifyVault,
              payload.categories.count > 1,
              category(id: id) != nil
        else { return }
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
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.setString(value, forType: .string)
    }

    func openDataFolder() {
        let directory = vaultFileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        NSWorkspace.shared.activateFileViewerSelecting([vaultFileURL])
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
