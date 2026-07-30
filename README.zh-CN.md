<p align="center">
  <img src="Resources/benri-icon-readme.png" width="128" height="128" alt="Benri 应用图标">
</p>

<h1 align="center">Benri</h1>

<p align="center">
  一个快速、完全本地的 macOS 常用资料面板。<br>
  找到资料、复制，并直接粘贴回正在使用的应用，不打断当前工作。
</p>

<p align="center">
  <a href="README.md">English</a>
  ·
  <a href="https://github.com/crimsonteps/benri/releases/latest">下载</a>
  ·
  <a href="https://github.com/crimsonteps/benri/issues">反馈问题</a>
</p>

<p align="center">
  <a href="https://github.com/crimsonteps/benri/actions/workflows/ci.yml"><img alt="CI" src="https://github.com/crimsonteps/benri/actions/workflows/ci.yml/badge.svg"></a>
  <img alt="macOS 13+" src="https://img.shields.io/badge/macOS-13%2B-black?logo=apple">
  <img alt="Swift 6" src="https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white">
  <a href="LICENSE"><img alt="MIT License" src="https://img.shields.io/badge/License-MIT-blue.svg"></a>
</p>

<p align="center">
  <img src="Resources/benri-panel-readme.png" width="820" alt="Benri 主面板">
</p>

> [!NOTE]
> 当前 `main` 分支面向即将发布的 v1.1.0。GitHub 最新公开下载仍是 v1.0.0，备份恢复和诊断导出等新功能会随 v1.1.0 提供。

## 主要功能

- 使用全局快捷键随时唤起 Benri
- 通过分类和名称搜索快速找到常用文本
- 使用键盘完成浏览、选择和只读预览
- 按下 `Return`，将所选内容复制并粘贴回之前使用的应用
- 支持多行文本编辑、自动保存和自定义分类
- 数据在本机加密保存，并支持备份与恢复

## 系统体验

- 常驻菜单栏，不显示 Dock 图标
- 自动适配浅色、深色、降低透明度和 macOS 26 Liquid Glass
- 没有辅助功能权限时自动退回“仅复制”

## 系统要求

- macOS 13 Ventura 或更高版本
- 只有“自动粘贴回其他应用”需要辅助功能权限

## 安装

1. 从 [Releases](https://github.com/crimsonteps/benri/releases/latest) 下载最新的 `Benri-vX.Y.Z-macOS-universal.zip`。
2. 解压后将 `Benri.app` 移到 `/Applications`。
3. 打开 Benri；如果需要自动粘贴，可按系统提示授予辅助功能权限。

GitHub 会在 Release 安装包旁直接显示 SHA-256，无需下载单独的校验文件。

当前 v1.0.0 使用 ad-hoc 签名且未经过 Apple 公证，首次打开时可能需要按住 Control 点击应用并选择“打开”。从 v1.1.0 开始，Release 自动化只有在 Developer ID 签名、公证和 Gatekeeper 检查全部通过后才会发布安装包。

## 快捷键

| 快捷键 | 操作 |
| --- | --- |
| 可配置的全局快捷键 | 显示或隐藏 Benri |
| `↑` / `↓` | 在分类或记录中移动 |
| `→` | 进入记录列表，或打开所选记录的只读预览 |
| `←` | 关闭预览，或返回分类 |
| `Return` | 复制所选记录，并粘贴回之前的应用 |
| `⌘F` | 聚焦记录搜索框 |
| `⌘N` | 新建记录 |
| `⌘⇧N` | 新建分类 |
| `⌃Return` | 打开所选分类或记录的操作菜单 |
| `⌘E` | 编辑所选分类或记录 |
| `⌘⌫` | 删除所选分类或记录 |
| `⌘S` 或 `⌘Return` | 保存记录或分类的编辑内容 |
| `⌘,` | 打开设置 |
| `Esc` | 关闭编辑器或隐藏面板 |

如果自动粘贴没有权限或执行失败，内容仍会保留在系统剪贴板中，可以手动粘贴。

## 隐私与数据

Benri 使用独立的应用支持目录保存数据：

```text
~/Library/Application Support/Benri/vault.qv
~/Library/Application Support/Benri/vault.key
```

- 保险库整体使用 AES-256-GCM 加密，并限制为当前 macOS 用户访问。
- Benri 不会上传记录、密钥或使用数据，也不会在后台发起网络请求。
- 无法解密或识别保险库时，Benri 不会静默覆盖原文件。
- 恢复前会校验备份，并在替换正常保险库前保存恢复副本。

密钥和密文保存在同一个 macOS 用户账户下，因此 Benri 无法防御已经控制当前登录账户的软件或人员。`.benribackup` 文件包含恢复所需的匹配密钥，也需要像原始数据一样妥善保管。Benri 是效率工具，不是专业密码管理器的替代品。完整安全边界见 [SECURITY.md](SECURITY.md)。

可以通过“文件 → 备份保险库… / 恢复保险库… / 导出诊断信息…”进行数据维护。诊断报告只包含版本、系统、权限和文件元数据，不包含任何记录名称或正文。

安全问题请使用 [GitHub 私密安全报告](https://github.com/crimsonteps/benri/security/advisories/new)，不要提交公开 Issue。

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
make release     # 生成 Universal 2 Release 压缩包
make clean
```

## 项目结构

```text
Sources/Benri/       AppKit 与 SwiftUI 应用代码
Sources/BenriCore/   模型、加密、密钥和文件存储
Sources/BenriChecks/ 自动化检查
Resources/           Info.plist、图标与 README 图片
Scripts/             应用与 Release 打包脚本
```

## 当前范围

Benri 专注于单机、快速、私密的常用文本工作流。云同步、浏览器自动填充和跨平台客户端暂不在当前范围内。

## 参与贡献

欢迎提交问题和范围清晰的 Pull Request。开始前请阅读 [CONTRIBUTING.md](CONTRIBUTING.md)。维护者发布新版本时可参考 [RELEASING.md](RELEASING.md)。

## 许可证

Benri 使用 [MIT License](LICENSE) 开源。
