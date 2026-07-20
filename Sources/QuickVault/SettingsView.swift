import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 5) {
                Label("外观", systemImage: "circle.lefthalf.filled")
                    .font(.system(size: 18, weight: .semibold))
                Text("选择 QuickVault 的显示方式")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Form {
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
            .formStyle(.grouped)
        }
        .padding(24)
        .frame(width: 430, height: 230)
        .preferredColorScheme(settings.appearanceMode.colorScheme)
    }
}
