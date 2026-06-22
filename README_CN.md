# EasyTier for iOS 15+ Jailbreak

[简体中文](README_CN.md) | [English](README.md)

面向 iOS 15+ rootless 越狱环境的 EasyTier 客户端。

### 概览

本仓库提供面向越狱设备的 iOS 客户端包，将越狱桌面 App 和 `easytierd` 运行时守护进程以 rootless `.deb` 形式打包。

### 构建

完整打包入口是 `Packaging/deb/scripts/build_full_deb.sh`。

已知要求：Xcode 14 或更新版本。根据构建脚本，还需要 macOS 构建环境、Xcode Command Line Tools、带 `aarch64-apple-ios` target 的 Rust、`protoc`、`dpkg-deb` 和 `ldid`。

准备 Rust iOS target 和 `protoc`：

```sh
ci_scripts/ci_post_clone.sh
```

构建 App、daemon 并生成 rootless deb：

```sh
VERSION=0.1.19 Packaging/deb/scripts/build_full_deb.sh
```

`CONFIGURATION` 默认是 `Debug`，`VERSION` 默认使用 deb 脚本中的包版本。输出文件位于：

```text
Packaging/deb/dist/com.zeroninex.easytier_${VERSION}_iphoneos-arm64.deb
```

如果已有 iOS arm64 构建产物，也可以只打包：

```sh
APP_PATH=/path/to/EasyTier.app DAEMON_BIN=/path/to/easytierd VERSION=0.1.19 Packaging/deb/scripts/build_deb.sh
```

### 安装

请在 rootless 越狱环境中安装生成的 `.deb`。桌面入口作为越狱 App 安装在 `/var/jb/Applications/EasyTier.app`；运行数据保存在 `/var/jb/var/lib/easytier`。

### 状态

这不是 EasyTier 官方发布版本。

### 许可证

GNU General Public License v3.0 or later - 详见 [LICENSE](LICENSE)
