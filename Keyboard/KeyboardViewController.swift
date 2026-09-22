import UIKit

final class KeyboardViewController: UIInputViewController {
    private let stack = UIStackView()
    private let status = UILabel()
    private let detail = UILabel()
    private var replyButtons: [UIButton] = []
    private var timer: Timer?
    private var displayed: ResultEnvelope?
    private var insertionMessage: String?
    private var insertedResultAt: Date?
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .secondarySystemBackground
        stack.axis = .vertical; stack.spacing = 8; stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo:view.leadingAnchor, constant:12), stack.trailingAnchor.constraint(equalTo:view.trailingAnchor, constant:-12),
            stack.topAnchor.constraint(equalTo:view.topAnchor, constant:10), stack.bottomAnchor.constraint(lessThanOrEqualTo:view.bottomAnchor, constant:-10),
            view.heightAnchor.constraint(equalToConstant:310)
        ])
        status.font = .systemFont(ofSize:14, weight:.semibold); status.numberOfLines = 2
        detail.font = .systemFont(ofSize:11); detail.textColor = .secondaryLabel; detail.numberOfLines = 2
        stack.addArrangedSubview(status); stack.addArrangedSubview(detail)
        for i in 0..<3 {
            let button = UIButton(type:.system)
            button.tag = i; button.titleLabel?.numberOfLines = 2; button.titleLabel?.font = .systemFont(ofSize:15)
            button.contentHorizontalAlignment = .leading
            button.heightAnchor.constraint(equalToConstant:52).isActive = true
            button.backgroundColor = .tertiarySystemBackground; button.layer.cornerRadius = 8
            button.addTarget(self, action:#selector(insertReply(_:)), for:.touchUpInside)
            stack.addArrangedSubview(button); replyButtons.append(button)
        }
        let controls = UIStackView(); controls.axis = .horizontal; controls.spacing = 14; controls.distribution = .fillEqually
        let next = UIButton(type:.system); next.setTitle("🌐 切换键盘", for:.normal)
        next.addTarget(self, action:#selector(handleInputModeList(from:with:)), for:.allTouchEvents)
        let pause = UIButton(type:.system); pause.setTitle("暂停分析", for:.normal); pause.addTarget(self, action:#selector(pauseAnalysis), for:.touchUpInside)
        let back = UIButton(type:.system); back.setTitle("⌫ 删除", for:.normal); back.addTarget(self, action:#selector(deleteCharacter), for:.touchUpInside)
        [next,pause,back].forEach { controls.addArrangedSubview($0) }; stack.addArrangedSubview(controls)
    }
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated); refresh()
        timer?.invalidate(); timer = Timer.scheduledTimer(withTimeInterval:1, repeats:true) { [weak self] _ in self?.refresh() }
    }
    override func viewWillDisappear(_ animated: Bool) { super.viewWillDisappear(animated); timer?.invalidate(); timer = nil }
    override func textDidChange(_ textInput: UITextInput?) { super.textDidChange(textInput); insertionMessage = nil }
    private func refresh() {
        let store = SharedStore.shared
        guard hasFullAccess, store.available else {
            status.text = "CW·聊伴：请允许键盘完全访问"
            detail.text = "用于读取主程序共享的候选回复；本键盘不调用模型，也不上传输入内容。"
            displayed = nil; clearButtons(); return
        }
        let latest = store.usableResult()
        if displayed?.createdAt != latest?.createdAt { insertionMessage = nil }
        displayed = latest
        status.text = "CW·聊伴 · \(latest?.contactName ?? store.settings.selectedContact.name)"
        detail.text = insertionMessage ?? (latest == nil ? "暂无有效候选；请确认录屏、联系人和分析开关。" : "确认当前联系人后点选；只插入文字，发送由你点击。")
        for (index, button) in replyButtons.enumerated() {
            let replies = latest?.analysis?.replies ?? []
            button.isEnabled = index < replies.count
            if insertedResultAt == latest?.createdAt { button.isEnabled = false }
            button.setTitle(index < replies.count ? "  \(index+1). \(replies[index].text)" : "  等待候选…", for:.normal)
        }
    }
    private func clearButtons() { replyButtons.forEach { $0.isEnabled = false; $0.setTitle("等待授权", for:.normal) } }
    @objc private func insertReply(_ button: UIButton) {
        guard let displayed, let current = SharedStore.shared.usableResult(), current.createdAt == displayed.createdAt,
              current.sessionID == displayed.sessionID, let replies = current.analysis?.replies, button.tag < replies.count else { refresh(); return }
        if let before = textDocumentProxy.documentContextBeforeInput, !before.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty {
            insertionMessage = "输入框已有文字，请先清空或切换原键盘编辑，避免重复追加。"; refresh(); return
        }
        if let after = textDocumentProxy.documentContextAfterInput, !after.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty {
            insertionMessage = "光标后还有文字，请先清空输入框。"; refresh(); return
        }
        textDocumentProxy.insertText(replies[button.tag].text)
        insertedResultAt = current.createdAt
        insertionMessage = "已插入。请核对文字后自行点击发送。"; refresh()
    }
    @objc private func pauseAnalysis() { try? SharedStore.shared.setEnabled(false); refresh() }
    @objc private func deleteCharacter() { textDocumentProxy.deleteBackward() }
}
