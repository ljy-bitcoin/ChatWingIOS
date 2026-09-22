import Foundation
import CryptoKit

struct OCRLine {
    var text: String
    var x: Double
    var y: Double
    var width: Double
    var height: Double
}
enum TextLogic {
    static func matchesTitle(_ title: String, contact: Contact) -> Bool {
        let normalized = title.replacingOccurrences(of: " ", with: "").lowercased()
        return contact.titleTokens.contains {
            normalized == $0.replacingOccurrences(of: " ", with: "").lowercased()
        }
    }
    static func messages(from lines: [OCRLine]) -> [ChatMessage] {
        // OCR geometry is a heuristic, not access to the chat app's message tree.
        var out: [(ChatMessage, OCRLine)] = []
        for line in lines.sorted(by: { $0.y < $1.y }) {
            let text = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty || text.contains("CW·") { continue }
            if text.range(of: "^(\\d{1,2}:\\d{2}|已读|未读|发送|按住说话|昨天.*|星期[一二三四五六日天].*)$", options: .regularExpression) != nil { continue }
            let left = line.x, right = 1 - line.x - line.width
            let side: Speaker = abs(left - right) < 0.07 ? .unknown : left < right ? .other : .me
            if let last = out.last, last.0.speaker == side,
               line.y - (last.1.y + last.1.height) < min(line.height, last.1.height) * 0.55,
               abs(line.x - last.1.x) < 0.045 {
                out[out.count - 1].0.text += "\n" + text
                out[out.count - 1].1 = line
            } else { out.append((ChatMessage(speaker: side, text: String(text.prefix(1500))), line)) }
        }
        return Array(out.suffix(10).map(\.0))
    }
    static func fingerprint(_ messages: [ChatMessage], contactID: UUID) -> String {
        let values = messages.map { [ $0.speaker.rawValue, $0.text ] }
        let data = (try? JSONEncoder().encode(values)) ?? Data()
        return SHA256.hash(data: Data(contactID.uuidString.utf8) + data).map { String(format: "%02x", $0) }.joined()
    }
    static func parseManual(_ text: String) -> [ChatMessage] {
        text.components(separatedBy: "\n").compactMap { line in
            let text = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty { return nil }
            for (prefix, speaker) in [("我：", Speaker.me), ("我:", .me), ("对方：", .other), ("对方:", .other)] {
                if text.hasPrefix(prefix) { return ChatMessage(speaker: speaker, text: String(text.dropFirst(prefix.count))) }
            }
            return ChatMessage(speaker: .unknown, text: text)
        }.suffix(10).map { $0 }
    }
}
