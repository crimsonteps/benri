import AppKit
import Carbon.HIToolbox
import SwiftUI

struct CategoryEditorView: View {
    private enum FocusTarget: Hashable {
        case name
        case icons
    }

    fileprivate enum IconMove {
        case up
        case down
        case left
        case right
    }

    private static let iconColumnCount = 7

    @ObservedObject var store: VaultViewModel
    let context: CategoryEditorContext

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var selectedIconName: String
    @FocusState private var focusedTarget: FocusTarget?

    init(store: VaultViewModel, context: CategoryEditorContext) {
        self.store = store
        self.context = context
        let category = context.categoryID.flatMap(store.category(id:))
        _name = State(initialValue: category?.name ?? "")
        _selectedIconName = State(
            initialValue: category.map(CategoryIconCatalog.iconName(for:)) ?? "folder"
        )
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            TextField("分类名称", text: $name)
                .textFieldStyle(.plain)
                .focused($focusedTarget, equals: .name)
                .padding(.horizontal, 11)
                .frame(height: 34)
                .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 9))
                .overlay {
                    RoundedRectangle(cornerRadius: 9)
                        .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                }

            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.fixed(36), spacing: 8),
                    count: 7
                ),
                alignment: .leading,
                spacing: 8
            ) {
                ForEach(CategoryIconCatalog.options) { option in
                    Button {
                        selectedIconName = option.name
                        focusedTarget = .icons
                    } label: {
                        Image(systemName: option.name)
                            .font(.system(size: 14, weight: .medium))
                            .frame(width: 34, height: 32)
                            .background(
                                selectedIconName == option.name
                                    ? Color.accentColor.opacity(0.2)
                                    : Color.primary.opacity(0.045),
                                in: RoundedRectangle(cornerRadius: 8)
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(
                                        selectedIconName == option.name
                                            ? Color.accentColor.opacity(0.7)
                                            : Color.primary.opacity(0.08),
                                        lineWidth: 1
                                    )
                            }
                    }
                    .buttonStyle(.plain)
                    .help(option.label)
                }
            }
            .focusable()
            .focused($focusedTarget, equals: .icons)

            HStack {
                Spacer()
                Button("取消", action: cancel)
                .keyboardShortcut(.cancelAction)

                Button("保存", action: save)
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
            }
        }
        .padding(22)
        .frame(width: 380)
        .benriGlass(cornerRadius: 18)
        .background {
            CategoryEditorKeyboardMonitor(
                focusName: {
                    focusedTarget = .name
                },
                focusIcons: {
                    focusedTarget = .icons
                },
                moveIcon: moveIcon,
                isIconGridFocused: focusedTarget == .icons
            )
        }
        .onAppear {
            DispatchQueue.main.async {
                focusedTarget = .name
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .benriSaveActiveEditor)) { _ in
            save()
        }
        .onReceive(NotificationCenter.default.publisher(for: .benriCancelActiveEditor)) { _ in
            cancel()
        }
    }

    private func save() {
        guard canSave else { return }
        store.saveCategory(
            id: context.categoryID,
            name: name,
            iconName: selectedIconName
        )
        dismiss()
    }

    private func cancel() {
        dismiss()
    }

    private func moveIcon(_ move: IconMove) {
        let options = CategoryIconCatalog.options
        guard !options.isEmpty else { return }

        let currentIndex = options.firstIndex(where: { $0.name == selectedIconName }) ?? 0
        let column = currentIndex % Self.iconColumnCount
        let nextIndex: Int

        switch move {
        case .up:
            nextIndex = currentIndex >= Self.iconColumnCount
                ? currentIndex - Self.iconColumnCount
                : currentIndex
        case .down:
            let candidate = currentIndex + Self.iconColumnCount
            nextIndex = candidate < options.count ? candidate : currentIndex
        case .left:
            nextIndex = column > 0 ? currentIndex - 1 : currentIndex
        case .right:
            let canMoveRight = column < Self.iconColumnCount - 1
                && currentIndex + 1 < options.count
            nextIndex = canMoveRight ? currentIndex + 1 : currentIndex
        }

        selectedIconName = options[nextIndex].name
    }
}

private struct CategoryEditorKeyboardMonitor: NSViewRepresentable {
    let focusName: () -> Void
    let focusIcons: () -> Void
    let moveIcon: (CategoryEditorView.IconMove) -> Void
    let isIconGridFocused: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.hostView = view
        context.coordinator.startMonitoring()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.hostView = nsView
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.stopMonitoring()
    }

    final class Coordinator {
        var parent: CategoryEditorKeyboardMonitor
        weak var hostView: NSView?

        private var monitor: Any?

        init(parent: CategoryEditorKeyboardMonitor) {
            self.parent = parent
        }

        deinit {
            stopMonitoring()
        }

        func startMonitoring() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                self?.handle(event) ?? event
            }
        }

        func stopMonitoring() {
            guard let monitor else { return }
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }

        private func handle(_ event: NSEvent) -> NSEvent? {
            guard hostView?.window?.isKeyWindow == true else { return event }

            let modifiers = event.modifierFlags.intersection([
                .command,
                .option,
                .control,
                .shift
            ])

            if event.keyCode == kVK_Tab,
               modifiers.isEmpty || modifiers == [.shift] {
                if parent.isIconGridFocused {
                    parent.focusName()
                } else {
                    parent.focusIcons()
                }
                return nil
            }

            guard parent.isIconGridFocused, modifiers.isEmpty else { return event }

            switch Int(event.keyCode) {
            case kVK_UpArrow:
                parent.moveIcon(.up)
            case kVK_DownArrow:
                parent.moveIcon(.down)
            case kVK_LeftArrow:
                parent.moveIcon(.left)
            case kVK_RightArrow:
                parent.moveIcon(.right)
            default:
                return event
            }
            return nil
        }
    }
}
