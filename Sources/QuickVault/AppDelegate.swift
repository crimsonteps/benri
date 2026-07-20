import AppKit
import QuickVaultCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store: VaultViewModel = {
        let environment = ProcessInfo.processInfo.environment
        let testFileURL = environment["QUICKVAULT_DATA_FILE"].map {
            URL(fileURLWithPath: $0)
        }
        let keychainService = environment["QUICKVAULT_KEYCHAIN_SERVICE"]
            ?? "com.crimsonteps.quickvault"
        return VaultViewModel(
            vaultFileURL: testFileURL,
            keyStore: KeychainKeyStore(service: keychainService)
        )
    }()
    private var panelController: PanelController!
    private var hotKeyManager: HotKeyManager!
    private var statusItem: NSStatusItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        panelController = PanelController(store: store)
        configureStatusItem()

        hotKeyManager = HotKeyManager { [weak self] in
            self?.panelController.toggle()
        }

        if !hotKeyManager.registerOptionSpace() {
            addHotKeyFailureItem()
        }

        if CommandLine.arguments.contains("--show") {
            DispatchQueue.main.async { [weak self] in
                self?.panelController.show()
            }
        }
    }

    @objc private func openPanel() {
        panelController.show()
    }

    @objc private func newRecord() {
        panelController.showNewRecord()
    }

    @objc private func openDataFolder() {
        store.openDataFolder()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func configureStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "lock.square.stack",
                accessibilityDescription: "QuickVault"
            )
            button.toolTip = "QuickVault"
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "打开 QuickVault", action: #selector(openPanel), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "新建记录", action: #selector(newRecord), keyEquivalent: "n"))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "打开数据目录", action: #selector(openDataFolder), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出 QuickVault", action: #selector(quit), keyEquivalent: "q"))

        for item in menu.items {
            item.target = self
        }
        statusItem.menu = menu
    }

    private func addHotKeyFailureItem() {
        guard let menu = statusItem.menu else { return }
        let item = NSMenuItem(title: "⌥Space 已被其他应用占用", action: nil, keyEquivalent: "")
        item.isEnabled = false
        menu.insertItem(item, at: 0)
        menu.insertItem(.separator(), at: 1)
    }
}
