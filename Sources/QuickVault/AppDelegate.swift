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
    private var statusItem: NSStatusItem?
    private var settingsWindowController: SettingsWindowController!
    private var hotKeyFailureItem: NSMenuItem?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureAppearance()
        configureMainMenu()
        panelController = PanelController(
            store: store,
            settings: settings,
            openSettings: { [weak self] in self?.openSettings() }
        )
        settingsWindowController = SettingsWindowController(
            settings: settings,
            selectHotKey: { [weak self] hotKey in self?.applyHotKey(hotKey) }
        )
        observeMenuBarIconVisibility()

        hotKeyManager = HotKeyManager { [weak self] in
            self?.panelController.toggle()
        }

        registerSavedHotKey()

        DispatchQueue.main.async { [weak self] in
            self?.panelController.show()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.flushPendingRecordSave()
    }

    func applicationDidResignActive(_ notification: Notification) {
        panelController.hide(restoringPreviousApplication: false)
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        panelController.show()
        return true
    }

    @objc private func openPanel() {
        panelController.show()
    }

    @objc private func newRecord() {
        panelController.showNewRecord()
    }

    @objc private func openSettings() {
        settingsWindowController.show()
    }

    @objc private func closeFrontWindow(_ sender: Any?) {
        let window = NSApp.keyWindow
            ?? NSApp.mainWindow
            ?? NSApp.orderedWindows.first { $0.isVisible && $0.styleMask.contains(.closable) }
        window?.performClose(sender)
    }

    @objc private func quit(_ sender: Any?) {
        store.flushPendingRecordSave()
        NSApplication.shared.terminate(self)
    }

    private func configureStatusItem() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem = item
        if let button = item.button {
            button.image = makeStatusItemImage()
            button.toolTip = "Benri"
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "打开 Benri", action: #selector(openPanel), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "新建记录", action: #selector(newRecord), keyEquivalent: "n"))

        let failureItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        failureItem.isEnabled = false
        failureItem.isHidden = true
        menu.addItem(failureItem)
        hotKeyFailureItem = failureItem

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "设置…", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(.separator())
        let quitItem = NSMenuItem(
            title: "退出 Benri",
            action: #selector(quit(_:)),
            keyEquivalent: "q"
        )
        quitItem.keyEquivalentModifierMask = [.command]
        menu.addItem(quitItem)

        for item in menu.items {
            item.target = self
        }
        item.menu = menu
        updateHotKeyToolTip(settings.globalHotKey)

        if let hotKeyError = settings.hotKeyError {
            failureItem.title = hotKeyError
            failureItem.isHidden = false
        }
    }

    private func makeStatusItemImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            let scale = rect.width / 18

            let faceRect = NSRect(
                x: 1.2 * scale,
                y: 1.2 * scale,
                width: 15.6 * scale,
                height: 15.6 * scale
            )
            NSColor.black.setFill()
            NSBezierPath(
                roundedRect: faceRect,
                xRadius: 4.2 * scale,
                yRadius: 4.2 * scale
            ).fill()

            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.saveGState()
            context.setBlendMode(.clear)

            for x in [5.0, 11.2] {
                let eyeRect = NSRect(
                    x: x * scale,
                    y: 9.1 * scale,
                    width: 1.8 * scale,
                    height: 4.2 * scale
                )
                NSBezierPath(
                    roundedRect: eyeRect,
                    xRadius: eyeRect.width / 2,
                    yRadius: eyeRect.width / 2
                ).fill()
            }

            let smile = NSBezierPath()
            smile.move(to: NSPoint(x: 5.0 * scale, y: 7.0 * scale))
            smile.curve(
                to: NSPoint(x: 13.0 * scale, y: 7.0 * scale),
                controlPoint1: NSPoint(x: 6.8 * scale, y: 5.0 * scale),
                controlPoint2: NSPoint(x: 11.2 * scale, y: 5.0 * scale)
            )
            smile.lineWidth = 1.7 * scale
            smile.lineCapStyle = .round
            NSColor.black.setStroke()
            smile.stroke()
            context.restoreGState()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Benri"
        return image
    }

    private func observeMenuBarIconVisibility() {
        settings.$showsMenuBarIcon
            .removeDuplicates()
            .sink { [weak self] isVisible in
                self?.setMenuBarIconVisible(isVisible)
            }
            .store(in: &cancellables)
    }

    private func setMenuBarIconVisible(_ isVisible: Bool) {
        if isVisible {
            configureStatusItem()
            return
        }

        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
        statusItem = nil
        hotKeyFailureItem = nil
    }

    private func registerSavedHotKey() {
        let hotKey = settings.globalHotKey
        updateHotKeyToolTip(hotKey)
        if !hotKeyManager.register(hotKey) {
            showHotKeyFailure(hotKey)
        }
    }

    private func applyHotKey(_ hotKey: GlobalHotKey) {
        guard hotKey != settings.globalHotKey else { return }

        if hotKeyManager.register(hotKey) {
            settings.globalHotKey = hotKey
            settings.hotKeyError = nil
            updateHotKeyToolTip(hotKey)
            hotKeyFailureItem?.isHidden = true
        } else {
            showHotKeyFailure(hotKey)
        }
    }

    private func updateHotKeyToolTip(_ hotKey: GlobalHotKey) {
        statusItem?.button?.toolTip = "Benri · \(hotKey.title)"
    }

    private func showHotKeyFailure(_ hotKey: GlobalHotKey) {
        let message = "\(hotKey.title) 已被其他应用占用"
        settings.hotKeyError = message
        hotKeyFailureItem?.title = message
        hotKeyFailureItem?.isHidden = false
    }

    private func configureMainMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: "Benri")
        appMenu.addItem(
            withTitle: "设置…",
            action: #selector(openSettings),
            keyEquivalent: ","
        ).target = self
        appMenu.addItem(.separator())
        let hideItem = appMenu.addItem(
            withTitle: "隐藏 Benri",
            action: #selector(NSApplication.hide(_:)),
            keyEquivalent: "h"
        )
        hideItem.target = NSApp

        let hideOthersItem = appMenu.addItem(
            withTitle: "隐藏其他应用",
            action: #selector(NSApplication.hideOtherApplications(_:)),
            keyEquivalent: "h"
        )
        hideOthersItem.keyEquivalentModifierMask = [.command, .option]
        hideOthersItem.target = NSApp

        let showAllItem = appMenu.addItem(
            withTitle: "全部显示",
            action: #selector(NSApplication.unhideAllApplications(_:)),
            keyEquivalent: ""
        )
        showAllItem.target = NSApp
        appMenu.addItem(.separator())
        let quitItem = appMenu.addItem(
            withTitle: "退出 Benri",
            action: #selector(quit(_:)),
            keyEquivalent: "q"
        )
        quitItem.target = self
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        let fileItem = NSMenuItem()
        let fileMenu = NSMenu(title: "文件")
        fileMenu.addItem(
            withTitle: "新建记录",
            action: #selector(newRecord),
            keyEquivalent: "n"
        ).target = self
        fileMenu.addItem(.separator())
        fileMenu.addItem(
            withTitle: "关闭窗口",
            action: #selector(closeFrontWindow(_:)),
            keyEquivalent: "w"
        ).target = self
        fileItem.submenu = fileMenu
        mainMenu.addItem(fileItem)

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

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "窗口")
        windowMenu.addItem(
            withTitle: "最小化",
            action: #selector(NSWindow.performMiniaturize(_:)),
            keyEquivalent: "m"
        )
        windowMenu.addItem(
            withTitle: "缩放",
            action: #selector(NSWindow.performZoom(_:)),
            keyEquivalent: ""
        )
        let fullScreenItem = windowMenu.addItem(
            withTitle: "进入全屏幕",
            action: #selector(NSWindow.toggleFullScreen(_:)),
            keyEquivalent: "f"
        )
        fullScreenItem.keyEquivalentModifierMask = [.command, .control]
        windowItem.submenu = windowMenu
        mainMenu.addItem(windowItem)
        NSApp.windowsMenu = windowMenu

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
