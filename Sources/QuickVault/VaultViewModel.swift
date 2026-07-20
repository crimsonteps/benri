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
            return "保险库文件存在，但本机钥匙串中的解密密钥已丢失。"
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
    @Published var copyNotice: String?

    let vaultFileURL: URL

    private let keyStore: KeychainKeyStore
    private var fileStore: VaultFileStore?
    private var clipboardClearWorkItem: DispatchWorkItem?
    private var copyNoticeWorkItem: DispatchWorkItem?

    init(
        vaultFileURL: URL? = nil,
        keyStore: KeychainKeyStore = KeychainKeyStore()
    ) {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.homeDirectoryForCurrentUser

        self.vaultFileURL = vaultFileURL
            ?? applicationSupport
                .appendingPathComponent("QuickVault", isDirectory: true)
                .appendingPathComponent("vault.qv")
        self.keyStore = keyStore

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
        ensureSelection()
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

    func beginEditingSelectedRecord() {
        guard let selectedRecordID else { return }
        recordEditor = RecordEditorContext(recordID: selectedRecordID)
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
        fields: [RecordField]
    ) {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return }

        let safeCategoryID = payload.categories.contains(where: { $0.id == categoryID })
            ? categoryID
            : VaultDefaults.otherCategoryID
        let normalizedFields = fields.enumerated().compactMap { index, field -> RecordField? in
            let cleanLabel = field.label.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanLabel.isEmpty || !field.value.isEmpty else { return nil }
            return RecordField(
                id: field.id,
                label: cleanLabel.isEmpty ? "字段" : cleanLabel,
                value: field.value,
                isSensitive: field.isSensitive,
                sortOrder: index
            )
        }

        let recordID: UUID
        if let id, let index = payload.records.firstIndex(where: { $0.id == id }) {
            payload.records[index].name = cleanName
            payload.records[index].categoryID = safeCategoryID
            payload.records[index].fields = normalizedFields
            payload.records[index].updatedAt = Date()
            recordID = id
        } else {
            let record = VaultRecord(
                name: cleanName,
                categoryID: safeCategoryID,
                fields: normalizedFields
            )
            payload.records.append(record)
            recordID = record.id
        }

        selectedCategoryID = safeCategoryID
        selectedRecordID = recordID
        persist()
    }

    func requestDeleteRecord(_ id: UUID) {
        alert = .confirmDeleteRecord(id)
    }

    func deleteRecord(_ id: UUID) {
        payload.records.removeAll(where: { $0.id == id })
        ensureSelection()
        persist()
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

    func copy(_ value: String, sensitive: Bool) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
        showCopyNotice()

        clipboardClearWorkItem?.cancel()
        guard sensitive else { return }

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

    private func showCopyNotice() {
        copyNoticeWorkItem?.cancel()
        copyNotice = "已复制"

        let workItem = DispatchWorkItem { [weak self] in
            self?.copyNotice = nil
        }
        copyNoticeWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4, execute: workItem)
    }
}
