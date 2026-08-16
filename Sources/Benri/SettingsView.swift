import AppKit
import BenriCore
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    let selectHotKey: (GlobalHotKey) -> Void
    let selectClipboardHotKey: (GlobalHotKey?) -> Void
    let clearClipboardHistory: () -> Void
    @State private var confirmingClipboardEnable = false
    @State private var confirmingClear = false

    var body: some View {
        VStack(alignment: .leading) {
            Form {
                Section("菜单栏") {
                    Toggle("显示菜单栏图标", isOn: $settings.showsMenuBarIcon)

                    Text("隐藏后仍可通过全局快捷键唤起 Benri。")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Section("快捷键") {
                    Picker(
                        "唤起 Benri",
                        selection: Binding(
                            get: { settings.globalHotKey },
                            set: selectHotKey
                        )
                    ) {
                        ForEach(GlobalHotKey.allCases, id: \.self) { hotKey in
                            Text(hotKey.title).tag(hotKey)
                        }
                    }

                    if let hotKeyError = settings.hotKeyError {
                        Text(hotKeyError)
                            .font(.system(size: 11))
                            .foregroundStyle(.red)
                    } else {
                        Text("快捷键设置会立即生效并自动保存。")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }

                    Picker(
                        "直接打开剪贴板",
                        selection: Binding(
                            get: { settings.clipboardHotKey },
                            set: selectClipboardHotKey
                        )
                    ) {
                        Text("未绑定").tag(GlobalHotKey?.none)
                        ForEach(GlobalHotKey.allCases, id: \.self) { hotKey in
                            Text(hotKey.title).tag(Optional(hotKey))
                        }
                    }

                    if let error = settings.clipboardHotKeyError {
                        Text(error)
                            .font(.system(size: 11))
                            .foregroundStyle(.red)
                    }
                }

                Section("剪贴板历史") {
                    Toggle(
                        "启用剪贴板历史",
                        isOn: Binding(
                            get: { settings.clipboardHistoryEnabled },
                            set: { enabled in
                                if enabled, !settings.hasConfirmedClipboardHistory {
                                    confirmingClipboardEnable = true
                                } else {
                                    settings.clipboardHistoryEnabled = enabled
                                }
                            }
                        )
                    )

                    Picker("保留时间", selection: $settings.clipboardRetention) {
                        ForEach(ClipboardRetention.allCases) { retention in
                            Text(retention.title).tag(retention)
                        }
                    }

                    Text("历史以明文保存在本机缓存目录，不会进入 Benri 保险库备份。")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Section("不记录这些应用") {
                    ForEach(settings.clipboardExcludedApps, id: \.self) { bundleID in
                        HStack {
                            Text(applicationName(for: bundleID))
                            Spacer()
                            Button {
                                settings.clipboardExcludedApps.removeAll { $0 == bundleID }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Button("添加应用…", action: addExcludedApplication)
                }

                Section("清理") {
                    Button("清空剪贴板历史…", role: .destructive) {
                        confirmingClear = true
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
        }
        .padding(24)
        .frame(width: 500, height: 660)
        .background {
            Color(nsColor: .windowBackgroundColor)
                .ignoresSafeArea()
        }
        .alert("启用剪贴板历史？", isPresented: $confirmingClipboardEnable) {
            Button("取消", role: .cancel) {}
            Button("启用") {
                settings.hasConfirmedClipboardHistory = true
                settings.clipboardHistoryEnabled = true
            }
        } message: {
            Text("Benri 会在本机以明文缓存文本和图片，默认保留 90 天。")
        }
        .confirmationDialog(
            "清空剪贴板历史？",
            isPresented: $confirmingClear,
            titleVisibility: .visible
        ) {
            Button("清空历史", role: .destructive, action: clearClipboardHistory)
            Button("取消", role: .cancel) {}
        } message: {
            Text("所有缓存文本和图片都会永久删除。")
        }
    }

    private func addExcludedApplication() {
        let panel = NSOpenPanel()
        panel.title = "选择不记录剪贴板的应用"
        panel.allowedContentTypes = [.application]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        guard panel.runModal() == .OK,
              let url = panel.url,
              let bundleID = Bundle(url: url)?.bundleIdentifier,
              !settings.clipboardExcludedApps.contains(bundleID)
        else { return }
        settings.clipboardExcludedApps.append(bundleID)
    }

    private func applicationName(for bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return bundleID
        }
        return url.deletingPathExtension().lastPathComponent
    }
}
