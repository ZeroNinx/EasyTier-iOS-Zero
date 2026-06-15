# Compatibility TODO

本文件只保留仍需后续处理的兼容事项。已经在 Xcode 14.2 适配中完成的工程格式降级、Swift 5.7 语法修正、SwiftPM `Package.resolved` 降级、传统 AppIcon 补齐、Rust simulator target 映射修正等，不再作为 TODO 保留。

## iOS 15 兼容

- [ ] 明确是否仍以 iOS 15 为目标。如果是，将所有 iOS target 的 `IPHONEOS_DEPLOYMENT_TARGET` 从 `16.0` 调整为 `15.0`，并同步 Rust 构建脚本的部署目标。
- [ ] 将主 App 中的 `NavigationStack` 兼容到 iOS 15 可用的导航实现，避免 iOS 15 编译路径引用 iOS 16+ API。
- [ ] 将 sheet 内部的 `NavigationStack` 兼容到 iOS 15 可用实现，包括 `StatusSheet`、`NetworkEditView`、`LogView` 等。
- [ ] 用自定义兼容组件替换或封装 iOS 16+ 的 `LabeledContent`，覆盖 `NetworkEditView`、`SettingsView`、`StatusSheet` 等表单页面。
- [ ] 为 `.scrollDismissesKeyboard(.immediately)` 增加兼容封装，iOS 15 下 no-op。
- [ ] 检查所有 `.onChange(of:)` 调用，确保只使用 iOS 15 可用的一参数旧签名。
- [ ] 检查 Debug-only 代码是否仍会参与 iOS 15 编译，尤其是预览、mock 数据和高版本系统 API。
- [ ] 在 iOS 15 真机或可用模拟器上验证 App 启动、配置编辑、VPN 保存/连接、Packet Tunnel、日志、状态刷新、iCloud 配置读写和冲突处理。

## 本次 Xcode 14.2 兼容引入的行为变化

- [ ] 恢复主 App 对 `EasyTierWidgetExtension.appex` 的依赖和嵌入。当前 Xcode 14.2 构建的 `EasyTier.app` 不包含 Widget。
- [ ] 为 Widget Extension 制定旧 Xcode 策略：要么拆分/条件编译 Xcode 15+ 的 `AppIntents`、`ControlWidget`、`Button(intent:)` 等代码，要么明确 Widget 只支持新 Xcode 构建。
- [ ] 恢复或替代 Control Widget 刷新逻辑。当前 `ControlCenter.shared.reloadControls(...)` 仅在 `compiler(>=5.10)` 下编译，Xcode 14.2 构建不会刷新 Control Widget。
- [ ] 处理高级 VPN 开关的 UI 可用性。当前 Xcode 14.2 构建不会写入 `excludeCellularServices`、`excludeAPNs`、`excludeDeviceCommunication`，但设置页开关仍然存在，容易造成“开了但不生效”的误解。
- [ ] 恢复紧凑布局下的 navigation destination 行为。当前 `AdaptiveNavigation` 统一降级为 `.sheet(item:)`，二级页面呈现方式与新系统上的 push/navigation destination 不一致。
- [ ] 为 `EasyTier/Assets.xcassets/AppIcon.appiconset` 准备原始 1024x1024 图源。当前传统 AppIcon 由 512x512 `.icon` 源图生成，足够本地构建，但不适合作为最终上架素材。

## 发布前验证

- [ ] 使用 Xcode 14.2 验证 App + Network Extension 的 Debug/Release 构建。
- [ ] 使用较新 Xcode 验证 Widget Extension 和 Control Widget 是否仍按预期构建与运行。
- [ ] 真机验证 Network Extension entitlement、App Group、iCloud container、自动签名团队配置。
- [ ] 对比 Xcode 14.2 构建和新 Xcode 构建的功能差异，确认 README 或 release notes 是否需要说明。
