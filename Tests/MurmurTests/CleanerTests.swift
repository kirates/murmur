import XCTest
@testable import Murmur

final class CleanerTests: XCTestCase {
    func testRemovesStandaloneFillers() {
        XCTAssertEqual(Cleaner.clean("um I think uh the build is broken"), "I think the build is broken")
        XCTAssertEqual(Cleaner.clean("er, we should ship it"), "We should ship it")
    }

    func testKeepsWordsThatMerelyContainAFiller() {
        XCTAssertEqual(Cleaner.clean("the umbrella is ahead of us"), "The umbrella is ahead of us")
        XCTAssertEqual(Cleaner.clean("run the hmac check"), "Run the hmac check")
    }

    func testCollapsesStutters() {
        XCTAssertEqual(Cleaner.clean("the the the config is wrong"), "The config is wrong")
        XCTAssertEqual(Cleaner.clean("I I need a branch"), "I need a branch")
    }

    func testKeepsLegitimateDoubledWords() {
        XCTAssertEqual(Cleaner.clean("I had had enough of it"), "I had had enough of it")
        XCTAssertEqual(Cleaner.clean("the thing that that broke"), "The thing that that broke")
    }

    func testStripsLeadingMarkers() {
        XCTAssertEqual(Cleaner.clean("so basically it works"), "Basically it works")
        XCTAssertEqual(Cleaner.clean("okay so let's deploy"), "Let's deploy")
        XCTAssertEqual(Cleaner.clean("alright, run the tests"), "Run the tests")
    }

    func testStripsTrailingTags() {
        XCTAssertEqual(Cleaner.clean("we merge it tomorrow, right?"), "We merge it tomorrow?")
        XCTAssertEqual(Cleaner.clean("it needs a rebase, you know"), "It needs a rebase")
    }

    func testLeavesTechnicalDictationIntact() {
        let command = "git rebase -i origin slash dev"
        XCTAssertEqual(Cleaner.clean(command), "Git rebase -i origin slash dev")
        XCTAssertEqual(Cleaner.clean("run kubectl get pods -n staging"), "Run kubectl get pods -n staging")
    }

    func testNeverReturnsEmptyForNonEmptyInput() {
        XCTAssertEqual(Cleaner.clean("um"), "um")
        XCTAssertEqual(Cleaner.clean("uh, um, er"), "uh, um, er")
    }

    func testHandlesEmptyAndWhitespace() {
        XCTAssertEqual(Cleaner.clean(""), "")
        XCTAssertEqual(Cleaner.clean("   \n "), "")
    }

    func testNormalisesSpacingAroundPunctuation() {
        XCTAssertEqual(Cleaner.clean("the tests pass , and the lint is green"),
                       "The tests pass, and the lint is green")
    }

    func testRealDictationSample() {
        let spoken = "so I think that uh, what I want us to do is we build both"
        XCTAssertEqual(Cleaner.clean(spoken), "I think that what I want us to do is we build both")
    }
}
