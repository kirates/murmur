import XCTest
@testable import Murmur

@MainActor
final class InserterTests: XCTestCase {
    func testShortTextIsOneChunk() {
        XCTAssertEqual(Inserter.chunks(of: "hello", size: 16), ["hello"])
    }

    func testLongTextIsSplitIntoChunks() {
        let text = String(repeating: "a", count: 40)
        let chunks = Inserter.chunks(of: text, size: 16)
        XCTAssertEqual(chunks.count, 3)
        XCTAssertEqual(chunks.joined(), text)
    }

    func testChunkingIsLossless() {
        let text = "Ship the release on Friday, once every test is green."
        XCTAssertEqual(Inserter.chunks(of: text, size: 7).joined(), text)
    }

    func testDoesNotSplitAGraphemeCluster() {
        let text = "e\u{0301}" + String(repeating: "x", count: 20)
        for chunk in Inserter.chunks(of: text, size: 4) {
            XCTAssertFalse(chunk.unicodeScalars.first?.properties.isDiacritic ?? false)
        }
        XCTAssertEqual(Inserter.chunks(of: text, size: 4).joined(), text)
    }

    func testEmojiSurviveChunking() {
        let text = "done 👍🏽 shipping 🚀 now"
        XCTAssertEqual(Inserter.chunks(of: text, size: 3).joined(), text)
    }

    func testEmptyTextProducesNoChunks() {
        XCTAssertEqual(Inserter.chunks(of: "", size: 16), [])
    }
}
