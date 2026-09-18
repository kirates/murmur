import AppKit
import XCTest
@testable import Murmur

final class InserterTests: XCTestCase {
    private var pasteboard: NSPasteboard!

    override func setUp() {
        super.setUp()
        pasteboard = NSPasteboard(name: NSPasteboard.Name("com.kirates.murmur.tests"))
        pasteboard.clearContents()
    }

    override func tearDown() {
        pasteboard.releaseGlobally()
        pasteboard = nil
        super.tearDown()
    }

    func testRestoreBringsBackPlainText() {
        pasteboard.clearContents()
        pasteboard.setString("original clipboard", forType: .string)

        let saved = Inserter.snapshot(of: pasteboard)

        pasteboard.clearContents()
        pasteboard.setString("dictated text", forType: .string)
        XCTAssertEqual(pasteboard.string(forType: .string), "dictated text")

        Inserter.restore(saved, to: pasteboard)
        XCTAssertEqual(pasteboard.string(forType: .string), "original clipboard")
    }

    func testRestorePreservesMultipleTypesOnOneItem() {
        let item = NSPasteboardItem()
        item.setData(Data("plain".utf8), forType: .string)
        item.setData(Data("<b>rich</b>".utf8), forType: .html)
        pasteboard.clearContents()
        pasteboard.writeObjects([item])

        let saved = Inserter.snapshot(of: pasteboard)
        pasteboard.clearContents()
        pasteboard.setString("dictated text", forType: .string)

        Inserter.restore(saved, to: pasteboard)
        XCTAssertEqual(pasteboard.string(forType: .string), "plain")
        XCTAssertEqual(pasteboard.data(forType: .html).map { String(decoding: $0, as: UTF8.self) }, "<b>rich</b>")
    }

    func testRestoringAnEmptySnapshotLeavesPasteboardEmpty() {
        pasteboard.clearContents()
        let saved = Inserter.snapshot(of: pasteboard)

        pasteboard.clearContents()
        pasteboard.setString("dictated text", forType: .string)

        Inserter.restore(saved, to: pasteboard)
        XCTAssertNil(pasteboard.string(forType: .string))
    }
}
