import Foundation
import BenriCore

enum PaletteMode: String {
    case commonText
    case clipboard
}

enum PaletteAction: String, Identifiable {
    case paste
    case copy
    case pasteKeepingOpen
    case editRecord
    case togglePin
    case revealImage
    case deleteRecord
    case deleteClipboard
    case clearClipboard

    var id: String { rawValue }

    static func available(
        mode: PaletteMode,
        record: VaultRecord?,
        clipboardItem: ClipboardItem?
    ) -> [PaletteAction] {
        switch mode {
        case .commonText:
            guard record != nil else { return [] }
            return [.paste, .copy, .editRecord, .deleteRecord]
        case .clipboard:
            guard let clipboardItem else { return [] }
            var actions: [PaletteAction] = [.paste, .copy, .pasteKeepingOpen, .togglePin]
            if clipboardItem.kind == .image { actions.append(.revealImage) }
            actions.append(contentsOf: [.deleteClipboard, .clearClipboard])
            return actions
        }
    }
}

@MainActor
final class PaletteState: ObservableObject {
    @Published var mode: PaletteMode = .commonText
    @Published var clipboardQuery = ""
    @Published var selectedClipboardID: UUID?
    @Published var confirmation: PaletteConfirmation?
    @Published var actionMenuOpen = false
    @Published var actionMenuSelection = 0

    func showCommonText() {
        mode = .commonText
    }

    func showClipboard() {
        mode = .clipboard
    }

    func toggleMode() {
        closeActionMenu()
        mode = mode == .commonText ? .clipboard : .commonText
    }

    func toggleActionMenu(actions: [PaletteAction]) {
        if actionMenuOpen {
            closeActionMenu()
        } else {
            openActionMenu(actions: actions)
        }
    }

    func openActionMenu(actions: [PaletteAction]) {
        guard !actions.isEmpty else { return }
        actionMenuSelection = 0
        actionMenuOpen = true
    }

    func closeActionMenu() {
        actionMenuOpen = false
        actionMenuSelection = 0
    }

    func moveActionMenuSelection(_ direction: Int, actions: [PaletteAction]) {
        guard actionMenuOpen, !actions.isEmpty else { return }
        actionMenuSelection = min(
            max(actionMenuSelection + direction, 0),
            actions.count - 1
        )
    }

    func selectedAction(in actions: [PaletteAction]) -> PaletteAction? {
        guard actionMenuOpen, actions.indices.contains(actionMenuSelection) else { return nil }
        return actions[actionMenuSelection]
    }

    func clipboardResults(in store: ClipboardStore) -> [ClipboardItem] {
        store.search(clipboardQuery)
    }

    func selectedClipboardItem(in store: ClipboardStore) -> ClipboardItem? {
        let results = clipboardResults(in: store)
        guard let selectedClipboardID else { return results.first }
        return results.first { $0.id == selectedClipboardID } ?? results.first
    }

    func ensureClipboardSelection(in store: ClipboardStore) {
        let results = clipboardResults(in: store)
        if let selectedClipboardID,
           results.contains(where: { $0.id == selectedClipboardID }) {
            return
        }
        selectedClipboardID = results.first?.id
    }

    func moveClipboardSelection(_ direction: Int, in store: ClipboardStore) {
        let results = clipboardResults(in: store)
        guard !results.isEmpty else {
            selectedClipboardID = nil
            return
        }
        guard let selectedClipboardID,
              let index = results.firstIndex(where: { $0.id == selectedClipboardID })
        else {
            self.selectedClipboardID = results.first?.id
            return
        }
        self.selectedClipboardID = results[
            min(max(index + direction, 0), results.count - 1)
        ].id
    }
}

enum PaletteConfirmation: Identifiable, Equatable {
    case enableClipboard
    case clearClipboard
    case deleteClipboard(UUID)

    var id: String {
        switch self {
        case .enableClipboard: "enableClipboard"
        case .clearClipboard: "clearClipboard"
        case let .deleteClipboard(id): "deleteClipboard-\(id.uuidString)"
        }
    }
}
