import AppKit
import Combine
import BenriCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let legacyCleanupPendingKey = "legacyQuickVaultCleanupPending.v1"

    private let settings: AppSettings
    private let store: VaultViewModel
    private let startupFailureMessage: String?
    private let startupWarningMessage: String?
    private var vaultFileLock: VaultFileLock?
    private var panelController: PanelController!
    private var hotKeyManager: HotKeyManager!
    private var statusItem: NSStatusItem?
    private var settingsWindowController: SettingsWindowController!
    private var hotKeyFailureItem: NSMenuItem?
    private var cancellables = Set<AnyCancellable>()
    private lazy var vaultMaintenanceController = VaultMaintenanceController(store: store)

    override init() {
        let environment = ProcessInfo.processInfo.environment
        let allowsLegacyMigration = environment["BENRI_DATA_FILE"] == nil
            && environment["BENRI_KEYCHAIN_SERVICE"] == nil
        let defaultVaultFileURL = Self.canonicalFileURL(
            VaultStorage.defaultVaultFileURL()
        )
        let configuredVaultFileURL = environment["BENRI_DATA_FILE"]
            .map { URL(fileURLWithPath: $0) }
            ?? defaultVaultFileURL
        let vaultFileURL = Self.canonicalFileURL(configuredVaultFileURL)
        let usesDefaultVault = vaultFileURL.deletingLastPathComponent().path
            == defaultVaultFileURL.deletingLastPathComponent().path
        let keychainService = environment["BENRI_KEYCHAIN_SERVICE"]
            ?? "com.crimsonteps.benri"
        let keyStore = VaultKeyStore(
            fileURL: vaultFileURL
                .deletingLastPathComponent()
                .appendingPathComponent("vault.key"),
            legacyKeychain: KeychainKeyStore(service: keychainService)
        )
        var startupFailureMessage: String?
        var startupWarningMessage: String?
        var acquiredLock: VaultFileLock?
        let legacyVaultFileURL = VaultStorage.legacyDirectoryURL()
            .appendingPathComponent("vault.qv")
        let requiresLegacyMigration = allowsLegacyMigration
            && !FileManager.default.fileExists(atPath: vaultFileURL.path)
            && FileManager.default.fileExists(atPath: legacyVaultFileURL.path)

        if usesDefaultVault,
           let existingApplication = Self.runningBenriWithoutVaultLock() {
            existingApplication.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
            startupFailureMessage = "另一个旧版 Benri 正在使用默认数据目录。请先退出旧版，再重新打开当前版本。"
        }

        if requiresLegacyMigration,
           startupFailureMessage == nil,
           let existingApplication = Self.runningLegacyVaultApplication() {
            existingApplication.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
            startupFailureMessage = "旧版 Benri 仍在运行。请先退出旧版，再重新打开当前版本。"
        }

        if startupFailureMessage == nil {
            do {
                acquiredLock = try VaultFileLock.acquire(
                    forVaultAt: vaultFileURL,
                    lockDirectoryURL: VaultStorage.lockDirectoryURL()
                )
            } catch {
                startupFailureMessage = error.localizedDescription
            }
        }

        if startupFailureMessage == nil, allowsLegacyMigration {
            let legacyKeychain = KeychainKeyStore(
                service: VaultStorage.legacyBundleIdentifier
            )
            do {
                let outcome = try LegacyInstallationMigrator.migrateIfNeeded(
                    legacyDirectoryURL: VaultStorage.legacyDirectoryURL(),
                    destinationDirectoryURL: vaultFileURL.deletingLastPathComponent(),
                    appVersion: Self.applicationVersion,
                    legacyKeychainKey: { try legacyKeychain.loadKey() },
                    legacySourceIsInactive: {
                        Self.runningLegacyVaultApplication() == nil
                    }
                )
                LegacyPreferencesMigrator.migrateIfNeeded(
                    legacyDomainName: VaultStorage.legacyBundleIdentifier
                )
                switch outcome {
                case .migrated:
                    try? legacyKeychain.deleteKey()
                    UserDefaults.standard.removePersistentDomain(
                        forName: VaultStorage.legacyBundleIdentifier
                    )
                    UserDefaults.standard.removeObject(
                        forKey: Self.legacyCleanupPendingKey
                    )
                case .currentVaultAlreadyExists:
                    if UserDefaults.standard.bool(forKey: Self.legacyCleanupPendingKey),
                       FileManager.default.fileExists(
                        atPath: VaultStorage.legacyDirectoryURL().path
                       ) {
                        startupWarningMessage = "旧 QuickVault 数据目录仍未清理。Benri 已保留它以避免误删其他文件，请确认旧版已退出后手动检查该目录。"
                    } else {
                        UserDefaults.standard.removeObject(
                            forKey: Self.legacyCleanupPendingKey
                        )
                    }
                case .noLegacyVault:
                    UserDefaults.standard.removeObject(
                        forKey: Self.legacyCleanupPendingKey
                    )
                }
            } catch let error as LegacyInstallationMigrationError {
                if case .legacyCleanupFailed = error {
                    LegacyPreferencesMigrator.migrateIfNeeded(
                        legacyDomainName: VaultStorage.legacyBundleIdentifier
                    )
                    UserDefaults.standard.set(
                        true,
                        forKey: Self.legacyCleanupPendingKey
                    )
                    startupWarningMessage = error.localizedDescription
                } else {
                    startupFailureMessage = "迁移旧版 QuickVault 数据失败。旧数据未被改动。\n\n\(error.localizedDescription)"
                }
            } catch {
                startupFailureMessage = "迁移旧版 QuickVault 数据失败。旧数据未被改动。\n\n\(error.localizedDescription)"
            }
        }

        settings = AppSettings()
        store = VaultViewModel(
            vaultFileURL: vaultFileURL,
            keyStore: keyStore,
            startupFailureMessage: startupFailureMessage
        )
        self.startupFailureMessage = startupFailureMessage
        self.startupWarningMessage = startupWarningMessage
        vaultFileLock = acquiredLock
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if let startupFailureMessage {
            showStartupAlert(
                title: "Benri 无法启动",
                message: startupFailureMessage,
                style: .critical
            )
            NSApp.terminate(self)
            return
        }

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
            if let startupWarningMessage = self?.startupWarningMessage {
                self?.showStartupAlert(
                    title: "旧数据清理未完成",
                    message: startupWarningMessage,
                    style: .warning
                )
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.flushPendingRecordSave()
    }

    func applicationDidResignActive(_ notification: Notification) {
        guard startupFailureMessage == nil, panelController.isVisible else { return }
        panelController.hide(restoringPreviousApplication: false)
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        guard startupFailureMessage == nil else { return false }
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

    @objc private func checkForUpdates() {
        guard let url = URL(string: "https://github.com/crimsonteps/benri/releases/latest") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    @objc private func backupVault() {
        vaultMaintenanceController.backupVault()
    }

    @objc private func restoreVault() {
        vaultMaintenanceController.restoreVault()
    }

    @objc private func exportDiagnostics() {
        vaultMaintenanceController.exportDiagnostics()
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
            button.imageScaling = .scaleProportionallyDown
            button.toolTip = "Benri"
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "打开 Benri", action: #selector(openPanel), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "新建记录", action: #selector(newRecord), keyEquivalent: "n"))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "备份保险库…", action: #selector(backupVault), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "恢复保险库…", action: #selector(restoreVault), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "导出诊断信息…", action: #selector(exportDiagnostics), keyEquivalent: ""))

        let failureItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        failureItem.isEnabled = false
        failureItem.isHidden = true
        menu.addItem(failureItem)
        hotKeyFailureItem = failureItem

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "检查更新…", action: #selector(checkForUpdates), keyEquivalent: ""))
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
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.saveGState()
            defer { context.restoreGState() }

            let iconScale: CGFloat = 14.0 / 18.0
            context.translateBy(x: rect.midX, y: rect.midY)
            context.scaleBy(x: iconScale, y: iconScale)
            context.translateBy(x: -rect.midX, y: -rect.midY)

            let scale = rect.width / 18

            let faceRect = NSRect(
                x: 0.8 * scale,
                y: 0.8 * scale,
                width: 16.4 * scale,
                height: 16.4 * scale
            )
            let face = NSBezierPath(
                roundedRect: faceRect,
                xRadius: 4.0 * scale,
                yRadius: 4.0 * scale
            )
            face.lineWidth = 1.2 * scale
            NSColor.black.setStroke()
            face.stroke()

            NSColor.black.setFill()
            for x in [5.35, 11.13] {
                let eyeRect = NSRect(
                    x: x * scale,
                    y: 9.15 * scale,
                    width: 1.45 * scale,
                    height: 2.7 * scale
                )
                NSBezierPath(
                    roundedRect: eyeRect,
                    xRadius: eyeRect.width / 2,
                    yRadius: eyeRect.width / 2
                ).fill()
            }

            let smile = NSBezierPath()
            smile.move(to: NSPoint(x: 5.65 * scale, y: 7.4 * scale))
            smile.curve(
                to: NSPoint(x: 12.28 * scale, y: 7.4 * scale),
                controlPoint1: NSPoint(x: 7.1 * scale, y: 5.4 * scale),
                controlPoint2: NSPoint(x: 10.83 * scale, y: 5.4 * scale)
            )
            smile.lineWidth = 1.25 * scale
            smile.lineCapStyle = .round
            NSColor.black.setStroke()
            smile.stroke()
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
        appMenu.addItem(
            withTitle: "检查更新…",
            action: #selector(checkForUpdates),
            keyEquivalent: ""
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
            withTitle: "备份保险库…",
            action: #selector(backupVault),
            keyEquivalent: ""
        ).target = self
        fileMenu.addItem(
            withTitle: "恢复保险库…",
            action: #selector(restoreVault),
            keyEquivalent: ""
        ).target = self
        fileMenu.addItem(
            withTitle: "导出诊断信息…",
            action: #selector(exportDiagnostics),
            keyEquivalent: ""
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

    private func showStartupAlert(
        title: String,
        message: String,
        style: NSAlert.Style
    ) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = style
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "知道了")
        alert.runModal()
    }

    private static var applicationVersion: String {
        let shortVersion = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "unknown"
        let buildVersion = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleVersion"
        ) as? String ?? "unknown"
        return "\(shortVersion) (\(buildVersion))"
    }

    private static func runningLegacyVaultApplication() -> NSRunningApplication? {
        let currentProcessIdentifier = ProcessInfo.processInfo.processIdentifier
        return NSRunningApplication.runningApplications(
            withBundleIdentifier: VaultStorage.legacyBundleIdentifier
        )
            .first { $0.processIdentifier != currentProcessIdentifier }
    }

    private static func runningBenriWithoutVaultLock() -> NSRunningApplication? {
        let currentProcessIdentifier = ProcessInfo.processInfo.processIdentifier
        return NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.crimsonteps.benri"
        )
            .filter { $0.processIdentifier != currentProcessIdentifier }
            .first { application in
                guard let bundleURL = application.bundleURL else { return true }
                let installedPaths = [
                    "/Applications/Benri.app",
                    FileManager.default.homeDirectoryForCurrentUser
                        .appendingPathComponent("Applications/Benri.app")
                        .path
                ]
                if installedPaths.contains(bundleURL.standardizedFileURL.path) {
                    return true
                }

                guard
                      let bundle = Bundle(url: bundleURL),
                      let lockVersion = bundle.object(
                        forInfoDictionaryKey: "BenriVaultLockVersion"
                      ) as? NSNumber
                else { return true }
                return lockVersion.intValue < 1
            }
    }

    private static func canonicalFileURL(_ url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath()
    }

}
