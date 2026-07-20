import AppKit
import Combine
import QuickVaultCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = AppSettings()
    private let store: VaultViewModel = {
        let environment = ProcessInfo.processInfo.environment
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.homeDirectoryForCurrentUser
        let vaultFileURL = environment["QUICKVAULT_DATA_FILE"]
            .map { URL(fileURLWithPath: $0) }
            ?? applicationSupport
                .appendingPathComponent("QuickVault", isDirectory: true)
                .appendingPathComponent("vault.qv")
        let keychainService = environment["QUICKVAULT_KEYCHAIN_SERVICE"]
            ?? "com.crimsonteps.quickvault"
        return VaultViewModel(
            vaultFileURL: vaultFileURL,
            keyStore: VaultKeyStore(
                fileURL: vaultFileURL
                    .deletingLastPathComponent()
                    .appendingPathComponent("vault.key"),
                legacyKeychain: KeychainKeyStore(service: keychainService)
            )
        )
    }()
    private var panelController: PanelController!
    private var hotKeyManager: HotKeyManager!
    private var statusItem: NSStatusItem!
    private var settingsWindowController: SettingsWindowController!
    private var hotKeyMenuItems: [GlobalHotKey: NSMenuItem] = [:]
    private var hotKeyFailureItem: NSMenuItem?
    private var cancellables = Set<AnyCancellable>()

    private static let hotKeyDefaultsKey = "globalHotKey"

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureAppearance()
        configureMainMenu()
        panelController = PanelController(store: store, settings: settings)
        settingsWindowController = SettingsWindowController(settings: settings)
        configureStatusItem()

        hotKeyManager = HotKeyManager { [weak self] in
            self?.panelController.toggle()
        }

        registerSavedHotKey()

        if CommandLine.arguments.contains("--show")
            || ProcessInfo.processInfo.environment["QUICKVAULT_SHOW_ON_LAUNCH"] == "1" {
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

    @objc private func openSettings() {
        settingsWindowController.show()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    @objc private func selectHotKey(_ sender: NSMenuItem) {
        guard
            let rawValue = sender.representedObject as? String,
            let hotKey = GlobalHotKey(rawValue: rawValue)
        else { return }

        let currentHotKey = savedHotKey
        guard hotKey != currentHotKey else { return }

        if hotKeyManager.register(hotKey) {
            UserDefaults.standard.set(hotKey.rawValue, forKey: Self.hotKeyDefaultsKey)
            updateHotKeyMenu(selected: hotKey)
            hotKeyFailureItem?.isHidden = true
        } else {
            showHotKeyFailure(hotKey)
        }
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
        menu.addItem(makeHotKeyMenuItem())

        let failureItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        failureItem.isEnabled = false
        failureItem.isHidden = true
        menu.addItem(failureItem)
        hotKeyFailureItem = failureItem

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "设置…", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "打开数据目录", action: #selector(openDataFolder), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出 QuickVault", action: #selector(quit), keyEquivalent: "q"))

        for item in menu.items {
            item.target = self
        }
        statusItem.menu = menu
    }

    private func makeHotKeyMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "唤起快捷键", action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: "唤起快捷键")

        for hotKey in GlobalHotKey.allCases {
            let hotKeyItem = NSMenuItem(
                title: hotKey.title,
                action: #selector(selectHotKey(_:)),
                keyEquivalent: ""
            )
            hotKeyItem.target = self
            hotKeyItem.representedObject = hotKey.rawValue
            hotKeyMenuItems[hotKey] = hotKeyItem
            submenu.addItem(hotKeyItem)
        }

        item.submenu = submenu
        return item
    }

    private var savedHotKey: GlobalHotKey {
        UserDefaults.standard.string(forKey: Self.hotKeyDefaultsKey)
            .flatMap(GlobalHotKey.init(rawValue:))
            ?? .optionSpace
    }

    private func registerSavedHotKey() {
        let hotKey = savedHotKey
        updateHotKeyMenu(selected: hotKey)
        if !hotKeyManager.register(hotKey) {
            showHotKeyFailure(hotKey)
        }
    }

    private func updateHotKeyMenu(selected: GlobalHotKey) {
        for (hotKey, item) in hotKeyMenuItems {
            item.state = hotKey == selected ? .on : .off
        }
        statusItem.button?.toolTip = "QuickVault · \(selected.title)"
    }

    private func showHotKeyFailure(_ hotKey: GlobalHotKey) {
        hotKeyFailureItem?.title = "\(hotKey.title) 已被其他应用占用"
        hotKeyFailureItem?.isHidden = false
    }

    private func configureMainMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: "QuickVault")
        appMenu.addItem(
            withTitle: "设置…",
            action: #selector(openSettings),
            keyEquivalent: ","
        ).target = self
        appMenu.addItem(.separator())
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

    private func configureAppearance() {
        NSApp.appearance = settings.appearanceMode.appearance
        settings.$appearanceMode
            .removeDuplicates()
            .sink { mode in
                NSApp.appearance = mode.appearance
            }
            .store(in: &cancellables)
    }

}
