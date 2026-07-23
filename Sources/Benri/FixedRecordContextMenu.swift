import AppKit
import SwiftUI

struct FixedRecordContextMenu: NSViewRepresentable {
    let prepare: () -> Void
    let editAction: () -> Void
    let deleteAction: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
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
        return view
    }

    func updateNSView(_ nsView: RightClickCaptureView, context: Context) {
        context.coordinator.prepare = prepare
        context.coordinator.editAction = editAction
        context.coordinator.deleteAction = deleteAction
    }

    final class Coordinator: NSObject {
        var prepare: () -> Void
        var editAction: () -> Void
        var deleteAction: () -> Void

        init(
            prepare: @escaping () -> Void,
            editAction: @escaping () -> Void,
            deleteAction: @escaping () -> Void
        ) {
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
