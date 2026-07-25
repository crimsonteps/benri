import ApplicationServices
import Darwin
import Foundation
import BenriCore
import UniformTypeIdentifiers

extension UTType {
    static let benriBackup = UTType(
        exportedAs: "com.crimsonteps.benri.backup",
        conformingTo: .package
    )
}

enum BenriDiagnosticsReport {
    static func make(
        vaultFileURL: URL,
        keyFileURL: URL,
        payload: VaultPayload,
        fatalErrorMessage: String?
    ) -> String {
        let bundle = Bundle.main
        let shortVersion = bundle.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "unknown"
        let buildVersion = bundle.object(
            forInfoDictionaryKey: "CFBundleVersion"
        ) as? String ?? "unknown"
        let fileManager = FileManager.default

        return [
            "Benri diagnostics",
            "Generated: \(ISO8601DateFormatter().string(from: Date()))",
            "Version: \(shortVersion) (\(buildVersion))",
            "Bundle identifier: \(bundle.bundleIdentifier ?? "unknown")",
            "macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)",
            "Architecture: \(architecture)",
            "App location: \(sanitizedPath(bundle.bundleURL))",
            "Accessibility trusted: \(AXIsProcessTrusted() ? "yes" : "no")",
            "Fatal vault error: \(fatalErrorMessage ?? "none")",
            "Categories loaded: \(payload.categories.count)",
            "Records loaded: \(payload.records.count)",
            fileDescription(label: "Vault", url: vaultFileURL, fileManager: fileManager),
            fileDescription(label: "Key", url: keyFileURL, fileManager: fileManager),
            "",
            "This report intentionally excludes record names and content."
        ].joined(separator: "\n")
    }

    private static var architecture: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        return withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(cString: $0)
            }
        }
    }

    private static func fileDescription(
        label: String,
        url: URL,
        fileManager: FileManager
    ) -> String {
        guard fileManager.fileExists(atPath: url.path) else {
            return "\(label): missing at \(sanitizedPath(url))"
        }

        do {
            let attributes = try fileManager.attributesOfItem(atPath: url.path)
            let size = (attributes[.size] as? NSNumber)?.int64Value ?? -1
            let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue
            let permissionDescription = permissions.map {
                String(format: "%03o", $0)
            } ?? "unknown"
            return "\(label): present, size=\(size) bytes, permissions=\(permissionDescription), path=\(sanitizedPath(url))"
        } catch {
            return "\(label): present, metadata unavailable, path=\(sanitizedPath(url))"
        }
    }

    private static func sanitizedPath(_ url: URL) -> String {
        let homePath = FileManager.default.homeDirectoryForCurrentUser.path
        guard url.path.hasPrefix(homePath) else { return url.path }
        return "~" + url.path.dropFirst(homePath.count)
    }
}
