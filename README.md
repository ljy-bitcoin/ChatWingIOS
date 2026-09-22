# 聊伴 ChatWing · iPhone 聊天副驾

完整 iOS 源码工程，包含主程序、ReplayKit 屏幕广播扩展、画中画显示、候选回复键盘、联系人背景、模型接口配置和测试。基于 [Jev 聊天助手](https://github.com/jev-chat/jev-chat-jarvis) 的判断题集与接口设计二次开发；不是原作者发布的官方 iOS 版。

**交付状态：源码已实现并通过工程结构与 Swift 语法解析检查；尚未经过 Xcode 编译、签名、真机或真实模型接口测试。不是可直接安装的 IPA。** 详细记录见 `Docs/Validation.md`。

## 你能用它做什么

1. 主动启动系统屏幕广播，在本机对画面抽帧识字。
2. 识别所选联系人的聊天，结合备注和个人话术，分析可能意图、冲突风险与建议动作。
3. 生成三条候选；Jev 模式再调用判断接口排序。
4. 把建议渲染成视频，在画中画小窗显示。
5. 切到「聊伴」键盘，点候选填进当前输入框，由你自行发送。

另外提供截图导入和手动文字分析：截图只在本机 OCR，核对后才提交文字给模型。

## 准备条件

- 一台 Mac，以及支持你 iPhone 当前系统版本的 Xcode（工程采用 Xcode 16 可识别的项目格式）。
- iPhone 最低 iOS 17。屏幕广播、画中画与跨应用键盘必须用真机验证。
- 可为应用启用 **App Groups 与 Keychain Sharing** 的 Apple 开发签名配置。普通免费 Personal Team 可能无法启用本工程所需能力；完整三 Target 安装通常需要 Apple Developer Program 团队。
- 自己的模型 API Key；ChatGPT 订阅不等于 API 额度。

**无需 XcodeGen、CocoaPods 或第三方 Swift 包。** 解压后直接打开 `ChatWing.xcodeproj`。

## 安装到 iPhone

### 1. 设置唯一标识和团队

编辑 `Config/Signing.xcconfig`，例如：

```xcconfig
BUNDLE_PREFIX = com.yourname.chatwing
DEVELOPMENT_TEAM = ABCDE12345
CODE_SIGN_STYLE = Automatic
```

这里的团队 ID 是你自己的 10 位 Team ID。也可以在工程目录运行：

```bash
python3 Scripts/configure.py --bundle-id com.yourname.chatwing --team ABCDE12345
```

### 2. 在 Xcode 配好共享能力

打开工程，选中 `ChatWing` Scheme。检查三个产品 Target 的 Signing & Capabilities，使用同一个 Team：

| Target | Bundle ID | App Group | Keychain Sharing |
|---|---|---|---|
| ChatWing | `com.yourname.chatwing` | `group.com.yourname.chatwing` | `$(AppIdentifierPrefix)com.yourname.chatwing.credentials` |
| ChatWingBroadcast | 上面加 `.Broadcast` | 同上 | 同上 |
| ChatWingKeyboard | 上面加 `.Keyboard` | 同上 | 不启用 |

工程文件已声明这些 entitlement，但你的开发者账户仍需注册并授权对应 App Group。新建团队通常由 Xcode 自动管理；若报 provisioning 不匹配，在开发者后台为 App 和两个扩展启用相同 Group 后重新生成签名。Keychain 前缀以实际 `AppIdentifierPrefix` 为准，不要自行替换成猜测的 Team ID。

### 3. 编译运行

用数据线或 Xcode 已配对的网络连接 iPhone，按 Xcode 提示开启设备开发者模式。选择 iPhone 后点击 Run。若报错，将**第一条编译错误**或签名错误完整提供给开发者定位。

## 第一次使用：先验证接口

1. 「接口」选择预设并填写密钥，保存。地址要填**完整 POST URL**，本工程不自动补 `/v1` 等后缀。
2. 「联系人」把默认“新联系人”改成微信顶部实际显示的名字，填写关系与备注，保存。别名按行填写，标题匹配采用去空格后的精确匹配。
3. 「识别与测试」先粘贴几行文字，例如：

```text
我：资料已经发过去了，你看看有没有需要调整的。
对方：收到，我下午看完给你反馈。
```

4. 点「分析文字 / 测试两路接口」。这一步会真实调用模型并产生 API 费用。返回三条回复后再测实时流程。

预设来自本次核对的上游版本，不承诺服务商未来保持同名模型或接口：

| 用途 | 完整 URL | 模型示例 |
|---|---|---|
| Jev / OpenRouter | `https://openrouter.ai/api/alpha/decisions` | `typesafe/jev-1.13` |
| Jev / TypeSafe | `https://api.typesafe.ai/v1/systemone` | `jev-latest` |
| 生成 / OpenRouter | `https://openrouter.ai/api/v1/chat/completions` | `deepseek/deepseek-chat-v3.1` |
| 通用判断与生成 / DeepSeek | `https://api.deepseek.com/chat/completions` | `deepseek-chat` |

**Jev 模式的判断地址不能填普通 `/chat/completions`。** 如果没有 Jev 接口，选择通用模式；普通模型会返回结构化判断，候选不显示虚构的 Jev 排名。

## 实时流程

1. 停留竖屏，在「助手」选择联系人，点击「保存配置并开启分析」。会话有效期 10 分钟，到期回主程序重新开启。
2. 点击系统录屏图标，在弹窗中选择聊伴并「开始直播」。这里使用本地广播扩展，不会把视频推流到服务器。可保持麦克风关闭。
3. 等待预览出现，点「开启画中画」，再切换到该联系人的微信聊天。
4. 将小窗放到 OCR 区域外；默认区域是屏幕中间 18%–70%。必要时先用截图校准上下左右边界。
5. 连续两次 OCR 一致后才调用模型；相同文字不重复调用。模型调用最小间隔默认 12 秒，失败后退避。
6. 系统设置 → 通用 → 键盘 → 键盘 → 添加新键盘 → 聊伴，并允许完全访问。回微信长按地球键切换，核对联系人，再点一条候选插入。
7. 手动点击微信发送按钮。需要自由编辑时切回普通键盘。

**停止：** 键盘里可暂停分析；画中画系统暂停或关闭也会暂停分析。若要完全停止屏幕采集，还需点击 iOS 的录屏指示器停止广播。画中画的播放键不会自动重新开启分析。

## 当前版本的边界

- 当前按**竖屏、一对一聊天**设计。气泡侧别靠 OCR 几何推测，长气泡、群聊、表情、图片、引用和不同聊天 App 布局可能识别不准；不确定的文字会显式标注。
- 画中画显示的是视频，候选文字不能直接作为按钮点选；填入入口在自定义键盘。
- iOS 不提供当前聊天对象给键盘。键盘展示联系人名、检查会话和有效期，并避免向已有文字追加，但用户仍需确认输入框属于该联系人。
- 不自动滚屏、不读取聊天数据库，不保存长期历史。联系人和个人背景会随分析请求发送。
- 截屏不落盘；最新 OCR 文本及候选暂存 App Group 文件供进程共享，暂停/失配/新会话会清除，超过 3 分钟不再作为可插入结果。它们不是零持久化数据。
- 画中画后台刷新、广播扩展内存峰值、不同机型耗电尚待真机测试。不能据此认定后台稳定性或 App Store 审核已经验证。

## 自检与编译

```bash
python3 Scripts/verify.py
xcodebuild -project ChatWing.xcodeproj -scheme ChatWing \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
```

在 Xcode 中 `Product → Test` 跑单元测试。`Docs/DeviceChecks.md` 给出了实时功能的逐项验收方式。仓库内包含 GitHub Actions 工作流，可在自己的仓库用 macOS runner 编译与跑测试；交付时未代为创建仓库或执行远程工作流。

新增源文件后可以运行 `python3 Scripts/generate_project.py` 重新生成工程；它不会覆盖 `Config/Signing.xcconfig`。

## 来源

上游：<https://github.com/jev-chat/jev-chat-jarvis>

本次核对提交：`1b635448bb489f49fbd6826661c3c17c01213bed`。

`Resources/JudgeQuestions.json` 从上游 `tools/jev/questions.py` 的七题集转换，追加了上游 Android 使用的背景说明。Jev state 使用 Android 版 `me/other` 约定，保留判断→生成→排序流程。其余 iOS 界面、OCR、进程共享和键盘为本工程实现。保留原 `LICENSE` 与 `NOTICE`；不暗示原作者出品或背书。
