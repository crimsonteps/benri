import Foundation

public enum LegacyPreferencesMigrator {
    public static let markerKey = "legacyQuickVaultPreferencesMigration.v1"

    private static let supportedAppearanceModes: Set<String> = [
        "system",
        "light",
        "dark"
    ]
    private static let supportedHotKeys: Set<String> = [
        "optionSpace",
        "controlSpace",
        "commandOptionSpace",
        "controlOptionSpace"
    ]

    @discardableResult
    public static func migrateIfNeeded(
        legacyDomainName: String,
        destinationDefaults: UserDefaults = .standard
    ) -> Bool {
        guard !destinationDefaults.bool(forKey: markerKey) else { return false }

        let legacyValues = destinationDefaults.persistentDomain(forName: legacyDomainName) ?? [:]
        var changed = false

        if destinationDefaults.object(forKey: "appearanceMode") == nil,
           let appearanceMode = legacyValues["appearanceMode"] as? String,
           supportedAppearanceModes.contains(appearanceMode) {
            destinationDefaults.set(appearanceMode, forKey: "appearanceMode")
            changed = true
        }

        if destinationDefaults.object(forKey: "globalHotKey") == nil,
           let hotKey = legacyValues["globalHotKey"] as? String,
           supportedHotKeys.contains(hotKey) {
            destinationDefaults.set(hotKey, forKey: "globalHotKey")
            changed = true
        }

        if destinationDefaults.object(forKey: "showsMenuBarIcon") == nil,
           let showsMenuBarIcon = legacyValues["showsMenuBarIcon"] as? Bool {
            destinationDefaults.set(showsMenuBarIcon, forKey: "showsMenuBarIcon")
            changed = true
        }

        destinationDefaults.set(true, forKey: markerKey)
        return changed
    }
}
