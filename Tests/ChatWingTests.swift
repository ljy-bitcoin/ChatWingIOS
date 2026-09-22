import XCTest
@testable import ChatWing

final class ChatWingTests: XCTestCase {
    func testReplyParserRejectsMissingOrDuplicateReplies() throws {
        XCTAssertThrowsError(try APIClient.parseReplies("[\"你好\",\"你好\",\"收到\"]"))
        XCTAssertThrowsError(try APIClient.parseReplies("[\"收到\"]"))
        XCTAssertThrowsError(try APIClient.parseReplies("not json"))
        XCTAssertEqual(try APIClient.parseReplies("```json\n[\"收到\",\"我查一下\",\"谢谢提醒\"]\n```"), ["收到","我查一下","谢谢提醒"])
    }
    func testEndpointDoesNotAcceptCredentialsOrInsecureTransport() throws {
        XCTAssertThrowsError(try APIClient.endpoint("http://example.com/chat/completions"))
        XCTAssertThrowsError(try APIClient.endpoint("https://secret@example.com/chat/completions"))
        XCTAssertThrowsError(try APIClient.endpoint("https://example.com/chat/completions?key=secret"))
        XCTAssertEqual(try APIClient.endpoint("https://example.com/v1/chat/completions").path,"/v1/chat/completions")
    }
    func testOldSessionAndWrongContactCannotUseReplies() {
        let now = Date(), session = UUID(), contact = UUID()
        let control = SessionControl(id:session,enabled:true,expiresAt:now.addingTimeInterval(60))
        var result = ResultEnvelope(sessionID:session,contactID:contact,contactName:"朋友",createdAt:now,
            analysis:Analysis(intent:"日常聊天",danger:0,action:"回应",need:"无",replies:[]),status:"完成")
        XCTAssertTrue(result.isUsable(control:control,contactID:contact,now:now))
        XCTAssertFalse(result.isUsable(control:control,contactID:UUID(),now:now))
        result.sessionID = UUID()
        XCTAssertFalse(result.isUsable(control:control,contactID:contact,now:now))
        result.sessionID = session; result.createdAt = now.addingTimeInterval(-181)
        XCTAssertFalse(result.isUsable(control:control,contactID:contact,now:now))
        result.createdAt = now.addingTimeInterval(5)
        XCTAssertFalse(result.isUsable(control:control,contactID:contact,now:now))
    }
    func testPausedSessionCannotUseReplies() {
        let session = UUID(), contact = UUID(), now = Date()
        let result = ResultEnvelope(sessionID:session,contactID:contact,contactName:"朋友",createdAt:now,
            analysis:Analysis(intent:"聊天",danger:0,action:"回应",need:"无",replies:[]),status:"完成")
        let paused = SessionControl(id:session,enabled:false,expiresAt:now.addingTimeInterval(60))
        XCTAssertFalse(result.isUsable(control:paused,contactID:contact,now:now))
    }
    func testOCRPreservesUncertainSpeakerAndReadingOrder() {
        let lines = [OCRLine(text:"右侧回复",x:0.70,y:0.30,width:0.22,height:0.025),
                     OCRLine(text:"对方的话",x:0.08,y:0.20,width:0.25,height:0.025),
                     OCRLine(text:"无法区分",x:0.25,y:0.40,width:0.5,height:0.025)]
        let output = TextLogic.messages(from:lines)
        XCTAssertEqual(output.map(\.speaker), [.other,.me,.unknown])
    }
    func testFingerprintChangesWhenSpeakerOrContactChanges() {
        let id = UUID()
        let first = [ChatMessage(speaker:.me,text:"收到")]
        XCTAssertNotEqual(TextLogic.fingerprint(first,contactID:id),TextLogic.fingerprint([ChatMessage(speaker:.other,text:"收到")],contactID:id))
        XCTAssertNotEqual(TextLogic.fingerprint(first,contactID:id),TextLogic.fingerprint(first,contactID:UUID()))
    }
    func testTitleRequiresExactNameOrAlias() {
        let contact = Contact(name:"小李",aliases:"小李（工作）",relationship:"同事")
        XCTAssertTrue(TextLogic.matchesTitle("小李",contact:contact))
        XCTAssertTrue(TextLogic.matchesTitle("小李（工作）",contact:contact))
        XCTAssertFalse(TextLogic.matchesTitle("小李的群聊",contact:contact))
    }
    func testQuestionResourceHasSevenQuestions() throws {
        let bundle = Bundle(for:AppModel.self)
        let url = try XCTUnwrap(bundle.url(forResource:"JudgeQuestions",withExtension:"json"))
        let value = try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:url)) as? [String:Any])
        XCTAssertEqual(value.count,7)
        XCTAssertEqual((value["danger_level"] as? [String:Any])?["criteria"] as? [String] != nil,true)
    }
}
