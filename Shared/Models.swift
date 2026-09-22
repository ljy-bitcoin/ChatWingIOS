import Foundation

enum Speaker: String, Codable { case me, other, unknown }
struct ChatMessage: Codable, Equatable {
    var speaker: Speaker
    var text: String
    var label: String { speaker == .me ? "我" : speaker == .other ? "对方" : "侧别不确定" }
}
struct CropRegion: Codable, Equatable {
    // Normalized coordinates with origin at top-left, after orientation correction.
    var top = 0.18
    var bottom = 0.70
    var left = 0.04
    var right = 0.96
    var isValid: Bool { top >= 0 && bottom <= 1 && left >= 0 && right <= 1 && bottom - top >= 0.1 && right - left >= 0.3 }
}
struct Contact: Codable, Identifiable, Equatable {
    var id = UUID()
    var name = "新联系人"
    var aliases = ""
    var relationship = "朋友"
    var notes = ""
    var titleTokens: [String] { ([name] + aliases.components(separatedBy: "\n")).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty } }
}
enum JudgeMode: String, Codable, CaseIterable {
    case jev, compatible
    var label: String { self == .jev ? "Jev 原生判断接口" : "通用模型 JSON 判断" }
}
struct Settings: Codable {
    var revision = UUID()
    var judgeMode = JudgeMode.jev
    var judgeURL = "https://openrouter.ai/api/alpha/decisions"
    var judgeModel = "typesafe/jev-1.13"
    var replyURL = "https://openrouter.ai/api/v1/chat/completions"
    var replyModel = "deepseek/deepseek-chat-v3.1"
    var contacts = [Contact()]
    var selectedContactID: UUID?
    var knowledge = ""
    var crop = CropRegion()
    var frameInterval = 2.0
    var requestInterval = 12.0
    var requireTitleMatch = true
    var selectedContact: Contact { contacts.first { $0.id == selectedContactID } ?? contacts.first ?? Contact() }
    var background: String { "联系人：\(selectedContact.name)\n关系：\(selectedContact.relationship)\n备注：\(selectedContact.notes)\n我的背景与话术：\(knowledge)" }
}
struct SessionControl: Codable {
    var id = UUID()
    var enabled = false
    var expiresAt = Date.distantPast
    var isEnabled: Bool { enabled && expiresAt > Date() }
}
struct AppPresence: Codable { var foreground: Bool }
struct BroadcastStatus: Codable {
    var running = false
    var paused = false
    var updatedAt = Date()
    var message = "尚未启动录屏"
    var isFresh: Bool { running && !paused && Date().timeIntervalSince(updatedAt) < 15 }
}
struct Reply: Codable, Identifiable, Equatable {
    var id = UUID()
    var text: String
    var probability: Double?
}
struct Analysis: Codable, Equatable {
    var intent: String
    var danger: Double
    var action: String
    var need: String
    var substantive: Bool?
    var replies: [Reply]
    var warning = ""
}
struct ResultEnvelope: Codable {
    var sessionID: UUID
    var contactID: UUID
    var contactName: String
    var createdAt = Date()
    var messages: [ChatMessage] = []
    var analysis: Analysis?
    var status: String
    var source: String = "live"
    func isUsable(control: SessionControl, contactID: UUID, now: Date = Date()) -> Bool {
        sessionID == control.id && self.contactID == contactID && control.enabled && control.expiresAt > now &&
        now.timeIntervalSince(createdAt) >= 0 && now.timeIntervalSince(createdAt) < 180 && analysis != nil
    }
}
enum ChatWingError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case let .message(text) = self { return text }; return nil }
}
enum Labels {
    static let translations = [
        "confirm_you_care":"确认你是否在意", "vent_anger":"表达不满", "request_action":"希望采取行动",
        "seek_explanation":"寻求解释", "casual_chat":"日常聊天", "close_topic":"结束话题",
        "check_history":"先查清前文", "apologize":"为已知过失道歉", "give_commitment":"给出具体安排",
        "explain":"解释事实", "acknowledge":"回应感受", "say_less":"少说或暂不追加", "make_plan":"商量安排",
        "apology":"道歉", "action":"行动", "explanation":"解释", "care":"关心与重视", "nothing":"无需额外回应"
    ]
    static func text(_ value: String) -> String { translations[value] ?? value }
}
