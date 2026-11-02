import XCTest

/// UI tests. Launch arguments:
///  -uiTesting  → temporary storage + fresh defaults (never touches the real library)
///  -demoCamera → connects the in-memory demo camera on launch
final class FilmLabUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"] + extra
        app.launch()
        return app
    }

    /// Acceptance: with no camera, a photo previews, simulations change it, the badge says
    /// Approximate, and a recipe can be saved and found in Library.
    func testStudioIsFullyUsefulWithoutACamera() throws {
        let app = launch()
        app.buttons["tab-studio"].tap()
        let canvas = app.descendants(matching: .any)["previewCanvas"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 10))
        let badge = app.descendants(matching: .any)["fidelityBadge"]
        XCTAssertTrue(badge.waitForExistence(timeout: 5))
        XCTAssertTrue(badge.label.contains("Approximate"), "Offline previews must be labelled approximate: \(badge.label)")

        app.buttons["sim-velvia"].tap()
        app.buttons["sim-acros"].tap()
        XCTAssertFalse(badge.label.contains("Authentic"))

        // Render with Camera is disabled with no camera.
        XCTAssertFalse(app.buttons["renderWithCamera"].isEnabled)

        app.descendants(matching: .any)["recipeMenu"].tap()
        app.buttons["Save as New Recipe…"].tap()
        let name = app.textFields["recipeNameField"]
        XCTAssertTrue(name.waitForExistence(timeout: 3))
        name.tap()
        name.press(forDuration: 1.0)
        if app.menuItems["Select All"].waitForExistence(timeout: 1) { app.menuItems["Select All"].tap() }
        name.typeText("UITest Acros")
        app.buttons["saveRecipeConfirm"].tap()

        app.buttons["tab-library"].tap()
        XCTAssertTrue(app.staticTexts["UITest Acros"].waitForExistence(timeout: 5))
    }

    /// Acceptance: choosing a slot leads to a review screen; nothing is written until the user
    /// acknowledges and taps the explicit write button.
    func testSendToCameraNeverWritesWithoutConfirmation() throws {
        let app = launch(["-demoCamera"])
        app.buttons["tab-explore"].tap()
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Harbour Morning")).firstMatch.tap()
        app.buttons["saveToLibrary"].tap()
        app.buttons["Send to Camera…"].tap()

        let review = app.buttons["reviewChanges"]
        XCTAssertTrue(review.waitForExistence(timeout: 10))
        review.tap()

        let confirm = app.buttons["confirmWrite"]
        // The confirm button sits below the diff rows; scroll until the lazy form creates it.
        for _ in 0..<8 where !confirm.exists { app.swipeUp() }
        XCTAssertTrue(confirm.waitForExistence(timeout: 10))
        XCTAssertFalse(confirm.isEnabled, "Write must require explicit acknowledgement")
        XCTAssertFalse(app.descendants(matching: .any)["writeResult"].exists)

        app.switches["acknowledgeOverwrite"].tap()
        XCTAssertTrue(confirm.isEnabled)
        // Deliberately cancel: the test proves the flow is gated, without writing.
        app.buttons["Cancel"].tap()
    }

    func testCameraTabShowsDemoClearly() throws {
        let app = launch(["-demoCamera"])
        app.buttons["tab-camera"].tap()
        let status = app.descendants(matching: .any)["cameraStatus"]
        XCTAssertTrue(status.waitForExistence(timeout: 10))
        XCTAssertTrue(status.label.contains("Demo"), status.label)
        app.buttons["readAllSlots"].tap()
        let c1 = app.buttons["slot-C1"]
        XCTAssertTrue(c1.waitForExistence(timeout: 10))
        let predicate = NSPredicate(format: "label CONTAINS %@", "DEMO CHROME")
        expectation(for: predicate, evaluatedWith: c1)
        waitForExpectations(timeout: 10)
    }
}
