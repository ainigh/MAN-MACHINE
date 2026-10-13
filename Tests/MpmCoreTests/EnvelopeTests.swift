import XCTest
@testable import MpmCore

final class EnvelopeTests: XCTestCase {
    func testStep1EnvelopeFence() {
        let raw = """
        Sure, here you go.
        ```envelope
        {"say":"Hello","ask":null,"patch":[{"op":"update_node","id":"n_1","fields":{"status":"done"}}],"next":"2026-10-14T09:00:00Z"}
        ```
        """
        let o = EnvelopeParser.parse(raw)
        XCTAssertEqual(o.step, .envelopeFence)
        XCTAssertEqual(o.envelope.say, "Hello")
        XCTAssertEqual(o.envelope.patch, [.updateNode(id: "n_1", fields: NodeFields(status: .done))])
        XCTAssertNotNil(o.envelope.next)
    }

    func testStep2AnyFence() {
        let raw = "```json\n{\"say\":\"hi\",\"extra\":1}\n```"
        let o = EnvelopeParser.parse(raw)
        XCTAssertEqual(o.step, .anyFence)
        XCTAssertEqual(o.warnings, ["dropped key extra"])
    }

    func testStep3Brace() {
        let o = EnvelopeParser.parse("Here: {\"say\":\"x\",\"patch\":[]} thanks")
        XCTAssertEqual(o.step, .braceSubstring); XCTAssertEqual(o.envelope.say, "x")
    }

    func testStep4Lines() {
        let o = EnvelopeParser.parse("say: Keep going.\nask: Did you finish?\n")
        XCTAssertEqual(o.step, .lineOriented)
        XCTAssertEqual(o.envelope.ask, "Did you finish?"); XCTAssertEqual(o.envelope.patch, [])
    }

    func testStep5Prose() {
        let o = EnvelopeParser.parse("Just keep working on the API.")
        XCTAssertEqual(o.step, .proseOnly); XCTAssertEqual(o.envelope.say, "Just keep working on the API.")
    }

    func testLadderNeverInventsOps() {
        let raw = "```envelope\n{\"say\":\"s\",\"patch\":[{\"op\":\"add_node\",\"title\":\"no parent\"},{\"op\":\"delete_everything\"}]}\n```"
        let o = EnvelopeParser.parse(raw)
        XCTAssertEqual(o.envelope.patch, [])
        XCTAssertFalse(o.warnings.isEmpty)
        // blocked is never settable, even by a well-formed op
        let raw2 = "```envelope\n{\"say\":\"s\",\"patch\":[{\"op\":\"update_node\",\"id\":\"n\",\"fields\":{\"status\":\"blocked\"}}]}\n```"
        XCTAssertEqual(EnvelopeParser.parse(raw2).envelope.patch, [])
    }

    func testAddNodeWireFormat() {
        let raw = "```envelope\n{\"say\":\"\",\"patch\":[{\"op\":\"add_node\",\"tmp_id\":\"a\",\"parent\":\"root\",\"title\":\"T\",\"status\":\"next\"},{\"op\":\"add_dep\",\"id\":\"tmp:a\",\"dep\":\"n_2\"}]}\n```"
        let o = EnvelopeParser.parse(raw)
        XCTAssertEqual(o.envelope.patch.count, 2)
        if case .addNode(let tmp, let p, let title, let st, _, _, _) = o.envelope.patch[0] {
            XCTAssertEqual(tmp, "a"); XCTAssertEqual(p, "root"); XCTAssertEqual(title, "T"); XCTAssertEqual(st, .next)
        } else { XCTFail() }
    }
}
