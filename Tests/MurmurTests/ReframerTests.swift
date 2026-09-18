import XCTest
@testable import Murmur

final class ReframerTests: XCTestCase {
    private let original = "we should ship the release on friday after the tests go green"

    func testAcceptsAPlausibleRewrite() {
        let candidate = "We should ship the release on Friday, after the tests go green."
        XCTAssertEqual(Reframer.accept(candidate, replacing: original), candidate)
    }

    func testStripsSurroundingQuotes() {
        let candidate = "\"We should ship on Friday once the tests are green.\""
        XCTAssertEqual(Reframer.accept(candidate, replacing: original),
                       "We should ship on Friday once the tests are green.")
    }

    func testRejectsARefusal() {
        XCTAssertNil(Reframer.accept("I can't help with that request.", replacing: original))
    }

    func testKeepsARefusalPhraseTheSpeakerActuallySaid() {
        let spoken = "I can't reproduce the crash on my machine no matter what I try"
        let candidate = "I can't reproduce the crash on my machine, no matter what I try."
        XCTAssertEqual(Reframer.accept(candidate, replacing: spoken), candidate)
    }

    func testRejectsAnAnswerInsteadOfARewrite() {
        let padded = String(repeating: "Here is a detailed explanation of the release process. ", count: 4)
        XCTAssertNil(Reframer.accept(padded, replacing: original))
    }

    func testRejectsASummary() {
        XCTAssertNil(Reframer.accept("Ship Friday.", replacing: original))
    }

    func testRejectsEmptyOutput() {
        XCTAssertNil(Reframer.accept("   ", replacing: original))
    }
}
