import XCTest

/// UI tests. Launch arguments:
///  -uiTesting  → temporary storage + fresh defaults (never touches the real library), offline
///  -demoCamera → connects the in-memory demo camera on launch
/// Environment: FILMLAB_WEB_RECIPES_JSON → the recipe catalogue, in the website's
/// `GET /api/recipes` shape (the app ships no recipes; UI tests never hit the network).
@MainActor
final class FilmLabUITests: XCTestCase {
    override func setUp() async throws { continueAfterFailure = false }

    static let webRecipes = #"""
    {"recipes":[
      {"id":"A1000000-0000-4000-8000-000000000001","slug":"harbour-morning","name":"Harbour Morning",
       "summary":"Soft, cool daylight with gentle shadows.","xTransGeneration":"IV","publishedAt":"2026-11-01T09:00:00.000Z",
       "settings":{"filmSimulation":"classicChrome","highlight":{"state":"value","value":-1},"shadow":{"state":"value","value":-1}}},
      {"id":"A1000000-0000-4000-8000-000000000002","slug":"paper-moon","name":"Paper Moon",
       "summary":"Crunchy black-and-white.","xTransGeneration":"IV","publishedAt":"2026-11-01T08:00:00.000Z",
       "settings":{"filmSimulation":"acrosR","shadow":{"state":"value","value":2}}}
    ]}
    """#

    private func launch(_ extra: [String] = [], webRecipes: String? = FilmLabUITests.webRecipes) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"] + extra
        if let webRecipes { app.launchEnvironment["FILMLAB_WEB_RECIPES_JSON"] = webRecipes }
        app.launch()
        return app
    }

    /// The catalogue comes from the FilmLab website; with nothing cached and no network, Explore
    /// explains that and offers Retry instead of showing an empty page.
    func testExploreShowsWebCatalogueOrOfflineState() throws {
        let app = launch()
        app.tabBars.buttons["Explore"].tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Harbour Morning")).firstMatch
            .waitForExistence(timeout: 10))
        app.terminate()

        let offline = launch(webRecipes: nil)
        offline.tabBars.buttons["Explore"].tap()
        XCTAssertTrue(offline.buttons["retryWebRecipes"].waitForExistence(timeout: 10))
        XCTAssertFalse(offline.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Harbour Morning")).firstMatch.exists)
    }

    /// True when the element is laid out inside the window (lazy stacks report off-screen frames).
    private func isOnScreen(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
        element.exists && app.windows.firstMatch.frame.contains(element.frame)
    }

    /// Acceptance: with no camera, a photo previews, simulations change it, the badge says
    /// Approximate, and a recipe can be saved and found in Library.
    func testStudioIsFullyUsefulWithoutACamera() throws {
        let app = launch()
        app.tabBars.buttons["Studio"].tap()
        let canvas = app.descendants(matching: .any)["previewCanvas"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 10))
        let badge = app.descendants(matching: .any)["fidelityBadge"]
        XCTAssertTrue(badge.waitForExistence(timeout: 5))
        XCTAssertTrue(badge.label.contains("Approximate"), "Offline previews must be labelled approximate: \(badge.label)")

        app.buttons["sim-velvia"].tap()
        // ACROS sits further along the horizontal simulation strip.
        let acros = app.buttons["sim-acros"]
        let strip = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "sim-"))
        for _ in 0..<8 where !isOnScreen(acros, in: app) {
            // Swipe on whichever simulation is visible (the strip may have scrolled after the tap).
            guard let visible = strip.allElementsBoundByIndex.first(where: { isOnScreen($0, in: app) }) else { break }
            // Drag (no fling) by exactly the distance that centres ACROS, so it can't overshoot.
            let window = app.windows.firstMatch.frame
            let dx = max(-window.width * 0.8, min(window.width * 0.8, window.midX - acros.frame.midX))
            let start = visible.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: dx, dy: 0)),
                        withVelocity: .slow, thenHoldForDuration: 0.2)
        }
        acros.tap()
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

        app.tabBars.buttons["Library"].tap()
        XCTAssertTrue(app.staticTexts["UITest Acros"].waitForExistence(timeout: 5))
    }

    /// Acceptance: choosing a slot leads to a review screen; nothing is written until the user
    /// acknowledges and taps the explicit write button.
    func testSendToCameraNeverWritesWithoutConfirmation() throws {
        let app = launch(["-demoCamera"])
        app.tabBars.buttons["Explore"].tap()
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

        // Tap the switch control itself; the row's centre is its label.
        let acknowledge = app.switches["acknowledgeOverwrite"]
        (acknowledge.switches.firstMatch.exists ? acknowledge.switches.firstMatch : acknowledge).tap()
        XCTAssertTrue(confirm.isEnabled)
        // Deliberately cancel: the test proves the flow is gated, without writing.
        app.buttons["Cancel"].tap()
    }

    func testCameraTabShowsDemoClearly() throws {
        let app = launch(["-demoCamera"])
        app.tabBars.buttons["Camera"].tap()
        let status = app.descendants(matching: .any)["cameraStatus"]
        XCTAssertTrue(status.waitForExistence(timeout: 10))
        XCTAssertTrue(status.label.contains("Demo"), status.label)
        let readAll = app.buttons["readAllSlots"]
        for _ in 0..<6 where !isOnScreen(readAll, in: app) { app.swipeUp() }
        readAll.tap()
        // The slot rows sit above the actions; scroll back up to them.
        let c1 = app.buttons["slot-C1"]
        for _ in 0..<6 where !isOnScreen(c1, in: app) { app.swipeDown() }
        XCTAssertTrue(c1.waitForExistence(timeout: 10))
        let predicate = NSPredicate(format: "label CONTAINS %@", "DEMO CHROME")
        expectation(for: predicate, evaluatedWith: c1)
        waitForExpectations(timeout: 10)
    }

    /// Wi‑Fi import against the emulated camera (real sockets on 127.0.0.1): connect, wait for
    /// the simulated OK on the camera, browse, import everything new. UI tests don't touch Photos.
    func testWiFiImportWithDemoCamera() throws {
        let app = launch()
        app.tabBars.buttons["Camera"].tap()
        let entry = app.buttons["importPhotos"]
        XCTAssertTrue(entry.waitForExistence(timeout: 10))
        entry.tap()
        let demo = app.buttons["wifiDemo"]
        for _ in 0..<4 where !isOnScreen(demo, in: app) { app.swipeUp() }
        demo.tap()
        let importNew = app.buttons["wifiImportNew"]
        XCTAssertTrue(importNew.waitForExistence(timeout: 20), "Browser should appear after the handshake")
        XCTAssertTrue(app.descendants(matching: .any)["wifiGrid"].exists)
        importNew.tap()
        let done = app.buttons["wifiImported"]
        XCTAssertTrue(done.waitForExistence(timeout: 60))
        let all = NSPredicate(format: "label CONTAINS %@", "12 imported")
        expectation(for: all, evaluatedWith: done)
        waitForExpectations(timeout: 60)
        // Nothing left to import: the ledger marks every photo.
        XCTAssertFalse(importNew.isEnabled)
    }
}
