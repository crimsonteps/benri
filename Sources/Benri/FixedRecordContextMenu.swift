import AppKit
import SwiftUI

@MainActor
final class RecordContextMenuAnchor {
    private(set) weak var selectedView: NSView?

    func update(view: NSView, isSelected: Bool) {
        if isSelected {
            selectedView = view
        } else if selectedView === view {
            selectedView = nil
        }
    }

    func remove(view: NSView) {
        if selectedView === view {
            selectedView = nil
        }
    }
}

struct FixedRecordContextMenu: NSViewRepresentable {
    let anchor: RecordContextMenuAnchor
    let isSelected: Bool
    let prepare: () -> Void
    let editAction: () -> Void
    let deleteAction: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            anchor: anchor,
            prepare: prepare,
            editAction: editAction,
            deleteAction: deleteAction
        )
    }

    func makeNSView(context: Context) -> RightClickCaptureView {
        let view = RightClickCaptureView()
        view.onRightClick = { [weak coordinator = context.coordinator] sourceView in
            coordinator?.presentMenu(from: sourceView)
        }
        anchor.update(view: view, isSelected: isSelected)
        return view
    }

    func updateNSView(_ nsView: RightClickCaptureView, context: Context) {
        anchor.update(view: nsView, isSelected: isSelected)
        context.coordinator.prepare = prepare
        context.coordinator.editAction = editAction
        context.coordinator.deleteAction = deleteAction
    }

    static func dismantleNSView(_ nsView: RightClickCaptureView, coordinator: Coordinator) {
        coordinator.anchor.remove(view: nsView)
    }

    final class Coordinator: NSObject {
        let anchor: RecordContextMenuAnchor
        var prepare: () -> Void
        var editAction: () -> Void
        var deleteAction: () -> Void

        init(
            anchor: RecordContextMenuAnchor,
            prepare: @escaping () -> Void,
            editAction: @escaping () -> Void,
            deleteAction: @escaping () -> Void
        ) {
            self.anchor = anchor
            self.prepare = prepare
            self.editAction = editAction
            self.deleteAction = deleteAction
        }

        func presentMenu(from view: NSView) {
            prepare()

            let menu = NSMenu()
            menu.autoenablesItems = false

            let editItem = NSMenuItem(
                title: "编辑",
                action: #selector(editRecord),
                keyEquivalent: ""
            )
            editItem.target = self
            menu.addItem(editItem)

            let deleteItem = NSMenuItem(
                title: "删除",
                action: #selector(deleteRecord),
                keyEquivalent: ""
            )
            deleteItem.target = self
            menu.addItem(deleteItem)

            menu.popUp(
                positioning: nil,
                at: NSPoint(x: view.bounds.maxX - 6, y: view.bounds.midY),
                in: view
            )
        }

        @objc private func editRecord() {
            editAction()
        }

        @objc private func deleteRecord() {
            deleteAction()
        }
    }
}

final class RightClickCaptureView: NSView {
    var onRightClick: ((NSView) -> Void)?

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard bounds.contains(point),
              NSApp.currentEvent?.type == .rightMouseDown
        else { return nil }
        return self
    }

    override func rightMouseDown(with event: NSEvent) {
        onRightClick?(self)
    }
}
