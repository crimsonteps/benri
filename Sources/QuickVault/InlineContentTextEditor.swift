import AppKit
import SwiftUI

struct InlineContentTextEditor: NSViewRepresentable {
    @Binding var text: String
    let usesMonospacedFont: Bool
    let onFocusChange: (Bool) -> Void
    let onDelete: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.scrollerStyle = .overlay

        let textView = RecordContentTextView()
        textView.delegate = context.coordinator
        textView.string = text
        textView.font = editorFont
        textView.textColor = .labelColor
        textView.drawsBackground = false
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 5, height: 5)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: scrollView.contentSize.width,
            height: .greatestFiniteMagnitude
        )
        textView.makeContextMenu = { [weak coordinator = context.coordinator] in
            coordinator?.makeContextMenu()
        }

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? RecordContentTextView else { return }

        if textView.string != text {
            textView.string = text
        }
        if textView.font != editorFont {
            textView.font = editorFont
        }
    }

    private var editorFont: NSFont {
        usesMonospacedFont
            ? .monospacedSystemFont(ofSize: 14, weight: .regular)
            : .systemFont(ofSize: 14)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: InlineContentTextEditor

        init(parent: InlineContentTextEditor) {
            self.parent = parent
        }

        func textDidBeginEditing(_ notification: Notification) {
            parent.onFocusChange(true)
        }

        func textDidEndEditing(_ notification: Notification) {
            parent.onFocusChange(false)
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }

        func makeContextMenu() -> NSMenu {
            let menu = NSMenu()
            menu.addItem(NSMenuItem(title: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: ""))
            menu.addItem(NSMenuItem(title: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: ""))
            menu.addItem(NSMenuItem(title: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: ""))
            menu.addItem(.separator())

            let deleteItem = NSMenuItem(
                title: "删除记录",
                action: #selector(deleteRecord),
                keyEquivalent: ""
            )
            deleteItem.target = self
            menu.addItem(deleteItem)
            return menu
        }

        @objc private func deleteRecord() {
            parent.onDelete()
        }
    }
}

private final class RecordContentTextView: NSTextView {
    var makeContextMenu: (() -> NSMenu?)?

    override func menu(for event: NSEvent) -> NSMenu? {
        makeContextMenu?() ?? super.menu(for: event)
    }
}
