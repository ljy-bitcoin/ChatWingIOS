import SwiftUI
import ReplayKit
import PhotosUI

struct RootView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        TabView {
            NavigationStack { HomeView() }.tabItem { Label("助手", systemImage:"bubble.left.and.bubble.right") }
            NavigationStack { SettingsView() }.tabItem { Label("接口", systemImage:"slider.horizontal.3") }
            NavigationStack { ContactsView() }.tabItem { Label("联系人", systemImage:"person.crop.rectangle") }
            NavigationStack { TestView() }.tabItem { Label("识别与测试", systemImage:"viewfinder") }
        }
        .safeAreaInset(edge:.top) {
            if !model.notice.isEmpty {
                HStack(alignment:.top) {
                    Text(model.notice).font(.footnote).frame(maxWidth:.infinity, alignment:.leading)
                    Button { model.notice = "" } label: { Image(systemName:"xmark.circle.fill") }.accessibilityLabel("关闭提示")
                }.padding(12).background(.thinMaterial)
            }
        }
    }
}
struct BroadcastPicker: UIViewRepresentable {
    func makeUIView(context: Context) -> RPSystemBroadcastPickerView {
        let picker = RPSystemBroadcastPickerView(frame:CGRect(x:0,y:0,width:52,height:52))
        picker.preferredExtension = (Bundle.main.bundleIdentifier ?? "") + ".Broadcast"
        picker.showsMicrophoneButton = false
        return picker
    }
    func updateUIView(_ uiView: RPSystemBroadcastPickerView, context: Context) {}
}
struct HomeView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var pip: PiPController
    var body: some View {
        ScrollView {
            VStack(alignment:.leading, spacing:20) {
                VStack(alignment:.leading, spacing:8) {
                    Text("让回复多一点把握").font(.title2.bold())
                    Text("屏幕识别 · 语境分析 · 三条候选").foregroundStyle(.secondary)
                }
                GroupBox("当前联系人") {
                    VStack(alignment:.leading, spacing:12) {
                        Picker("联系人", selection:$model.settings.selectedContactID) {
                            ForEach(model.settings.contacts) { Text($0.name).tag(Optional($0.id)) }
                        }
                        .onChange(of:model.settings.selectedContactID) { _, _ in model.pause() }
                        Text("切换聊天前先暂停，并选对联系人。标题需与微信顶部显示一致。").font(.footnote).foregroundStyle(.secondary)
                    }
                }
                GroupBox("启动顺序") {
                    VStack(alignment:.leading, spacing:16) {
                        Button(model.enabled ? "暂停分析" : "1. 保存配置并开启分析（10分钟）") { model.enabled ? model.pause() : model.arm() }
                            .buttonStyle(.borderedProminent)
                        HStack { Text("2. 点右侧图标 → 开始直播"); Spacer(); BroadcastPicker().frame(width:52,height:52) }
                        Button(pip.active ? "关闭画中画" : "3. 开启画中画，再切到微信") { pip.active ? pip.stop() : pip.start() }.buttonStyle(.bordered)
                        Text("系统称作“直播”，本工程只在本机抽帧识字，识别出的文字才会发给所配模型。").font(.footnote).foregroundStyle(.secondary)
                    }.frame(maxWidth:.infinity,alignment:.leading)
                }
                VStack(alignment:.leading,spacing:8) {
                    Text("画中画预览").font(.headline)
                    PiPPreview(controller:pip).aspectRatio(16/9,contentMode:.fit).clipShape(RoundedRectangle(cornerRadius:16))
                    Text(pip.message).font(.caption).foregroundStyle(.secondary)
                }
                Label(model.broadcast.isFresh ? model.broadcast.message : "录屏未运行或心跳已中断", systemImage:model.broadcast.isFresh ? "record.circle.fill" : "record.circle")
                    .font(.footnote).foregroundStyle(model.broadcast.isFresh ? Color.teal : Color.secondary)
                if let result = model.result { ResultCard(result:result) }
                GroupBox("键盘设置") {
                    Text("系统设置 → 通用 → 键盘 → 键盘 → 添加新键盘 → 聊伴；开启“允许完全访问”。回到聊天输入框，长按地球键切换到聊伴，点候选插入，再手动发送。")
                        .font(.footnote).frame(maxWidth:.infinity,alignment:.leading)
                }
                Text("基于 Jev 聊天助手二次开发 · 非官方 iOS 移植\n模型输出是建议，OCR 的发言方划分需要核对。").font(.caption).foregroundStyle(.secondary)
            }.padding()
        }.navigationTitle("聊伴 ChatWing")
    }
}
struct ResultCard: View {
    var result: ResultEnvelope
    var body: some View {
        GroupBox("\(result.contactName) · \(result.status)") {
            VStack(alignment:.leading,spacing:12) {
                if let analysis = result.analysis {
                    Text("可能意图：\(analysis.intent)").font(.headline)
                    Text("冲突风险 \(Int(analysis.danger))/9 · \(analysis.action)")
                    Text("当前需求：\(analysis.need)").foregroundStyle(.secondary)
                    ForEach(Array(analysis.replies.enumerated()), id:\.element.id) { index, reply in
                        HStack {
                            Text("\(index+1). \(reply.text)").textSelection(.enabled)
                            Spacer()
                            Button { UIPasteboard.general.string = reply.text } label: { Image(systemName:"doc.on.doc") }.accessibilityLabel("复制候选")
                        }.padding(10).background(Color.teal.opacity(0.07),in:RoundedRectangle(cornerRadius:10))
                    }
                    if !analysis.warning.isEmpty { Text(analysis.warning).font(.caption).foregroundStyle(.secondary) }
                }
                DisclosureGroup("核对识别原文") {
                    ForEach(Array(result.messages.enumerated()), id:\.offset) { _, message in
                        Text("\(message.label)：\(message.text)").font(.footnote).frame(maxWidth:.infinity,alignment:.leading).textSelection(.enabled)
                    }
                }
            }.frame(maxWidth:.infinity,alignment:.leading)
        }
    }
}
struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        Form {
            Section("快速填写") {
                Button("Jev + OpenRouter") { model.preset("openrouter") }
                Button("Jev · TypeSafe 直连（只改判断接口）") { model.preset("typesafe") }
                Button("通用模式 · DeepSeek") { model.preset("compatible") }
                Text("预设来自上游配置；服务商可能更改模型名称或接口权限。所有字段都可编辑。").font(.caption)
            }
            Section("判断接口") {
                Picker("模式",selection:$model.settings.judgeMode) { ForEach(JudgeMode.allCases,id:\.self) { Text($0.label).tag($0) } }
                TextField("完整 HTTPS 地址",text:$model.settings.judgeURL).keyboardType(.URL)
                TextField("模型名称",text:$model.settings.judgeModel)
                SecureField("API Key",text:$model.judgeKey)
            }
            Section("回复接口 · Chat Completions") {
                TextField("完整 HTTPS 地址（含 /chat/completions）",text:$model.settings.replyURL).keyboardType(.URL)
                TextField("模型名称",text:$model.settings.replyModel)
                SecureField("API Key",text:$model.replyKey)
                Text("留空仅在两个接口域名相同时继承判断密钥；不同服务商需分别填写。").font(.caption)
            }
            Section("调用节奏") {
                Stepper("每 \(Int(model.settings.frameInterval)) 秒识别一次",value:$model.settings.frameInterval,in:1...10,step:1)
                Stepper("请求间隔至少 \(Int(model.settings.requestInterval)) 秒",value:$model.settings.requestInterval,in:6...60,step:2)
                Text("相同文字不重复调用；连续两次识别一致才分析。Jev 模式每次通常为判断、生成、排序三次请求。").font(.caption)
            }
            Section { Button("保存设置") { model.save() }.font(.headline) }
            Section("关于") {
                Link("原项目 jev-chat-jarvis",destination:URL(string:"https://github.com/jev-chat/jev-chat-jarvis")!)
                Text("基于 Jev 聊天助手二次开发，保留原作者 MIT LICENSE 与 NOTICE。独立 iOS 实现，不代表原作者出品或背书。").font(.caption)
            }
        }.textInputAutocapitalization(.never).autocorrectionDisabled().navigationTitle("接口配置")
    }
}
struct ContactsView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        Form {
            Section("联系人档案") {
                ForEach($model.settings.contacts) { $contact in
                    DisclosureGroup(contact.name.isEmpty ? "联系人" : contact.name) {
                        TextField("聊天顶部显示的名称",text:$contact.name)
                        TextField("关系，如朋友/同事/伴侣",text:$contact.relationship)
                        TextField("其它标题或别名，每行一个",text:$contact.aliases,axis:.vertical)
                        TextField("已知事实、偏好与待办",text:$contact.notes,axis:.vertical).lineLimit(3...8)
                    }
                }.onDelete { offsets in
                    if model.settings.contacts.count > offsets.count {
                        model.settings.contacts.remove(atOffsets:offsets)
                        if !model.settings.contacts.contains(where:{ $0.id == model.settings.selectedContactID }) {
                            model.settings.selectedContactID = model.settings.contacts.first?.id
                        }
                    }
                }
                Button("添加联系人") { model.settings.contacts.append(Contact()) }
            }
            Section("我的背景与话术") {
                TextEditor(text:$model.settings.knowledge).frame(minHeight:130)
                Text("只填写希望模型参考的事实。选定联系人的资料和这里的文字会随分析请求发送。第一版不自动保存聊天历史。").font(.caption)
            }
            Section { Button("保存档案") { model.save() } }
        }.navigationTitle("联系人与背景")
    }
}
struct TestView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        Form {
            Section("识别区域（竖屏，从顶部计算）") {
                Text("聊天正文识别范围").font(.subheadline.bold())
                SliderRow(title:"上边界",value:$model.settings.crop.top,range:0.05...0.45)
                SliderRow(title:"下边界",value:$model.settings.crop.bottom,range:0.50...0.95)
                SliderRow(title:"左边界",value:$model.settings.crop.left,range:0...0.25)
                SliderRow(title:"右边界",value:$model.settings.crop.right,range:0.75...1)
                Text("聊天标题识别范围（顶部）").font(.subheadline.bold())
                SliderRow(title:"上边界",value:titleCropBinding.top,range:0...0.16)
                SliderRow(title:"下边界",value:titleCropBinding.bottom,range:0.08...0.36)
                SliderRow(title:"左边界",value:titleCropBinding.left,range:0...0.40)
                SliderRow(title:"右边界",value:titleCropBinding.right,range:0.60...1)
                Toggle("仅分析标题匹配的联系人",isOn:$model.settings.requireTitleMatch)
                Text("正文和标题范围分别调整。默认正文在屏幕中间，标题在顶部中央。将画中画放在正文区域外。关闭标题匹配后，当前区域出现的其它页面文字也可能被发送给模型。正常聊天页面请保留该保护。").font(.caption)
                Button("保存识别配置") { model.save() }
            }
            Section("先用截图校准，再开启实时识别") {
                PhotosPicker(selection:$model.photo,matching:.images) { Label("选择一张聊天截图（本机识字）",systemImage:"photo") }
                    .onChange(of:model.photo) { _, _ in Task { await model.loadPhoto() } }
                TextEditor(text:$model.manualText).frame(minHeight:200)
                Text("每行以“我：”或“对方：”开头。先修正 OCR 错字和侧别，再分析。测试也会实际调用接口并计费。").font(.caption)
                Button(model.manualBusy ? "正在分析…" : "分析文字 / 测试两路接口") { model.runManual() }.disabled(model.manualBusy)
                if model.manualBusy { Button("取消") { model.pause() } }
            }
            if let result = model.result { Section { ResultCard(result:result) } }
            Section { Button("清除当前识别结果",role:.destructive) { model.clearLocal() } }
        }.navigationTitle("识别与测试")
    }
    private var titleCropBinding: Binding<TitleRegion> {
        Binding(get: { model.settings.titleCrop ?? TitleRegion() },
                set: { model.settings.titleCrop = $0 })
    }
}
struct SliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var body: some View { VStack(alignment:.leading) { Text("\(title)：\(Int(value*100))%").font(.footnote); Slider(value:$value,in:range,step:0.01) } }
}
import SwiftUI
import ReplayKit
import PhotosUI

struct RootView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        TabView {
            NavigationStack { HomeView() }.tabItem { Label("助手", systemImage:"bubble.left.and.bubble.right") }
            NavigationStack { SettingsView() }.tabItem { Label("接口", systemImage:"slider.horizontal.3") }
            NavigationStack { ContactsView() }.tabItem { Label("联系人", systemImage:"person.crop.rectangle") }
            NavigationStack { TestView() }.tabItem { Label("识别与测试", systemImage:"viewfinder") }
        }
        .safeAreaInset(edge:.top) {
            if !model.notice.isEmpty {
                HStack(alignment:.top) {
                    Text(model.notice).font(.footnote).frame(maxWidth:.infinity, alignment:.leading)
                    Button { model.notice = "" } label: { Image(systemName:"xmark.circle.fill") }.accessibilityLabel("关闭提示")
                }.padding(12).background(.thinMaterial)
            }
        }
    }
}
struct BroadcastPicker: UIViewRepresentable {
    func makeUIView(context: Context) -> RPSystemBroadcastPickerView {
        let picker = RPSystemBroadcastPickerView(frame:CGRect(x:0,y:0,width:52,height:52))
        picker.preferredExtension = (Bundle.main.bundleIdentifier ?? "") + ".Broadcast"
        picker.showsMicrophoneButton = false
        return picker
    }
    func updateUIView(_ uiView: RPSystemBroadcastPickerView, context: Context) {}
}
struct HomeView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var pip: PiPController
    var body: some View {
        ScrollView {
            VStack(alignment:.leading, spacing:20) {
                VStack(alignment:.leading, spacing:8) {
                    Text("让回复多一点把握").font(.title2.bold())
                    Text("屏幕识别 · 语境分析 · 三条候选").foregroundStyle(.secondary)
                }
                GroupBox("当前联系人") {
                    VStack(alignment:.leading, spacing:12) {
                        Picker("联系人", selection:$model.settings.selectedContactID) {
                            ForEach(model.settings.contacts) { Text($0.name).tag(Optional($0.id)) }
                        }
                        .onChange(of:model.settings.selectedContactID) { _, _ in model.pause() }
                        Text("切换聊天前先暂停，并选对联系人。标题需与微信顶部显示一致。").font(.footnote).foregroundStyle(.secondary)
                    }
                }
                GroupBox("启动顺序") {
                    VStack(alignment:.leading, spacing:16) {
                        Button(model.enabled ? "暂停分析" : "1. 保存配置并开启分析（10分钟）") { model.enabled ? model.pause() : model.arm() }
                            .buttonStyle(.borderedProminent)
                        HStack { Text("2. 点右侧图标 → 开始直播"); Spacer(); BroadcastPicker().frame(width:52,height:52) }
                        Button(pip.active ? "关闭画中画" : "3. 开启画中画，再切到微信") { pip.active ? pip.stop() : pip.start() }.buttonStyle(.bordered)
                        Text("系统称作“直播”，本工程只在本机抽帧识字，识别出的文字才会发给所配模型。").font(.footnote).foregroundStyle(.secondary)
                    }.frame(maxWidth:.infinity,alignment:.leading)
                }
                VStack(alignment:.leading,spacing:8) {
                    Text("画中画预览").font(.headline)
                    PiPPreview(controller:pip).aspectRatio(16/9,contentMode:.fit).clipShape(RoundedRectangle(cornerRadius:16))
                    Text(pip.message).font(.caption).foregroundStyle(.secondary)
                }
                Label(model.broadcast.isFresh ? model.broadcast.message : "录屏未运行或心跳已中断", systemImage:model.broadcast.isFresh ? "record.circle.fill" : "record.circle")
                    .font(.footnote).foregroundStyle(model.broadcast.isFresh ? Color.teal : Color.secondary)
                if let result = model.result { ResultCard(result:result) }
                GroupBox("键盘设置") {
                    Text("系统设置 → 通用 → 键盘 → 键盘 → 添加新键盘 → 聊伴；开启“允许完全访问”。回到聊天输入框，长按地球键切换到聊伴，点候选插入，再手动发送。")
                        .font(.footnote).frame(maxWidth:.infinity,alignment:.leading)
                }
                Text("基于 Jev 聊天助手二次开发 · 非官方 iOS 移植\n模型输出是建议，OCR 的发言方划分需要核对。").font(.caption).foregroundStyle(.secondary)
            }.padding()
        }.navigationTitle("聊伴 ChatWing")
    }
}
struct ResultCard: View {
    var result: ResultEnvelope
    var body: some View {
        GroupBox("\(result.contactName) · \(result.status)") {
            VStack(alignment:.leading,spacing:12) {
                if let analysis = result.analysis {
                    Text("可能意图：\(analysis.intent)").font(.headline)
                    Text("冲突风险 \(Int(analysis.danger))/9 · \(analysis.action)")
                    Text("当前需求：\(analysis.need)").foregroundStyle(.secondary)
                    ForEach(Array(analysis.replies.enumerated()), id:\.element.id) { index, reply in
                        HStack {
                            Text("\(index+1). \(reply.text)").textSelection(.enabled)
                            Spacer()
                            Button { UIPasteboard.general.string = reply.text } label: { Image(systemName:"doc.on.doc") }.accessibilityLabel("复制候选")
                        }.padding(10).background(Color.teal.opacity(0.07),in:RoundedRectangle(cornerRadius:10))
                    }
                    if !analysis.warning.isEmpty { Text(analysis.warning).font(.caption).foregroundStyle(.secondary) }
                }
                DisclosureGroup("核对识别原文") {
                    ForEach(Array(result.messages.enumerated()), id:\.offset) { _, message in
                        Text("\(message.label)：\(message.text)").font(.footnote).frame(maxWidth:.infinity,alignment:.leading).textSelection(.enabled)
                    }
                }
            }.frame(maxWidth:.infinity,alignment:.leading)
        }
    }
}
struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        Form {
            Section("快速填写") {
                Button("Jev + OpenRouter") { model.preset("openrouter") }
                Button("Jev · TypeSafe 直连（只改判断接口）") { model.preset("typesafe") }
                Button("通用模式 · DeepSeek") { model.preset("compatible") }
                Text("预设来自上游配置；服务商可能更改模型名称或接口权限。所有字段都可编辑。").font(.caption)
            }
            Section("判断接口") {
                Picker("模式",selection:$model.settings.judgeMode) { ForEach(JudgeMode.allCases,id:\.self) { Text($0.label).tag($0) } }
                TextField("完整 HTTPS 地址",text:$model.settings.judgeURL).keyboardType(.URL)
                TextField("模型名称",text:$model.settings.judgeModel)
                SecureField("API Key",text:$model.judgeKey)
            }
            Section("回复接口 · Chat Completions") {
                TextField("完整 HTTPS 地址（含 /chat/completions）",text:$model.settings.replyURL).keyboardType(.URL)
                TextField("模型名称",text:$model.settings.replyModel)
                SecureField("API Key",text:$model.replyKey)
                Text("留空仅在两个接口域名相同时继承判断密钥；不同服务商需分别填写。").font(.caption)
            }
            Section("调用节奏") {
                Stepper("每 \(Int(model.settings.frameInterval)) 秒识别一次",value:$model.settings.frameInterval,in:1...10,step:1)
                Stepper("请求间隔至少 \(Int(model.settings.requestInterval)) 秒",value:$model.settings.requestInterval,in:6...60,step:2)
                Text("相同文字不重复调用；连续两次识别一致才分析。Jev 模式每次通常为判断、生成、排序三次请求。").font(.caption)
            }
            Section { Button("保存设置") { model.save() }.font(.headline) }
            Section("关于") {
                Link("原项目 jev-chat-jarvis",destination:URL(string:"https://github.com/jev-chat/jev-chat-jarvis")!)
                Text("基于 Jev 聊天助手二次开发，保留原作者 MIT LICENSE 与 NOTICE。独立 iOS 实现，不代表原作者出品或背书。").font(.caption)
            }
        }.textInputAutocapitalization(.never).autocorrectionDisabled().navigationTitle("接口配置")
    }
}
struct ContactsView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        Form {
            Section("联系人档案") {
                ForEach($model.settings.contacts) { $contact in
                    DisclosureGroup(contact.name.isEmpty ? "联系人" : contact.name) {
                        TextField("聊天顶部显示的名称",text:$contact.name)
                        TextField("关系，如朋友/同事/伴侣",text:$contact.relationship)
                        TextField("其它标题或别名，每行一个",text:$contact.aliases,axis:.vertical)
                        TextField("已知事实、偏好与待办",text:$contact.notes,axis:.vertical).lineLimit(3...8)
                    }
                }.onDelete { offsets in
                    if model.settings.contacts.count > offsets.count {
                        model.settings.contacts.remove(atOffsets:offsets)
                        if !model.settings.contacts.contains(where:{ $0.id == model.settings.selectedContactID }) {
                            model.settings.selectedContactID = model.settings.contacts.first?.id
                        }
                    }
                }
                Button("添加联系人") { model.settings.contacts.append(Contact()) }
            }
            Section("我的背景与话术") {
                TextEditor(text:$model.settings.knowledge).frame(minHeight:130)
                Text("只填写希望模型参考的事实。选定联系人的资料和这里的文字会随分析请求发送。第一版不自动保存聊天历史。").font(.caption)
            }
            Section { Button("保存档案") { model.save() } }
        }.navigationTitle("联系人与背景")
    }
}
struct TestView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        Form {
            Section("识别区域（竖屏，从顶部计算）") {
                SliderRow(title:"上边界",value:$model.settings.crop.top,range:0.05...0.45)
                SliderRow(title:"下边界",value:$model.settings.crop.bottom,range:0.50...0.95)
                SliderRow(title:"左边界",value:$model.settings.crop.left,range:0...0.25)
                SliderRow(title:"右边界",value:$model.settings.crop.right,range:0.75...1)
                Toggle("仅分析标题匹配的联系人",isOn:$model.settings.requireTitleMatch)
                Text("默认只识别画面中间 18%–70% 的区域。将画中画放在区域外。关闭标题匹配后，当前区域出现的其它页面文字也可能被发送给模型。").font(.caption)
                Button("保存识别配置") { model.save() }
            }
            Section("先用截图校准，再开启实时识别") {
                PhotosPicker(selection:$model.photo,matching:.images) { Label("选择一张聊天截图（本机识字）",systemImage:"photo") }
                    .onChange(of:model.photo) { _, _ in Task { await model.loadPhoto() } }
                TextEditor(text:$model.manualText).frame(minHeight:200)
                Text("每行以“我：”或“对方：”开头。先修正 OCR 错字和侧别，再分析。测试也会实际调用接口并计费。").font(.caption)
                Button(model.manualBusy ? "正在分析…" : "分析文字 / 测试两路接口") { model.runManual() }.disabled(model.manualBusy)
                if model.manualBusy { Button("取消") { model.pause() } }
            }
            if let result = model.result { Section { ResultCard(result:result) } }
            Section { Button("清除当前识别结果",role:.destructive) { model.clearLocal() } }
        }.navigationTitle("识别与测试")
    }
}
struct SliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var body: some View { VStack(alignment:.leading) { Text("\(title)：\(Int(value*100))%").font(.footnote); Slider(value:$value,in:range,step:0.01) } }
}
