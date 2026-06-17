# EasyTier for iOS 15+ Jailbreak

[简体中文](README_CN.md) | [English](README.md)

面向 iOS 15+ rootless 越狱环境的 EasyTier 客户端。本分支将 SwiftUI App、EasyTier core 包装层和特权 `easytierd` daemon 打包为一个 rootless `.deb`。

这不是 EasyTier 官方发布版本。

当前范围和后续工作见 [docs/ROADMAP.md](docs/ROADMAP.md)。

## 仓库结构

```text
EasyTier/                  SwiftUI App
EasyTierShared/            Swift 共享常量和辅助代码
EasyTierNetworkExtension/  保留的原 NetworkExtension target
EasyTierWidgetExtension/   iOS widget target
Core/                      Rust static library，包装 EasyTier core
Daemon/                    Rust 越狱 daemon 和 IPC 服务
Packaging/deb/             Rootless deb 元数据、entitlements、launchd plist、脚本
ci_scripts/                构建环境准备脚本
docs/                      公开 roadmap 和项目说明
```

## 构建环境

当前本机已验证环境：

- macOS 12.6.2
- Xcode 14.2，iPhoneOS SDK 16.2
- Rust/Cargo 1.96.0
- Rust target `aarch64-apple-ios`
- `protoc` 3.21.12
- `dpkg-deb` 1.21.18
- `ldid` 2.1.5

需要这些命令可用：

```text
xcodebuild xcrun rustup rustc cargo protoc dpkg-deb ldid file otool ditto
```

deb 脚本会将 `/opt/homebrew/bin:/usr/local/bin` 加到 `PATH` 前面，因为 Homebrew 安装的 `protoc`、`dpkg-deb`、`ldid` 通常位于这些目录。

安装 Rust iOS target：

```sh
rustup target add aarch64-apple-ios
```

如果缺少打包工具，可以用 Homebrew 安装：

```sh
brew install protobuf dpkg ldid
```

`ci_scripts/ci_post_clone.sh` 可以在类似 CI 的环境中准备 Rust 和 `protoc`，但它不替代 Xcode、`dpkg-deb` 或 `ldid`。

## 构建

deb 只有一个构建入口：

```sh
Packaging/deb/scripts/build_deb.sh
```

默认流程：

1. 构建 `EasyTier` Xcode scheme，目标为 `iphoneos`。
2. 用 Cargo 构建 `Daemon`。`Daemon/.cargo/config.toml` 已将 daemon target 固定为 `aarch64-apple-ios`。
3. 生成 rootless 文件系统 staging 目录。
4. 使用打包 entitlements 重新签名 App 可执行文件和 daemon。
5. 生成 rootless `.deb`。

Release 构建：

```sh
CONFIGURATION=Release VERSION=0.2.0 Packaging/deb/scripts/build_deb.sh
```

默认值：

- `CONFIGURATION=Debug`
- `VERSION` 从 `Packaging/deb/control` 读取

输出：

```text
Packaging/deb/dist/com.zeroninx.easytier_${VERSION}_iphoneos-arm64.deb
```

如果已经有 iOS arm64 构建产物，可以只打包、不重新构建：

```sh
Packaging/deb/scripts/build_deb.sh \
  --package-only \
  --app /path/to/EasyTier.app \
  --daemon /path/to/easytierd \
  --version 0.2.0
```

`EasyTier.app/EasyTier` 和 `easytierd` 都必须是 iOS arm64 二进制；脚本会拒绝 macOS 主机二进制。

## 安装

请在 rootless 越狱设备上安装生成的 `.deb`。安装前，先移除通过 Xcode 或侧载工具安装的同 bundle identifier EasyTier App，否则 SpringBoard/Dopamine 可能报告 duplicate app。

安装路径：

```text
/var/jb/Applications/EasyTier.app
/var/jb/usr/bin/easytierd
/var/jb/Library/LaunchDaemons/com.zeroninx.easytierd.plist
```

运行时数据和日志路径：

```text
/var/mobile/Library/Application Support/EasyTier/
```

## 许可证

GNU General Public License v3.0 or later。详见 [LICENSE](LICENSE)。
