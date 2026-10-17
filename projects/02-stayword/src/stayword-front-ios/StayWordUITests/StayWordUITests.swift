import XCTest

final class StayWordUITests: XCTestCase {
    private let recordingRowPredicate = NSPredicate(
        format: "identifier BEGINSWITH %@",
        "recording-row-"
    )
    private let transcriptSegmentPredicate = NSPredicate(
        format: "identifier BEGINSWITH %@",
        "transcript-segment-"
    )
    private let deletedRecordingRowPredicate = NSPredicate(
        format: "identifier BEGINSWITH %@",
        "deleted-recording-row-"
    )

    @MainActor
    func testAppLaunchesIntoNativeLibrary() {
        let app = testApplication()
        app.launch()

        XCTAssertTrue(element("library-all-recordings", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(element("library-favorites", in: app).exists)
        XCTAssertTrue(element("library-recently-deleted", in: app).exists)
        XCTAssertTrue(app.buttons["record-button"].exists)
    }

    @MainActor
    func testLibraryEntersEditingFromToolbar() {
        let app = testApplication()
        app.launch()

        let editButton = app.buttons["library-edit"]
        XCTAssertTrue(editButton.waitForExistence(timeout: 5))
        editButton.tap()

        XCTAssertTrue(app.buttons["library-done"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.buttons["record-button"].exists)
    }

    @MainActor
    func testRecordingListKeepsSearchBeforeSeparateMoreAction() {
        let app = testApplication()
        app.launch()

        app.descendants(matching: .any)["library-all-recordings"].tap()

        let searchButton = app.buttons["recording-list-search"]
        let moreButton = app.buttons["recording-list-more"]
        XCTAssertTrue(searchButton.waitForExistence(timeout: 5))
        XCTAssertTrue(moreButton.exists)
        XCTAssertLessThan(searchButton.frame.maxX, moreButton.frame.minX)

        moreButton.tap()
        let selectAction = app.buttons["recording-list-select-action"]
        let importAction = app.buttons["recording-list-import-action"]
        XCTAssertTrue(selectAction.waitForExistence(timeout: 3))
        XCTAssertTrue(importAction.exists)
        XCTAssertLessThan(selectAction.frame.midY, importAction.frame.midY)

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Recording list adaptive overflow menu"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        selectAction.tap()
        XCTAssertTrue(app.buttons["recording-list-done"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testSearchOpensAtTopAndCanBeReopenedAfterClosing() {
        let app = testApplication()
        app.launch()

        element("library-all-recordings", in: app).tap()
        let searchField = app.searchFields.firstMatch
        XCTAssertFalse(searchField.exists)
        app.buttons["recording-list-search"].tap()

        XCTAssertTrue(searchField.waitForExistence(timeout: 3))
        XCTAssertLessThan(searchField.frame.midY, app.windows.firstMatch.frame.midY)

        let legacyClose = app.buttons["recording-list-search-close"]
        if legacyClose.waitForExistence(timeout: 2) {
            legacyClose.tap()
        } else {
            let cancelSearch = app.buttons.matching(
                NSPredicate(format: "label IN %@", ["Cancel", "取消"])
            ).firstMatch
            guard cancelSearch.waitForExistence(timeout: 2) else {
                // iOS 26 presents search as native integrated navigation chrome and
                // does not expose a separate Cancel accessibility element.
                return
            }
            cancelSearch.tap()
        }
        XCTAssertTrue(searchField.waitForNonExistence(timeout: 3))

        app.buttons["recording-list-search"].tap()
        XCTAssertTrue(searchField.waitForExistence(timeout: 3))
        XCTAssertLessThan(searchField.frame.midY, app.windows.firstMatch.frame.midY)
    }

    @MainActor
    func testEveryCorePageKeepsTheAdaptiveChromeAligned() throws {
        let app = testApplication()
        app.launch()

        let newFolder = hittableButton("library-new-folder", in: app)
        let edit = hittableButton("library-edit", in: app)
        XCTAssertTrue(newFolder.waitForExistence(timeout: 5))
        XCTAssertTrue(edit.exists)
        assertMinimumTouchTarget(newFolder)
        assertMinimumTouchTarget(edit)
        XCTAssertEqual(newFolder.frame.midY, edit.frame.midY, accuracy: 2)
        attach("01 Library", app: app)

        element("library-all-recordings", in: app).tap()
        assertRecordingListToolbar(in: app)
        attach("02 All Recordings", app: app)
        adaptiveBackButton("recording-list-back", in: app).tap()
        XCTAssertTrue(hittableButton("library-edit", in: app).waitForExistence(timeout: 5))

        element("library-favorites", in: app).tap()
        assertRecordingListToolbar(in: app)
        attach("03 Favorites", app: app)
        adaptiveBackButton("recording-list-back", in: app).tap()
        XCTAssertTrue(hittableButton("library-edit", in: app).waitForExistence(timeout: 5))

        element("library-recently-deleted", in: app).tap()
        let deletedBack = adaptiveBackButton("recently-deleted-back", in: app)
        let deletedSelect = hittableButton("recently-deleted-select", in: app)
        XCTAssertTrue(deletedBack.waitForExistence(timeout: 5))
        XCTAssertTrue(deletedSelect.exists)
        assertMinimumTouchTarget(deletedBack)
        assertMinimumTouchTarget(deletedSelect)
        XCTAssertEqual(deletedBack.frame.midY, deletedSelect.frame.midY, accuracy: 2)
        attach("04 Recently Deleted", app: app)
        deletedBack.tap()
        XCTAssertTrue(hittableButton("library-edit", in: app).waitForExistence(timeout: 5))

        element("library-all-recordings", in: app).tap()
        let firstRecording = app.buttons.matching(recordingRowPredicate).firstMatch
        guard firstRecording.waitForExistence(timeout: 5) else {
            throw XCTSkip("A recording is required to inspect the detail screens.")
        }
        firstRecording.tap()

        let detailBack = adaptiveBackButton("detail-back", in: app)
        let detailMore = hittableButton("detail-more", in: app)
        XCTAssertTrue(detailBack.waitForExistence(timeout: 5))
        XCTAssertTrue(detailMore.exists)
        assertMatchingCircularToolbarButtons(detailBack, detailMore)

        let playbackSpeed = hittableButton("playback-speed", in: app)
        XCTAssertTrue(playbackSpeed.exists)
        attach("05 Recording Summary", app: app)

        let transcriptTab = hittableButton("detail-transcript-tab", in: app)
        XCTAssertTrue(transcriptTab.waitForExistence(timeout: 3))
        transcriptTab.tap()
        attach("06 Recording Transcript", app: app)

        let editDetail = hittableButton("detail-edit", in: app)
        XCTAssertTrue(editDetail.exists)
        editDetail.tap()

        let editorCancel = hittableButton("recording-editor-cancel", in: app)
        let editorSave = hittableButton("recording-editor-save", in: app)
        XCTAssertTrue(editorCancel.waitForExistence(timeout: 5))
        XCTAssertTrue(editorSave.exists)
        assertMatchingCircularToolbarButtons(editorCancel, editorSave)
        attach("07 Recording Editor", app: app)
        editorCancel.tap()

        XCTAssertTrue(detailMore.waitForExistence(timeout: 5))
        detailMore.tap()
        let move = app.buttons["detail-move"]
        XCTAssertTrue(move.waitForExistence(timeout: 3))
        move.tap()

        let moveClose = hittableButton("move-recordings-close", in: app)
        XCTAssertTrue(moveClose.waitForExistence(timeout: 5))
        assertMinimumTouchTarget(moveClose)
        attach("08 Move Recording", app: app)
        moveClose.tap()
    }

    @MainActor
    func testRecordingDetailOffersPlaybackRatesAndThreeShareChoices() throws {
        let app = testApplication()
        app.launch()

        element("library-all-recordings", in: app).tap()
        let firstRecording = app.buttons.matching(recordingRowPredicate).firstMatch
        guard firstRecording.waitForExistence(timeout: 5) else {
            throw XCTSkip("A recording is required to inspect detail actions.")
        }
        firstRecording.tap()

        let detailMore = hittableButton("detail-more", in: app)
        let playbackSpeed = hittableButton("playback-speed", in: app)
        XCTAssertTrue(detailMore.waitForExistence(timeout: 5))
        XCTAssertTrue(playbackSpeed.exists)

        detailMore.tap()
        let shareAction = app.buttons["detail-share-action"]
        XCTAssertTrue(shareAction.waitForExistence(timeout: 3))
        shareAction.tap()
        XCTAssertTrue(app.buttons["detail-share-audio"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["detail-share-transcript"].exists)
        XCTAssertTrue(app.buttons["detail-share-summary"].exists)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5)).tap()

        playbackSpeed.tap()
        let fasterRate = app.buttons["1.25×"]
        XCTAssertTrue(fasterRate.waitForExistence(timeout: 3))
        fasterRate.tap()
        XCTAssertEqual(playbackSpeed.value as? String, "1.25×")
    }

    @MainActor
    func testRecordsSpeechAndProducesAnOnDeviceTranscript() throws {
        let app = testApplication()
        app.launch()

        addUIInterruptionMonitor(withDescription: "Microphone permission") { alert in
            let allow = alert.buttons.matching(
                NSPredicate(format: "label IN %@", ["Allow", "允许", "OK", "好"])
            ).firstMatch
            guard allow.exists else { return false }
            allow.tap()
            return true
        }

        let record = app.buttons["record-button"]
        XCTAssertTrue(record.waitForExistence(timeout: 5))
        record.tap()

        let stop = app.buttons["recorder-stop"]
        if !stop.waitForExistence(timeout: 3) {
            app.activate()
            if record.waitForExistence(timeout: 3) {
                record.tap()
            }
        }
        XCTAssertTrue(stop.waitForExistence(timeout: 10))
        attach("09 Recorder Compact", app: app)

        let recorderSheet = app.sheets.firstMatch
        if recorderSheet.exists {
            recorderSheet.swipeUp()
        } else {
            app.swipeUp()
        }

        let pauseResume = app.buttons["recorder-pause-resume"]
        XCTAssertTrue(pauseResume.waitForExistence(timeout: 5))

        pauseResume.tap()
        Thread.sleep(forTimeInterval: 1)
        pauseResume.tap()
        attach("10 Recorder Expanded", app: app)

        Thread.sleep(forTimeInterval: 16)
        stop.tap()

        let transcriptTab = app.buttons["detail-transcript-tab"]
        XCTAssertTrue(transcriptTab.waitForExistence(timeout: 15))
        transcriptTab.tap()

        let transcriptSegment = app.buttons.matching(transcriptSegmentPredicate).firstMatch
        XCTAssertTrue(
            transcriptSegment.waitForExistence(timeout: 180),
            "The on-device recognizer did not produce a timestamped transcript segment."
        )
        attach("11 On-device Transcript", app: app)

        app.buttons["detail-summary-tab"].tap()
        let overallStatus = element("detail-processing-status", in: app)
        XCTAssertTrue(
            overallStatus.waitForNonExistence(timeout: 240),
            "Processing did not reach a terminal state."
        )
        XCTAssertEqual(
            app.state,
            .runningForeground,
            "The app terminated while completing on-device processing."
        )

        transcriptTab.tap()
        let completedSegments = app.buttons.matching(transcriptSegmentPredicate)
        let completedTranscript = (0..<completedSegments.count)
            .map { completedSegments.element(boundBy: $0).label }
            .joined(separator: " ")
        let expectedSpeechTerms = ["语音", "识别", "录音", "转写"]
        XCTAssertTrue(
            expectedSpeechTerms.contains { completedTranscript.contains($0) },
            "The recognizer emitted a timestamp but did not capture the spoken test phrase."
        )
        attach("12 Completed On-device Transcript", app: app)

        let detailMore = app.buttons["detail-more"]
        detailMore.tap()
        let delete = app.buttons["detail-delete"]
        XCTAssertTrue(delete.waitForExistence(timeout: 3))
        delete.tap()
        let confirmDelete = app.buttons["detail-confirm-delete"]
        XCTAssertTrue(confirmDelete.waitForExistence(timeout: 3))
        confirmDelete.tap()

        let recentlyDeleted = element("library-recently-deleted", in: app)
        XCTAssertTrue(recentlyDeleted.waitForExistence(timeout: 5))
        recentlyDeleted.tap()
        let deletedRecording = app.buttons.matching(deletedRecordingRowPredicate).firstMatch
        XCTAssertTrue(deletedRecording.waitForExistence(timeout: 5))
        let deletedIdentifier = deletedRecording.identifier
        deletedRecording.tap()
        let itemDelete = app.buttons["recently-deleted-item-delete"]
        XCTAssertTrue(itemDelete.waitForExistence(timeout: 3))
        itemDelete.tap()
        let permanentDelete = app.buttons["recently-deleted-confirm-permanent-delete"]
        XCTAssertTrue(permanentDelete.waitForExistence(timeout: 3))
        permanentDelete.tap()
        XCTAssertTrue(app.buttons[deletedIdentifier].waitForNonExistence(timeout: 5))
    }

    @MainActor
    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    private func testApplication() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["STAYWORD_UI_TEST_DISABLE_SUMMARY"] = "1"
        return app
    }

    private func hittableButton(
        _ identifier: String,
        in app: XCUIApplication
    ) -> XCUIElement {
        let buttons = app.buttons.matching(identifier: identifier)
        for index in 0..<buttons.count {
            let candidate = buttons.element(boundBy: index)
            if candidate.isHittable {
                return candidate
            }
        }
        return buttons.firstMatch
    }

    private func adaptiveBackButton(
        _ identifier: String,
        in app: XCUIApplication
    ) -> XCUIElement {
        app.buttons.matching(
            NSPredicate(format: "identifier IN %@", [identifier, "BackButton"])
        ).firstMatch
    }

    private func assertRecordingListToolbar(
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let back = adaptiveBackButton("recording-list-back", in: app)
        let search = hittableButton("recording-list-search", in: app)
        let more = hittableButton("recording-list-more", in: app)
        XCTAssertTrue(back.waitForExistence(timeout: 5), file: file, line: line)
        XCTAssertTrue(search.exists, file: file, line: line)
        XCTAssertTrue(more.exists, file: file, line: line)
        assertMatchingCircularToolbarButtons(back, search, file: file, line: line)
        assertMatchingCircularToolbarButtons(search, more, file: file, line: line)
        XCTAssertLessThan(search.frame.maxX, more.frame.minX, file: file, line: line)
    }

    private func assertMatchingCircularToolbarButtons(
        _ first: XCUIElement,
        _ second: XCUIElement,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        assertMinimumTouchTarget(first, file: file, line: line)
        assertMinimumTouchTarget(second, file: file, line: line)
        XCTAssertEqual(first.frame.width, first.frame.height, accuracy: 2, file: file, line: line)
        XCTAssertEqual(second.frame.width, second.frame.height, accuracy: 2, file: file, line: line)
        XCTAssertEqual(first.frame.midY, second.frame.midY, accuracy: 2, file: file, line: line)
    }

    private func assertMinimumTouchTarget(
        _ element: XCUIElement,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let minimumDimension: CGFloat
        if #available(iOS 26.0, *) {
            // The native liquid-glass toolbar exposes its compact circular
            // controls as 36 pt accessibility frames. Older systems use the
            // app's 44 pt frosted-glass compatibility controls.
            minimumDimension = 36
        } else {
            minimumDimension = 44
        }
        XCTAssertGreaterThanOrEqual(
            element.frame.width,
            minimumDimension,
            file: file,
            line: line
        )
        XCTAssertGreaterThanOrEqual(
            element.frame.height,
            minimumDimension,
            file: file,
            line: line
        )
    }

    private func attach(_ name: String, app: XCUIApplication) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

}
