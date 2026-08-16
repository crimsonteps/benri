import AppKit
import BenriCore

enum BenriPasteboard {
    static let internalType = NSPasteboard.PasteboardType("com.crimsonteps.benri.internal")
}

@MainActor
final class ClipboardManager {
    static let maxTextLength = 32_000
    static let sensitiveTypes: Set<NSPasteboard.PasteboardType> = [
        .init("org.nspasteboard.ConcealedType"),
        .init("org.nspasteboard.TransientType"),
        .init("com.apple.is-sensitive")
    ]

    private let store: ClipboardStore
    private let settings: AppSettings
    private var timer: Timer?
    private var lastChangeCount = 0
    private var sessionObservers: [NSObjectProtocol] = []

    init(store: ClipboardStore, settings: AppSettings) {
        self.store = store
        self.settings = settings
    }

    deinit {
        timer?.invalidate()
        for observer in sessionObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }

    func updateMonitoring() {
        if settings.clipboardHistoryEnabled && settings.hasConfirmedClipboardHistory {
            start()
        } else {
            stop()
        }
    }

    func start() {
        guard timer == nil else { return }
        installSessionObserversIfNeeded()
        lastChangeCount = NSPasteboard.general.changeCount
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func writeText(_ text: String) -> Bool {
        drainBeforeInternalWrite()
        let item = NSPasteboardItem()
        item.setString("1", forType: BenriPasteboard.internalType)
        item.setString(text, forType: .string)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let result = pasteboard.writeObjects([item])
        synchronizeAfterInternalWrite()
        return result
    }

    func write(_ item: ClipboardItem) -> Bool {
        switch item.kind {
        case .text:
            return item.text.map(writeText) ?? false
        case .image:
            guard let url = store.imageURL(for: item),
                  let data = try? Data(contentsOf: url)
            else { return false }
            drainBeforeInternalWrite()
            let pasteboardItem = NSPasteboardItem()
            pasteboardItem.setString("1", forType: BenriPasteboard.internalType)
            pasteboardItem.setData(data, forType: .png)
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            let result = pasteboard.writeObjects([pasteboardItem])
            synchronizeAfterInternalWrite()
            return result
        }
    }

    private func installSessionObserversIfNeeded() {
        guard sessionObservers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        sessionObservers = [
            center.addObserver(
                forName: NSWorkspace.sessionDidResignActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.stop() }
            },
            center.addObserver(
                forName: NSWorkspace.sessionDidBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.updateMonitoring() }
            }
        ]
    }

    private func drainBeforeInternalWrite() {
        if timer != nil { poll() }
    }

    private func synchronizeAfterInternalWrite() {
        lastChangeCount = NSPasteboard.general.changeCount
    }

    private func poll() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount
        let types = Set(pasteboard.types ?? [])
        guard !types.contains(BenriPasteboard.internalType),
              types.isDisjoint(with: Self.sensitiveTypes)
        else { return }

        let sourceBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        if let sourceBundleID, settings.clipboardExcludedApps.contains(sourceBundleID) {
            return
        }

        if let text = pasteboard.string(forType: .string),
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           text.count <= Self.maxTextLength {
            store.addText(text, sourceBundleID: sourceBundleID)
            return
        }

        guard let type = pasteboard.availableType(from: [.png, .tiff]),
              let data = pasteboard.data(forType: type)
        else { return }
        let clipboardStore = store
        Task.detached(priority: .utility) {
            let pngData: Data?
            if type == .png {
                pngData = data
            } else {
                pngData = NSBitmapImageRep(data: data)?.representation(
                    using: .png,
                    properties: [:]
                )
            }
            guard let pngData else { return }
            await MainActor.run {
                _ = try? clipboardStore.addImage(pngData, sourceBundleID: sourceBundleID)
            }
        }
    }
}
