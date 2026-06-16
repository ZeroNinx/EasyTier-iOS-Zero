# EasyTier-iOS-Zero 越狱分支实施计划

本文件只面向个人分支。

目标设备：自己的 iOS 15 越狱设备。

目标形态：保留 SwiftUI GUI，用越狱环境下的后台特权服务替代正规 iOS 的 Network Extension 运行路径。

原 EasyTier iOS 正规 App 路线不在本分支继续推进。本分支不追求 App Store、TestFlight、非越狱设备、iCloud、Widget、Shortcuts、Network Extension 正规 entitlement 或 iOS 16+ 官方路线。

---

## 0. 当前状态

已完成：

- [x] Xcode 14.2 可打开项目。
- [x] GUI 可在 iOS 15 目标上编译。
- [x] `NavigationStack` 等 iOS 16 SwiftUI API 已加 iOS 15 兼容层。
- [x] README 已标注为个人 iOS 15+ 越狱 Fork。
- [x] Bundle ID 已切到 `com.zeroninex.easytier`，App Group entitlement 已从产物移除。
- [x] 已移除一部分旧团队、旧 App Store 能力和发布路径残留。

仍需处理：

- [x] GUI 运行入口已从 `NetworkExtensionManager` 解耦。
- [ ] App、Network Extension、Widget 相关 target 仍留在工程里。
- [x] iCloud 配置项和 ProfileStore 的 iCloud 路径已移除。
- [x] 主 App 日志页已从 App Group 路径迁回本地 Documents。
- [ ] legacy Network Extension 日志导出路径仍待移除或迁移。
- [ ] 越狱 daemon、IPC、utun、route、DNS 尚未完全实现。（daemon 已能启动/停止 EasyTier Core、附加 utun，并已真机验证 IPv4/route 应用；DNS 仍未实现）

当前原则：

- 先跑通越狱主链路，再清理 UI 和工程残留。
- 不再补正规 entitlement，不再围绕 Apple 审核能力设计。
- 能复用的数据模型、配置生成、状态展示尽量复用。

---

## 1. 目标架构

现有正规 iOS 架构：

```text
EasyTier App
  -> NETunnelProviderManager
  -> PacketTunnelProvider Extension
  -> NEPacketTunnelNetworkSettings
  -> Rust EasyTier Core
```

目标越狱架构：

```text
EasyTier App GUI
  -> JailbreakTunnelManager
  -> 本地 TCP IPC
  -> easytierd LaunchDaemon
  -> 手动创建 utun
  -> 手动设置 IP / MTU / route / DNS
  -> Rust EasyTier Core
```

边界划分：

- App 只负责配置编辑、状态展示、日志查看、发送控制命令。
- daemon 负责所有需要特权的网络操作。
- Rust Core 尽量继续通过现有 FFI 接入。
- Network Extension target 只作为迁移参考，不作为最终运行路径。

---

## 2. 第一阶段：冻结正规 iOS 能力

目的：减少旧路线继续干扰越狱实现。

### 2.1 工程与能力清理

- [x] 保留 App target 作为 GUI。
- [x] 将 `EasyTierNetworkExtension` target 标记为迁移参考，第一阶段不删除源文件。
- [x] 将 Widget / Control Widget / AppIntents 标记为废弃，先从主 App 依赖链中断开。
- [x] 确认 iPhoneOS 产物不再注入 macOS sandbox entitlements。
- [x] 确认 Debug 真机产物可以启动。

实现方案：

1. 保持 `EasyTierNetworkExtension` 源码用于参考 `PacketTunnelProvider`、`BuilderHelper`、`TunnelHelper`。
2. 不再新增 Network Extension capability。
3. Release entitlements 只保留当前个人分支需要的最小项。
4. 后续引入 daemon 后，再删除 extension target 或移入 `Legacy/`。

验收标准：

- [x] `xcodebuild -project EasyTier.xcodeproj -scheme EasyTier -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build` 通过。
- [x] 真机 Debug App 能启动 GUI。
- [x] 最终 iPhoneOS App entitlements 不包含 macOS sandbox 权限。

### 2.2 iCloud / App Group 降级

- [x] 关闭设置页里的 iCloud 同步入口。
- [x] `ProfileStore` 默认只使用本地 Documents 或越狱共享目录。
- [x] 移除 `ProfileStore` 的 iCloud metadata query 冲突监听。
- [x] 主 App 的 profile、设置和选中 profile 不再以 App Group 作为主存储方案。
- [x] App、Network Extension、Widget entitlements 不再声明 App Group。
- [x] 主 App 日志页不再访问 App Group container。
- [ ] legacy Network Extension 兼容代码仍需从 App Group 迁出。
- [x] 删除 `Info.plist` 里的旧 `iCloud.site.yinmo.easytier` 残留。

实现方案：

1. 删除 `profilesUseICloud` 设置项和相关 UI 入口。
2. `ProfileStore.profilesDirectoryURL()` 删除 `url(forUbiquityContainerIdentifier:)` 分支。
3. `ProfileSession` 不再启动 `NSMetadataQueryUbiquitousDocumentsScope`。
4. Dashboard 不再在启动、自动保存、连接前写入 Network Extension 的 App Group 配置。
5. Dashboard 启动时不再调用 `NetworkExtensionManager.load()`。
6. LogView / LogTailer 先改为读取 App sandbox Documents 下的日志文件。
7. 引入 `AppPaths`，统一管理本地路径。
8. 第一阶段使用 App sandbox Documents，daemon 引入后迁移到越狱共享目录。

目标路径：

```text
/var/mobile/Library/Application Support/EasyTier/
  profiles/
  logs/
  runtime/
  exports/
```

验收标准：

- [x] 新建、重命名、删除 profile 均走本地路径。
- [x] 设置页不再出现 iCloud 同步文案。
- [x] 旧 iCloud container key 不再出现在 `Info.plist`。

---

## 3. 第二阶段：抽象运行入口

目的：让 GUI 不再直接依赖 `NetworkExtensionManager`。

### 3.1 新连接状态模型

新增自定义状态：

```swift
enum TunnelRuntimeStatus {
    case invalid
    case stopped
    case starting
    case running
    case stopping
    case failed(String?)
    case daemonUnavailable
}
```

迁移范围：

- [x] Dashboard 连接按钮。
- [x] StatusView 状态展示。
- [x] SettingsView 的后台服务状态。
- [x] 错误提示和通知。

实现方案：

1. [x] 新建 `TunnelManagerProtocol`，由 GUI 依赖协议而非具体实现。
2. [x] 先提供 `NetworkExtensionTunnelManagerAdapter`，包装现有 `NetworkExtensionManager`，保证 GUI 不大改即可编译。
3. [x] 再新增 `JailbreakTunnelManager`，通过 IPC 调 daemon。
4. 最终删除 adapter 和 `NetworkExtensionManager` 依赖。

协议草案：

```swift
protocol TunnelManagerProtocol: ObservableObject {
    var status: TunnelRuntimeStatus { get }
    var lastError: String? { get }

    func refreshStatus() async
    func connect(profile: NetworkProfile) async throws
    func disconnect() async
    func runningInfo() async throws -> NetworkStatus?
    func networkSnapshot() async throws -> TunnelNetworkSettingsSnapshot?
}
```

验收标准：

- [x] Dashboard 不直接引用 `NEVPNStatus`。
- [x] GUI 中连接、断开、刷新均通过 `TunnelManagerProtocol`。
- [x] daemon 不在线时显示“后台服务不可用”。

### 3.2 UI 文案替换

要替换的概念：

```text
VPN -> EasyTier 连接
System VPN Configuration -> 后台服务配置
Network Extension -> 后台服务
iCloud Sync -> 本地配置
Tunnel -> 虚拟网卡 / EasyTier 连接
```

验收标准：

- [x] “VPN 状态”改为“EasyTier 状态”。
- [x] “重新安装 VPN 配置”改为“重启后台服务”或“修复网络状态”。
- [x] “扩展不可用”改为“后台服务不可用”。
- [x] iCloud 同步相关文案不再显示。

---

## 4. 第三阶段：IPC

目的：让 App 能和特权 daemon 稳定通信。

### 4.1 传输方式

首选 Unix domain socket，真机测试受限时使用本地 TCP：

```text
/var/mobile/Library/Application Support/EasyTier/runtime/easytierd.sock
```

备选本地 TCP：

```text
127.0.0.1:固定端口
```

当前采用：

```text
127.0.0.1:37657
```

第一阶段建议使用 newline-delimited JSON，降低实现复杂度。

### 4.2 命令模型

基础命令：

- [x] `ping`
- [x] `start`（已启动 Core 并附加 utun）
- [x] `stop`（已停止 Core，并清理本次添加的 route/utun；DNS 尚未实现）
- [x] `version`
- [ ] `restart`
- [x] `status`
- [x] `runningInfo`
- [ ] `networkSnapshot`
- [x] `tailLog`
- [ ] `exportLog`
- [ ] `clearLog`
- [ ] `cleanupNetwork`

消息草案：

```json
{"id":"uuid","command":"start","profileName":"default","options":{}}
{"id":"uuid","ok":true,"status":"running","data":{}}
{"id":"uuid","ok":false,"error":{"code":"invalidProfile","message":"..."}}
```

安全限制：

- [x] 不允许执行任意 shell 命令。
- [x] 不允许传入任意可执行路径。
- [ ] 所有 profile 参数必须校验。
- [ ] secret / token / password 不写入普通日志。
- [ ] IPC endpoint 权限或访问范围限制为 App/daemon 可访问范围。

验收标准：

- [x] App 能 `ping` daemon。
- [x] daemon 不在线时 App 能快速失败并显示明确错误。
- [x] IPC 基础错误码稳定，不靠解析日志判断结果。

---

## 5. 第四阶段：easytierd daemon

目的：提供越狱环境下的特权运行时。

### 5.1 daemon 职责

- [x] 创建运行目录。
- [x] 接收 IPC。
- [x] 管理 EasyTier Core 生命周期（已接入 start/stop 和 utun fd）
- [x] 创建和关闭 utun。
- [x] 设置 IP / MTU / route。（IPv4/route 已真机验证，MTU 随配置应用）
- [x] 记录当前 runtime state。
- [x] 写 daemon 日志。
- [ ] 提供 cleanup 能力。

服务名：

```text
com.zeroninx.easytierd
```

二进制名：

```text
easytierd
```

### 5.2 launchd

LaunchDaemon 要求：

- [ ] rootless 优先。
- [ ] rootful 可选。
- [ ] 不硬编码 rootful 路径。
- [ ] `KeepAlive` 可配置。
- [ ] 崩溃后可重启。
- [ ] 卸载前停止服务。

plist 草案：

```xml
<key>Label</key>
<string>com.zeroninx.easytierd</string>
<key>ProgramArguments</key>
<array>
  <string>/var/jb/usr/bin/easytierd</string>
</array>
<key>RunAtLoad</key>
<true/>
<key>KeepAlive</key>
<true/>
```

验收标准：

- [x] `launchctl load` 后 daemon 可启动。
- [x] App 可连接 daemon IPC。
- [ ] daemon 崩溃后可被重新拉起。
- [ ] 卸载脚本能停止 daemon 并清理运行时残留。

---

## 6. 第五阶段：Rust Core 接入

目的：把调用者从 `PacketTunnelProvider` 迁到 daemon。

需要复用和验证的 FFI：

- [x] `init_logger`
- [x] `run_network_instance`
- [x] `stop_network_instance`
- [x] `set_tun_fd`
- [ ] `register_stop_callback`
- [ ] `register_running_info_callback`
- [x] `get_running_info`
- [ ] `get_latest_error_msg`

实现步骤：

1. 从 `PacketTunnelProvider` 提取 Core 生命周期调用顺序。
2. 在 daemon 中实现单实例状态机：`idle -> starting -> running -> stopping -> idle/failed`。
3. daemon 创建 utun 后调用 `set_tun_fd`。
4. `running_info_callback` 写入 daemon runtime state，并可被 IPC 查询。
5. stop 时先请求 core 停止，再清理网络状态。

需要重点验证：

- [ ] 多次 start / stop 后 Rust runtime 不残留。
- [ ] 切换 profile 后旧实例完全释放。
- [ ] `set_tun_fd` 调用时机稳定。
- [ ] `macos-ne` feature 是否仍适合越狱 iOS utun fd。
- [ ] 日志 callback 能进入 daemon log。

如果现有 FFI 不稳定，新增更明确的接口：

```text
create_instance
attach_tun_fd
start_instance
stop_instance
destroy_instance
```

---

## 7. 第六阶段：utun 与网络配置

### 7.1 utun

目标：daemon 自己创建 utun，不依赖 `NEPacketTunnelFlow`。

- [x] 创建 utun fd。
- [x] 获取实际 interface name，例如 `utun3`。
- [ ] 设置 non-blocking / close-on-exec 等 fd 属性。
- [x] 将 fd 交给 Rust Core。
- [x] stop 时关闭 fd。
- [ ] daemon 重启时能处理残留状态。

验收标准：

- [x] daemon 能记录 interface name。
- [x] Rust Core 能通过该 fd 收发包。
- [x] stop 后 fd 关闭，route 清理。

### 7.2 TunnelNetworkPlan

替代 `NEPacketTunnelNetworkSettings` 的内部结构：

```swift
struct TunnelNetworkPlan {
    var interfaceName: String
    var ipv4Address: String?
    var ipv4Prefix: Int?
    var ipv6Address: String?
    var ipv6Prefix: Int?
    var mtu: Int?
    var includedRoutes: [Route]
    var excludedRoutes: [Route]
    var dnsServers: [String]
    var searchDomains: [String]
    var magicDNSStatus: FeatureStatus
    var appliedAt: Date?
}
```

第一阶段只实现：

- [x] IPv4 地址。
- [x] MTU。
- [x] EasyTier 虚拟网段 route。
- [x] 手动 route。
- [x] stop 清理本次添加的 route。

暂缓：

- [ ] IPv6。
- [ ] MagicDNS。
- [ ] Override DNS。
- [ ] 全局路由。
- [ ] 排除局域网。

### 7.3 DNS / MagicDNS

原则：不要假装已完成。

- [ ] 配置项可保留，但 UI 标记为实验或未实现。
- [ ] daemon 未实现 DNS 注入时，连接前给用户提示。
- [ ] 只有 daemon 确认应用后，GUI 才显示 DNS 已生效。

后续研究方向：

- [ ] 修改系统 resolver。
- [ ] 本地 DNS proxy。
- [ ] 只在 EasyTier 内部处理 MagicDNS。
- [ ] stop 后恢复 DNS。

---

## 8. 第七阶段：日志与修复

### 8.1 日志

目标路径：

```text
/var/mobile/Library/Application Support/EasyTier/logs/easytierd.log
```

实现项：

- [x] daemon 写主日志。
- [ ] Rust Core 日志进入 daemon 日志。
- [x] IPC 请求和结果写日志。
- [x] 网络操作写日志。
- [x] GUI 日志页从 daemon 读取最近 N 行。
- [ ] 支持导出日志。
- [ ] 支持清空日志。
- [ ] 支持日志轮转。

验收标准：

- [x] App 能显示 daemon 是否在线。
- [x] App 能显示 daemon 日志。
- [ ] 日志中不泄露 secret / token / password。

### 8.2 修复网络状态

设置页新增“修复网络状态”：

- [ ] 发送 `cleanupNetwork`。
- [ ] 停止 EasyTier Core。
- [ ] 删除本次添加的 route。
- [ ] 恢复 DNS。
- [ ] 关闭 utun fd。
- [ ] 清理 runtime state。
- [ ] 返回每一步结果。

验收标准：

- [ ] daemon 崩溃后再次启动能识别残留状态。
- [ ] 用户可手动清理 route / DNS / utun 残留。

---

## 9. 第八阶段：打包安装

目标：个人自用 deb 包，不考虑正规 IPA 分发。

当前状态：已在 `Packaging/deb/` 建立 rootless deb 打包流程，真机已验证 App 和 daemon IPC 可连通。

内容：

```text
EasyTier.app
easytierd
com.zeroninx.easytierd.plist
postinst
prerm
postrm
```

要求：

- [x] rootless 优先。
- [ ] rootful 可选。
- [x] Theos 或等价打包流程。
- [x] 安装后桌面出现 EasyTier App。
- [x] 安装后配置目录存在。
- [x] 安装后 daemon 可被 launchd 加载。
- [x] 卸载默认保留 profiles 和 logs。

脚本职责：

`postinst`：

- [x] 创建目录。
- [x] 设置权限。
- [x] 安装或重载 LaunchDaemon。
- [x] 可选启动 daemon。

`prerm`：

- [x] 停止 daemon。
- [x] 卸载 LaunchDaemon。
- [x] 清理 socket。
- [x] 保留 profile 和 logs。

`postrm`：

- [x] 默认不删除用户配置。
- [ ] 如需要，单独提供彻底清理脚本。

---

## 10. 第一阶段最小可用验收

必须完成：

- [x] App 能打开 GUI。
- [x] App 能 ping daemon。
- [x] daemon 能启动。
- [x] daemon 能接收 `start`。
- [x] daemon 能启动 Rust EasyTier Core。
- [x] daemon 能创建 utun。
- [x] daemon 能把 utun fd 交给 Rust Core。
- [x] daemon 能设置 IPv4。
- [x] daemon 能设置 MTU。
- [x] daemon 能添加 EasyTier 所需 route。
- [x] 当前设备能加入 EasyTier 网络。
- [x] 其他节点能看到当前节点版本号和主机名。
- [ ] 其他节点能 ping 通当前虚拟 IP。
- [x] App 能请求 running info。
- [x] App 能显示 daemon 日志。
- [x] App 能发送 `stop`。
- [x] stop 后 route 被清理。
- [x] stop 后 EasyTier Core 停止。
- [x] stop 后 GUI 状态正确更新。

明确暂缓：

- [ ] IPv6。
- [ ] MagicDNS。
- [ ] Override DNS。
- [ ] 全局路由。
- [ ] 排除局域网。
- [ ] Widget。
- [ ] Shortcuts。
- [ ] iCloud。
- [ ] 非越狱安装。

---

## 11. 当前项目里的直接后续任务

按建议顺序执行：

1. [x] 提交 README / TODO 文档状态。
2. [x] 删除或隐藏 iCloud 设置入口。
3. [x] 移除 `Info.plist` 旧 iCloud container。
4. [x] 新增 `TunnelRuntimeStatus` 和 `TunnelManagerProtocol`。
5. [x] 用 adapter 包装现有 `NetworkExtensionManager`，让 GUI 先依赖协议。
6. [x] 新增 `JailbreakTunnelManager` 空实现，返回 `daemonUnavailable`。
7. [x] 将 Dashboard / StatusView 文案从 VPN 迁到 EasyTier 后台服务。
8. [x] 新建 daemon 源码目录和 IPC 协议定义。
9. [x] 实现 `ping/status/tailLog` 三个只读命令。
10. [x] 实现 `start/stop` IPC 和 GUI 控制状态机骨架。
11. [x] 接入 Rust Core 生命周期和 `runningInfo` IPC。
12. [x] 真机验证 IPv4/MTU/route 应用，再进入 DNS 和 cleanup 细化。

---

## 12. 最终目标

- [x] iOS 15 越狱设备上打开 App。
- [x] 选择 EasyTier profile。
- [x] 点击连接。
- [x] daemon 创建 utun。
- [x] EasyTier Core 正常运行。
- [x] 当前设备加入 EasyTier 网络。
- [ ] 其他节点可访问当前设备虚拟 IP。
- [x] App 可查看状态。
- [x] App 可查看日志。
- [x] App 可断开连接。
- [x] 网络状态可被正确清理。
- [ ] 不依赖 App Store、iCloud、Network Extension、Widget、Shortcuts。
