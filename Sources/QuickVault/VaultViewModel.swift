import AppKit
import Foundation
import QuickVaultCore

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
    @Published var isEditingRecordName = false

    let vaultFileURL: URL

    private let keyStore: VaultKeyStore
    private var fileStore: VaultFileStore?
    private var clipboardClearWorkItem: DispatchWorkItem?
    private var recordSaveWorkItem: DispatchWorkItem?

    init(
        vaultFileURL: URL? = nil,
        keyStore: VaultKeyStore? = nil
    ) {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.homeDirectoryForCurrentUser

        let resolvedVaultFileURL = vaultFileURL
            ?? applicationSupport
                .appendingPathComponent("QuickVault", isDirectory: true)
                .appendingPathComponent("vault.qv")
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
        selectedCategoryID = categoryID
        keyboardPane = .categories
        ensureSelection()
    }

    func moveCategorySelection(_ direction: Int) {
        let categoryIDs: [UUID?] = [nil] + sortedCategories.map { Optional($0.id) }
        guard !categoryIDs.isEmpty else { return }

        let currentIndex = categoryIDs.firstIndex(where: { $0 == selectedCategoryID }) ?? 0
        let nextIndex = (currentIndex + direction + categoryIDs.count) % categoryIDs.count
        selectedCategoryID = categoryIDs[nextIndex]
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

    func beginNewRecord() {
        recordEditor = RecordEditorContext(recordID: nil)
    }

    func beginNewCategory() {
        categoryEditor = CategoryEditorContext(categoryID: nil)
    }

    func beginRenamingCategory(_ id: UUID) {
        guard let category = category(id: id), !category.isBuiltIn else { return }
        categoryEditor = CategoryEditorContext(categoryID: id)
    }

    func saveRecord(
        id: UUID?,
        name: String,
        categoryID: UUID,
        content: String
    ) {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return }

        let safeCategoryID = payload.categories.contains(where: { $0.id == categoryID })
            ? categoryID
            : VaultDefaults.otherCategoryID

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
        persist()
    }

    func deleteRecord(_ id: UUID) {
        flushPendingRecordSave()
        payload.records.removeAll(where: { $0.id == id })
        ensureSelection()
        persist()
    }

    func updateRecordName(id: UUID, name: String) {
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
        guard let index = payload.records.firstIndex(where: { $0.id == id }),
              payload.records[index].content != content
        else { return }

        payload.records[index].content = content
        payload.records[index].updatedAt = Date()

        scheduleRecordSave()
    }

    func flushPendingRecordSave() {
        guard recordSaveWorkItem != nil else { return }
        recordSaveWorkItem?.cancel()
        recordSaveWorkItem = nil
        persist()
    }

    private func scheduleRecordSave() {
        recordSaveWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.recordSaveWorkItem = nil
            self?.persist()
        }
        recordSaveWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: workItem)
    }

    func saveCategory(id: UUID?, name: String) {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return }

        if let id,
           let index = payload.categories.firstIndex(where: { $0.id == id }),
           !payload.categories[index].isBuiltIn {
            payload.categories[index].name = cleanName
        } else {
            let nextOrder = (payload.categories.map(\.sortOrder).max() ?? -1) + 1
            let category = VaultCategory(name: cleanName, sortOrder: nextOrder)
            payload.categories.append(category)
            selectedCategoryID = category.id
        }

        ensureSelection()
        persist()
    }

    func requestDeleteCategory(_ id: UUID) {
        guard let category = category(id: id), !category.isBuiltIn else { return }
        alert = .confirmDeleteCategory(id)
    }

    func deleteCategory(_ id: UUID) {
        payload.deleteCustomCategory(id: id)
        if selectedCategoryID == id {
            selectedCategoryID = VaultDefaults.otherCategoryID
        }
        ensureSelection()
        persist()
    }

    @discardableResult
    func copySelectedRecord() -> Bool {
        guard let record = selectedRecord, !record.content.isEmpty else { return false }
        copy(record.content)
        return true
    }

    func copy(_ value: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)

        clipboardClearWorkItem?.cancel()
        let workItem = DispatchWorkItem {
            if NSPasteboard.general.string(forType: .string) == value {
                NSPasteboard.general.clearContents()
            }
        }
        clipboardClearWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 30, execute: workItem)
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
        do {
            recordSaveWorkItem?.cancel()
            recordSaveWorkItem = nil
            try fileStore?.remove()
            try keyStore.deleteKey()
            fileStore = nil
            fatalErrorMessage = nil
            payload = .empty
            selectedCategoryID = nil
            selectedRecordID = nil
            bootstrap()
        } catch {
            alert = .saveError(error.localizedDescription)
        }
    }

    private func bootstrap() {
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
            fileStore = store

            if store.exists {
                payload = try store.load()
                if payload.migrateToCurrentFormat() {
                    try store.save(payload)
                }
            } else {
                payload = .empty
                try store.save(payload)
            }

            fatalErrorMessage = nil
            ensureSelection()
        } catch {
            fatalErrorMessage = error.localizedDescription
        }
    }

    private func persist() {
        do {
            try fileStore?.save(payload)
        } catch {
            alert = .saveError(error.localizedDescription)
        }
    }

}
