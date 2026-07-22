<p align="center">
  <img src="Resources/benri-icon-readme.png" width="128" height="128" alt="Benri 应用图标">
</p>

<h1 align="center">Benri</h1>

<p align="center">
  一个快速、本地优先的 macOS 常用资料面板。<br>
  找到资料、复制，并直接粘贴回正在使用的应用，不打断当前工作。
</p>

<p align="center">
  <a href="README.md">English</a>
  ·
  <a href="https://github.com/crimsonteps/benri/releases/latest">下载</a>
  ·
  <a href="https://github.com/crimsonteps/benri/issues">反馈问题</a>
</p>

Benri 是一款轻量的 macOS 菜单栏工具，用来保存经常重复使用的文本，例如服务器命令、账号资料、地址、网址、回复模板、代码片段和备注。按下全局快捷键，通过名称搜索，再按 `Return`，即可复制所选内容并自动粘贴回刚才使用的应用。

所有数据只保存在你的 Mac 上。Benri 没有账号系统、统计分析、网络请求、云服务或第三方运行时依赖。

## 主要功能

- 全局唤起，可选 `⌥Space`、`⌃Space`、`⌥⌘Space` 或 `⌃⌥Space`
- 分类、记录和正文之间的全键盘操作
- 自由多行正文，编辑后自动保存
- 自定义分类，以及个人、工作、服务器、其他四个内置分类
- 按记录名称搜索
- 没有辅助功能权限时自动退回“仅复制”
- 支持浅色、深色、降低透明度和 macOS 26 Liquid Glass
- 本地 AES-256-GCM 加密存储
- 不显示 Dock 图标，不联网，不收集遥测，不进行云同步

## 系统要求

- macOS 13 Ventura 或更高版本
- 只有“自动粘贴回其他应用”需要辅助功能权限

## 安装

1. 从 [Releases](https://github.com/crimsonteps/benri/releases/latest) 下载最新的 `Benri-vX.Y.Z-macOS-universal.zip`。
2. 解压后将 `Benri.app` 移到 `/Applications`。
3. 打开 Benri；如果需要自动粘贴，可按系统提示授予辅助功能权限。

除非某个 Release 明确注明已公证，社区构建默认使用 ad-hoc 签名。首次打开时，macOS 可能要求你按住 Control 点击应用，选择“打开”并确认一次；也可以前往“系统设置 → 隐私与安全性”允许打开。

## 快捷键

| 快捷键 | 操作 |
| --- | --- |
| 可配置的全局快捷键 | 显示或隐藏 Benri |
| `↑` / `↓` | 在分类或记录中移动 |
| `Return` | 复制所选记录，并粘贴回之前的应用 |
| `⌘←` / `⌘→` | 在不同栏位之间切换 |
| `⌘N` | 新建记录 |
| `⌘S` 或 `⌘Return` | 在记录编辑器中保存 |
| `⌘,` | 打开设置 |
| `Esc` | 关闭编辑器或隐藏面板 |

如果自动粘贴没有权限或执行失败，内容仍会保留在系统剪贴板中，可以手动粘贴。

## 隐私与安全

Benri 为兼容早期版本，继续使用 QuickVault 数据目录：

```text
~/Library/Application Support/QuickVault/vault.qv
~/Library/Application Support/QuickVault/vault.key
```

- 保险库整体使用 AES-256-GCM 加密。
- 随机生成的 32 字节密钥和保险库文件权限均为 `0600`，目录权限为 `0700`，仅当前用户可访问。
- Benri 不会通过网络发送数据。
- 保险库无法解密时，Benri 不会静默覆盖原文件。
- 重置保险库会永久删除加密数据和本地密钥。

为了避免每次启动都要求输入密码或确认钥匙串，密钥和密文保存在同一个 macOS 用户账户下。这能降低静态文件被随手读取的风险，但**无法**防御已经取得当前登录账户权限的软件或人员。复制内容后，文本也会进入 macOS 系统剪贴板，并遵循系统正常的剪贴板行为。Benri 是效率工具，不是专业密码管理器的替代品。

安全问题请使用 [GitHub 私密安全报告](https://github.com/crimsonteps/benri/security/advisories/new)，不要提交公开 Issue。详见 [SECURITY.md](SECURITY.md)。

## 从源码构建

Benri 使用 Swift Package Manager，不依赖外部 Swift 包。安装带 Swift 6 的 Xcode 或 macOS Command Line Tools 即可。

```bash
git clone https://github.com/crimsonteps/benri.git
cd benri
make test
make app
open dist/Benri.app
```

常用命令：

```bash
make build       # Debug 构建
make test        # 运行零依赖检查
make app         # 为当前架构生成 Benri.app
make release     # 生成 Universal 2 压缩包和 SHA-256 校验文件
make clean
```

使用较旧 SDK 构建时，Benri 会自动使用系统 Material 外观；使用 macOS 26 SDK 构建时，会在 macOS 26 上启用原生 Liquid Glass，同时继续保持 macOS 13 的最低部署版本。

## 项目结构

```text
Sources/QuickVault/        AppKit 与 SwiftUI 应用代码
Sources/QuickVaultCore/    模型、加密、密钥和文件存储
Sources/QuickVaultChecks/  零依赖自动检查
Resources/                 Info.plist 与应用图标源文件
Scripts/                   应用与 Release 打包脚本
```

## 当前范围

v1 专注于可靠的本地使用流程，暂不包含云同步、浏览器自动填充、导入导出、密码生成、开机启动和跨平台支持。

## 参与贡献

欢迎提交问题和范围清晰的 Pull Request。开始前请阅读 [CONTRIBUTING.md](CONTRIBUTING.md)。维护者发布新版本时可参考 [RELEASING.md](RELEASING.md)。

## 许可证

Benri 使用 [MIT License](LICENSE) 开源。
