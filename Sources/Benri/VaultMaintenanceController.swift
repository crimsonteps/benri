import AppKit
import Foundation
import BenriCore
import UniformTypeIdentifiers

@MainActor
final class VaultMaintenanceController {
    private let store: VaultViewModel

    init(store: VaultViewModel) {
        self.store = store
    }

    func backupVault() {
        let panel = NSSavePanel()
        panel.title = "备份 Benri"
        panel.prompt = "备份"
        panel.allowedContentTypes = [.benriBackup]
        panel.allowsOtherFileTypes = false
        panel.isExtensionHidden = false
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "Benri Backup \(fileTimestamp).\(VaultBackupArchive.fileExtension)"

        guard panel.runModal() == .OK, let destinationURL = panel.url else { return }

        do {
            let manifest = try store.createBackup(
                at: destinationURL,
                appVersion: applicationVersion
            )
            showAlert(
                title: "备份完成",
                message: "已备份 \(manifest.recordCount) 条记录。备份中包含解密密钥，请像保护原始数据一样妥善保管。"
            )
        } catch {
            showError(title: "无法备份", error: error)
        }
    }

    func restoreVault() {
        let panel = NSOpenPanel()
        panel.title = "恢复 Benri 备份"
        panel.prompt = "选择备份"
        panel.allowedContentTypes = [.benriBackup]
        panel.allowsOtherFileTypes = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = false

        guard panel.runModal() == .OK, let backupURL = panel.url else { return }

        do {
            let backup = try store.validateBackup(at: backupURL)
            let confirmation = NSAlert()
            confirmation.alertStyle = .warning
            confirmation.messageText = "恢复这个备份？"
            if store.canCreateRecoveryBackup {
                confirmation.informativeText = "备份包含 \(backup.manifest.recordCount) 条记录，将替换当前保险库。Benri 会先在数据目录中保存一份恢复前备份。"
            } else {
                confirmation.informativeText = "备份包含 \(backup.manifest.recordCount) 条记录，将替换当前保险库。当前保险库无法生成恢复前备份。"
            }
            let restoreButton = confirmation.addButton(withTitle: "恢复")
            restoreButton.hasDestructiveAction = true
            confirmation.addButton(withTitle: "取消")

            guard confirmation.runModal() == .alertFirstButtonReturn else { return }

            let result = try store.restoreBackup(
                backup,
                appVersion: applicationVersion
            )
            let recoveryMessage = result.recoveryBackupURL.map {
                "\n恢复前的数据已保存在：\(sanitizedPath($0))"
            } ?? ""
            showAlert(
                title: "恢复完成",
                message: "已恢复 \(result.backup.manifest.recordCount) 条记录。\(recoveryMessage)"
            )
        } catch {
            showError(title: "无法恢复", error: error)
        }
    }

    func exportDiagnostics() {
        let panel = NSSavePanel()
        panel.title = "导出 Benri 诊断信息"
        panel.prompt = "导出"
        panel.allowedContentTypes = [.plainText]
        panel.allowsOtherFileTypes = false
        panel.isExtensionHidden = false
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "Benri Diagnostics \(fileTimestamp).txt"

        guard panel.runModal() == .OK, let destinationURL = panel.url else { return }

        let report = BenriDiagnosticsReport.make(
            vaultFileURL: store.vaultFileURL,
            keyFileURL: store.keyFileURL,
            payload: store.payload,
            fatalErrorMessage: store.fatalErrorMessage
        )

        do {
            try Data(report.utf8).write(to: destinationURL, options: [.atomic])
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: destinationURL.path
            )
            showAlert(
                title: "诊断信息已导出",
                message: "报告不包含记录名称或正文，可在提交问题前自行检查。"
            )
        } catch {
            showError(title: "无法导出诊断信息", error: error)
        }
    }

    private var applicationVersion: String {
        let shortVersion = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "unknown"
        let buildVersion = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleVersion"
        ) as? String ?? "unknown"
        return "\(shortVersion) (\(buildVersion))"
    }

    private var fileTimestamp: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return formatter.string(from: Date())
    }

    private func sanitizedPath(_ url: URL) -> String {
        let homePath = FileManager.default.homeDirectoryForCurrentUser.path
        guard url.path.hasPrefix(homePath) else { return url.path }
        return "~" + url.path.dropFirst(homePath.count)
    }

    private func showError(title: String, error: Error) {
        showAlert(
            title: title,
            message: error.localizedDescription,
            style: .critical
        )
    }

    private func showAlert(
        title: String,
        message: String,
        style: NSAlert.Style = .informational
    ) {
        let alert = NSAlert()
        alert.alertStyle = style
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "知道了")
        alert.runModal()
    }
}
