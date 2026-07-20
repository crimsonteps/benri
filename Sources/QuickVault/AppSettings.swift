import AppKit
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
    private static let autoCopyDefaultsKey = "autoCopyOnSelection"
    private static let hidePreviewsDefaultsKey = "hideRecordPreviews"

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
    @Published var autoCopyOnSelection: Bool {
        didSet {
            UserDefaults.standard.set(
                autoCopyOnSelection,
                forKey: Self.autoCopyDefaultsKey
            )
        }
    }
    @Published var hideRecordPreviews: Bool {
        didSet {
            UserDefaults.standard.set(
                hideRecordPreviews,
                forKey: Self.hidePreviewsDefaultsKey
            )
        }
    }

    init() {
        let defaults = UserDefaults.standard
        appearanceMode = UserDefaults.standard
            .string(forKey: Self.appearanceDefaultsKey)
            .flatMap(AppearanceMode.init(rawValue:))
            ?? .system
        globalHotKey = UserDefaults.standard
            .string(forKey: Self.hotKeyDefaultsKey)
            .flatMap(GlobalHotKey.init(rawValue:))
            ?? .optionSpace
        autoCopyOnSelection = defaults.object(forKey: Self.autoCopyDefaultsKey) as? Bool ?? true
        hideRecordPreviews = defaults.object(forKey: Self.hidePreviewsDefaultsKey) as? Bool ?? true
    }
}
