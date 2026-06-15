# iOS 15 Compatibility TODO

本仓库的阶段目标是将 EasyTier 移植并兼容到 iOS 15。当前机器不是 macOS，无法直接用 Xcode 验证编译结果；以下方案先基于静态代码审计制定，后续需要在 macOS/Xcode 环境中逐项验证。

## Phase 1: 编译目标和基础兼容层

- [ ] 将所有 iOS target 的 `IPHONEOS_DEPLOYMENT_TARGET` 从 `16.0` 调整为 `15.0`。
- [ ] 在 Rust 构建脚本中显式传递 iOS 15 部署目标，避免 Swift/Xcode target 与 Rust 静态库产物版本不一致。
- [ ] 新增 SwiftUI 兼容 helper，用于集中处理 iOS 15 与 iOS 16+ API 差异。
- [ ] 将 `.topBarLeading` / `.topBarTrailing` 替换为 iOS 15 可用的 `.navigationBarLeading` / `.navigationBarTrailing`，或封装为版本兼容常量。
- [ ] 为 `.scrollDismissesKeyboard(.immediately)` 增加兼容封装，iOS 15 下 no-op。

## Phase 2: SwiftUI 导航降级

- [ ] 将主 App 中的 `NavigationStack` 替换或封装为 iOS 15 可用的 `NavigationView`。
- [ ] 将 macOS 侧 `NavigationSplitView` 保持在 macOS 分支内，避免 iOS 15 编译路径引用 iOS 16+ API。
- [ ] 将 `NavigationLink(value:)` / `.navigationDestination` 改为 `NavigationLink(destination:)` 或 sheet fallback。
- [ ] 调整 `AdaptiveNavigation`，让紧凑宽度设备在 iOS 15 下继续使用 sheet 或传统 push 导航。

## Phase 3: 表单和通用组件兼容

- [ ] 用自定义 `CompatLabeledContent` 替换 `LabeledContent`，覆盖 `NetworkEditView`、`SettingsView`、`StatusSheet` 等文件。
- [ ] 检查 `Form` / `List` 中的 label/value 排版，确保 iOS 15 下仍然可读。
- [ ] 保留 `FocusState`、`fileImporter`、`swipeActions` 等 iOS 15 可用能力，除非 Xcode 编译发现额外限制。

## Phase 4: Widget 和 AppIntents 降级

- [ ] 将 App Shortcuts 保持为 iOS 18+ 专属能力，避免 iOS 15 编译路径直接依赖不可用类型。
- [ ] 将 Control Widget 保持为 iOS 18+ 专属能力。
- [ ] iOS 15 Widget 先降级为状态展示，不提供交互按钮。
- [ ] 将 Widget 中的 `Button(intent:)`、`containerBackground(for: .widget)` 等新 API 放入版本兼容分支或移除 iOS 15 编译路径。
- [ ] 确认 `WidgetBundle` 在 iOS 15 下只暴露传统状态 Widget。

## Phase 5: 运行时设置和功能降级

- [ ] 对 `excludeCellularServices`、`excludeAPNs`、`excludeDeviceCommunication` 等高版本 Network Extension 设置做 UI 可用性处理。
- [ ] iOS 15 下隐藏或禁用只在 iOS 16.4 / iOS 17.4 之后才生效的高级 VPN 开关。
- [ ] 保持 `includeAllNetworks`、`excludeLocalNetworks`、`enforceRoutes` 的现有行为，并在真机上验证是否符合 iOS 15 预期。

## Phase 6: Preview 和调试辅助

- [ ] 将 `#Preview` 统一改为旧式 `PreviewProvider`，或用 iOS 17+ availability 完整隔离。
- [ ] 检查 Debug-only 代码是否仍会参与 iOS 15 编译。
- [ ] 确认 OSLog 导出逻辑在 Network Extension 中的可用性；如 iOS 15 受限，则提供 fallback 错误提示。

## Phase 7: macOS/Xcode 验证

- [ ] 在 macOS 上安装目标 Xcode 版本并打开工程。
- [ ] 分别编译 App、Network Extension、Widget Extension。
- [ ] 在 iOS 15 真机或可用模拟器上验证：
  - [ ] App 启动和配置编辑。
  - [ ] VPN 配置保存和连接流程。
  - [ ] Packet Tunnel 启动、日志、状态刷新。
  - [ ] Widget 状态展示。
  - [ ] iCloud 配置读写和冲突处理。
- [ ] 根据 Xcode 编译错误补充第二轮兼容清单。
