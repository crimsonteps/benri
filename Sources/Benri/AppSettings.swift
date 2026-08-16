import AppKit
import BenriCore
import SwiftUI

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "跟随系统"
        case .light: "浅色"
        case .dark: "深色"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    var appearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

@MainActor
final class AppSettings: ObservableObject {
    private static let appearanceDefaultsKey = "appearanceMode"
    private static let hotKeyDefaultsKey = "globalHotKey"
    private static let menuBarIconDefaultsKey = "showsMenuBarIcon"
    private static let clipboardEnabledDefaultsKey = "clipboardHistoryEnabled"
    private static let clipboardConsentDefaultsKey = "clipboardHistoryConsent"
    private static let clipboardHotKeyDefaultsKey = "clipboardHotKey"
    private static let clipboardRetentionDefaultsKey = "clipboardRetentionDays"
    private static let clipboardExcludedAppsDefaultsKey = "clipboardExcludedApps"

    @Published var appearanceMode: AppearanceMode {
        didSet {
            UserDefaults.standard.set(
                appearanceMode.rawValue,
                forKey: Self.appearanceDefaultsKey
            )
        }
    }
    @Published var globalHotKey: GlobalHotKey {
        didSet {
            UserDefaults.standard.set(
                globalHotKey.rawValue,
                forKey: Self.hotKeyDefaultsKey
            )
        }
    }
    @Published var hotKeyError: String?
    @Published var showsMenuBarIcon: Bool {
        didSet {
            UserDefaults.standard.set(
                showsMenuBarIcon,
                forKey: Self.menuBarIconDefaultsKey
            )
        }
    }
    @Published var clipboardHistoryEnabled: Bool {
        didSet {
            UserDefaults.standard.set(
                clipboardHistoryEnabled,
                forKey: Self.clipboardEnabledDefaultsKey
            )
        }
    }
    @Published var hasConfirmedClipboardHistory: Bool {
        didSet {
            UserDefaults.standard.set(
                hasConfirmedClipboardHistory,
                forKey: Self.clipboardConsentDefaultsKey
            )
        }
    }
    @Published var clipboardHotKey: GlobalHotKey? {
        didSet {
            if let clipboardHotKey {
                UserDefaults.standard.set(
                    clipboardHotKey.rawValue,
                    forKey: Self.clipboardHotKeyDefaultsKey
                )
            } else {
                UserDefaults.standard.removeObject(forKey: Self.clipboardHotKeyDefaultsKey)
            }
        }
    }
    @Published var clipboardRetention: ClipboardRetention {
        didSet {
            UserDefaults.standard.set(
                clipboardRetention.rawValue,
                forKey: Self.clipboardRetentionDefaultsKey
            )
        }
    }
    @Published var clipboardExcludedApps: [String] {
        didSet {
            UserDefaults.standard.set(
                clipboardExcludedApps,
                forKey: Self.clipboardExcludedAppsDefaultsKey
            )
        }
    }
    @Published var clipboardHotKeyError: String?

    init() {
        appearanceMode = UserDefaults.standard
            .string(forKey: Self.appearanceDefaultsKey)
            .flatMap(AppearanceMode.init(rawValue:))
            ?? .system
        globalHotKey = UserDefaults.standard
            .string(forKey: Self.hotKeyDefaultsKey)
            .flatMap(GlobalHotKey.init(rawValue:))
            ?? .optionSpace
        showsMenuBarIcon = UserDefaults.standard.object(forKey: Self.menuBarIconDefaultsKey) == nil
            ? true
            : UserDefaults.standard.bool(forKey: Self.menuBarIconDefaultsKey)
        clipboardHistoryEnabled = UserDefaults.standard.bool(
            forKey: Self.clipboardEnabledDefaultsKey
        )
        hasConfirmedClipboardHistory = UserDefaults.standard.bool(
            forKey: Self.clipboardConsentDefaultsKey
        )
        clipboardHotKey = UserDefaults.standard
            .string(forKey: Self.clipboardHotKeyDefaultsKey)
            .flatMap(GlobalHotKey.init(rawValue:))
        clipboardRetention = ClipboardRetention(
            rawValue: UserDefaults.standard.integer(
                forKey: Self.clipboardRetentionDefaultsKey
            )
        ) ?? .threeMonths
        clipboardExcludedApps = UserDefaults.standard.stringArray(
            forKey: Self.clipboardExcludedAppsDefaultsKey
        ) ?? []
    }
}
