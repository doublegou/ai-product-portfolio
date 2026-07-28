import XCTest

final class StayWordUITests: XCTestCase {
    @MainActor
    func testAppLaunchesIntoNativeLibrary() {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.navigationBars["Voice Recordings"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["All Recordings"].exists)
        XCTAssertTrue(app.staticTexts["Favorites"].exists)
    }

    @MainActor
    func testLibraryEntersEditingFromToolbar() {
        let app = XCUIApplication()
        app.launch()

        let editButton = app.buttons["Edit"]
        XCTAssertTrue(editButton.waitForExistence(timeout: 5))
        editButton.tap()

        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.buttons["Record"].exists)
    }

    @MainActor
    func testRecordingListKeepsSearchBeforeSeparateMoreAction() {
        let app = XCUIApplication()
        app.launch()

        app.staticTexts["All Recordings"].tap()

        let searchButton = app.buttons["Search"]
        let moreButton = app.buttons["More"]
        XCTAssertTrue(searchButton.waitForExistence(timeout: 5))
        XCTAssertTrue(moreButton.exists)
        XCTAssertLessThan(searchButton.frame.maxX, moreButton.frame.minX)
    }

    @MainActor
    func testSearchOpensAtTopAndCanBeReopenedAfterClosing() {
        let app = XCUIApplication()
        app.launch()

        app.staticTexts["All Recordings"].tap()
        XCTAssertFalse(app.searchFields["Title or transcript"].exists)
        app.buttons["Search"].tap()

        let searchField = app.searchFields["Title or transcript"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 3))
        XCTAssertLessThan(searchField.frame.midY, app.windows.firstMatch.frame.midY)

        app.buttons["Close"].tap()
        XCTAssertTrue(searchField.waitForNonExistence(timeout: 3))

        app.buttons["Search"].tap()
        XCTAssertTrue(searchField.waitForExistence(timeout: 3))
        XCTAssertLessThan(searchField.frame.midY, app.windows.firstMatch.frame.midY)
    }

}
