import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    let selectHotKey: (GlobalHotKey) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 5) {
                Label("设置", systemImage: "gearshape")
                    .font(.system(size: 18, weight: .semibold))
                Text("调整 valuet 的外观和唤起方式")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Form {
                Section("外观") {
                    Picker("主题", selection: $settings.appearanceMode) {
                        ForEach(AppearanceMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text("跟随系统会自动响应 macOS 的浅色和深色外观。")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Section("菜单栏") {
                    Toggle("显示菜单栏图标", isOn: $settings.showsMenuBarIcon)

                    Text("隐藏后仍可通过全局快捷键唤起 valuet。")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Section("快捷键") {
                    Picker(
                        "唤起 valuet",
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
                }

                Section("剪贴板") {
                    Text("复制的内容会在 30 秒后清除，前提是剪贴板内容没有被替换。")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
        }
        .padding(24)
        .frame(width: 460, height: 580)
        .background {
            Color(nsColor: .windowBackgroundColor)
                .ignoresSafeArea()
        }
        .preferredColorScheme(settings.appearanceMode.colorScheme)
    }
}
