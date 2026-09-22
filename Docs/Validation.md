# 交付验证记录

验证环境：Linux；没有 Xcode、Apple iOS SDK、签名证书、iPhone 或用户 API Key。

## 已完成

- 核对上游源码提交 `1b635448bb489f49fbd6826661c3c17c01213bed` 的 Jev 请求、回复接口、七题资源和许可证。
- 以 Tree-sitter Swift grammar 解析全部 Swift 文件。
- 解析 Xcode OpenStep 工程，检查全部对象引用、源文件 membership、扩展嵌入、Scheme、资源与 App Group/Keychain entitlement 一致性。
- 解析全部 plist、JSON、privacy manifest 和 Scheme XML。
- 打包前检查 ZIP 文件可完整读取。

具体命令输出见同目录 `StaticCheck.txt`。

## 尚未执行，不能视为已通过

- Swift 编译器的 iOS SDK 类型检查与链接。
- Xcode XCTest（工程已提供八个单元测试）。
- Apple 签名、安装、扩展注册。
- 用户真实 Jev / 生成模型 API 请求。
- ReplayKit、画中画跨应用持续刷新、键盘真实输入、耗电和扩展内存压力测试。
- App Store 审核或 TestFlight 分发。

交付性质是**完整首版工程，待 Mac 编译和真机联调**。`Docs/DeviceChecks.md` 是剩余验证的具体步骤，不是执行过的测试报告。
