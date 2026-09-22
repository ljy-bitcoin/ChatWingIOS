# 架构与维护

## 三个进程

| 进程 | 职责 | 跨进程数据 |
|---|---|---|
| 主 App | 配置、联系人、截图测试、PiP 视频渲染 | settings / control / presence / result |
| Broadcast Upload Extension | 接收帧、旋转与降采样、Vision OCR、模型请求 | 读配置与会话；写 result / broadcast 心跳 |
| Keyboard Extension | 读取候选、显示联系人、插入文字、暂停 | 读 result / control；暂停时更新 control |

API Key 放共享 Keychain，仅 App 和广播扩展有 access group。键盘无 Keychain entitlement，也不编译网络客户端。候选共享需要键盘允许完全访问。

## 录屏处理

`SampleHandler` 以锁做帧准入：最多排队一张图，默认每 2 秒采样，采样以外的视频和所有音频直接丢弃。串行 worker 做图像方向校正和 OCR。图像最长边限制与宽度限制分别为 1700、960 像素，不保留整段录屏。

先识别顶部 4%–17% 的标题区域；正文采用用户配置的 ROI。原始 bounding box 转换为左上角坐标。根据左右留白估计说话方；居中/宽气泡无法可靠归属时为 unknown。发给 Jev 时维持上游 schema，但加显式“不确定发言方”前缀，避免静默当作准确消息。

标题匹配失败、无正文、系统暂停、会话过期都会取消任务并清除结果。主程序前台时不分析主程序画面。**这不是全局 App 身份识别**，不能保证任意其它页面绝不会被 OCR；默认标题精确匹配用于限制处理范围。

相同内容需要两次稳定采样；使用 SHA256 对联系人、顺序、发言方、文字作指纹。滚动/文字变化先撤销旧结果。默认每 12 秒至多启动一条分析链。错误退避 15/30/60/120 秒。网络超时分别为请求 25 秒、资源 40 秒，不自动重试账单请求。Jev 对 background 不接受的 400/422 只降级一次为不带该字段的请求。

## 结果归属

每次开启/暂停都会生成新会话 UUID；配置保存刷新 revision。发布结果前检查会话、配置、当前指纹和任务身份。键盘插入前再次读取结果，核对会话、联系人、生成时间和 180 秒有效期；实时结果还需广播心跳新鲜。键盘自身不能知道微信正在和谁聊天，因此界面持续展示联系人。

原子 JSON 文件替换保证读者不会读到半份数据。会话文件更新使用进程内锁加 `flock`；非秘密数据也使用 `completeFileProtectionUntilFirstUserAuthentication` 且排除 iCloud 备份。截图只在内存；最新识别文本和回复落入共享文件，这是 PiP/键盘读取的必要中间结果。

## 画中画

主程序每 0.5 秒读一次共享结果，绘制 960×540 BGRA 帧，转换成 `CMSampleBuffer`，交给 `AVSampleBufferDisplayLayer` 和 `AVPictureInPictureController`。不使用私有 API、伪装通话或静音音频循环。声明 `audio` 后台模式用于 PiP。

这提供了后台显示的实现路径，**不代表已验证所有系统版本都持续调度主 App 的渲染 timer**。最优先的真机验收是：切到微信至少两分钟后，广播结果与小窗是否同步刷新。如果心跳更新而小窗冻结，需要进一步定位 PiP 状态、主进程调度和 sample buffer 时间轴。

## 接口

Jev：POST `{model,state,questions}`，读取 `answers`，七题来自上游。生成：OpenAI-compatible Chat Completions，要求恰好三条不同的 JSON 字符串；不返回伪造兜底回复。Jev 排序失败会保留候选并标为未经排序。通用模式要求 JSON 判断，不冒充原生 Jev 决策结果。

HTTP 禁止自动重定向；只接受无用户名、密码、查询参数、fragment 的 HTTPS URL。密钥继承仅限同域名。错误不打印请求体、密钥或供应商原始响应。没有埋点、第三方 SDK、自动发送或后台触控。

## 文件入口

- `Shared/Models.swift`：协议与会话模型。
- `Shared/APIClient.swift`：HTTP、Jev、兼容模型与解析。
- `Shared/OCRReader.swift`、`TextLogic.swift`：Vision、标题匹配、侧别、去重。
- `Broadcast/SampleHandler.swift`：实时任务调度。
- `App/PiPController.swift`：PiP 画面渲染。
- `Keyboard/KeyboardViewController.swift`：候选插入。
- `Scripts/generate_project.py`：无需额外工具生成 Xcode 项目。

Apple 接口参考：
- <https://developer.apple.com/documentation/replaykit/rpbroadcastsamplehandler>
- <https://developer.apple.com/documentation/avkit/avpictureinpicturecontroller/contentsource>
- <https://developer.apple.com/documentation/vision/recognizing-text-in-images>
- <https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/CustomKeyboard.html>
