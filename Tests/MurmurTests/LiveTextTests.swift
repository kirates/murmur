import XCTest
@testable import Murmur

final class LiveTextTests: XCTestCase {
    func testAppendingNeedsNoBackspaces() {
        let edit = LiveText.edit(from: "the build is", to: "the build is green")
        XCTAssertEqual(edit, LiveText.Edit(backspaces: 0, insertion: " green"))
    }

    func testRevisingTheTailBackspacesOnlyTheTail() {
        let edit = LiveText.edit(from: "I read the file", to: "I red the file")
        XCTAssertEqual(edit, LiveText.Edit(backspaces: 11, insertion: "d the file"))
    }

    func testAWholeRewriteReplacesEverything() {
        let edit = LiveText.edit(from: "wreck a nice beach", to: "recognise speech")
        XCTAssertEqual(edit.backspaces, 18)
        XCTAssertEqual(edit.insertion, "recognise speech")
    }

    func testIdenticalTextIsANoOp() {
        XCTAssertTrue(LiveText.edit(from: "ship it friday", to: "ship it friday").isEmpty)
    }

    func testShrinkingTextOnlyBackspaces() {
        let edit = LiveText.edit(from: "ship it on friday", to: "ship it")
        XCTAssertEqual(edit, LiveText.Edit(backspaces: 10, insertion: ""))
    }

    func testFromEmpty() {
        XCTAssertEqual(LiveText.edit(from: "", to: "hello"),
                       LiveText.Edit(backspaces: 0, insertion: "hello"))
    }

    func testToEmptyClearsEverything() {
        XCTAssertEqual(LiveText.edit(from: "hello", to: ""),
                       LiveText.Edit(backspaces: 5, insertion: ""))
    }

    func testCountsGraphemeClustersNotScalars() {
        // One backspace deletes the whole flag, not half of it.
        let edit = LiveText.edit(from: "🇬🇭 ship", to: "🇬🇭 shipped")
        XCTAssertEqual(edit, LiveText.Edit(backspaces: 0, insertion: "ped"))

        let replace = LiveText.edit(from: "done 👍🏽", to: "done 🚀")
        XCTAssertEqual(replace.backspaces, 1)
        XCTAssertEqual(replace.insertion, "🚀")
    }

    func testAppliedEditReproducesTheTarget() {
        let current = "the tests are passing now"
        let target = "the tests are failing now"
        let edit = LiveText.edit(from: current, to: target)
        let kept = String(current.dropLast(edit.backspaces))
        XCTAssertEqual(kept + edit.insertion, target)
    }
}
