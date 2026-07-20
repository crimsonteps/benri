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
        configureMainMenu()
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

    private func configureMainMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: "QuickVault")
        appMenu.addItem(
            withTitle: "退出 QuickVault",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")

        let redoItem = editMenu.addItem(
            withTitle: "重做",
            action: Selector(("redo:")),
            keyEquivalent: "z"
        )
        redoItem.keyEquivalentModifierMask = [.command, .shift]

        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)

        NSApp.mainMenu = mainMenu
    }

    private func addHotKeyFailureItem() {
        guard let menu = statusItem.menu else { return }
        let item = NSMenuItem(title: "⌥Space 已被其他应用占用", action: nil, keyEquivalent: "")
        item.isEnabled = false
        menu.insertItem(item, at: 0)
        menu.insertItem(.separator(), at: 1)
    }
}
