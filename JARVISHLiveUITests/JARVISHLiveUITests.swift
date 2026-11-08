import XCTest

final class JARVISHLiveUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testLaunchAndDiagnosticsTabs() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.staticTexts["diagnosticBoundary"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["refreshInterfaces"].exists)
        app.buttons["refreshInterfaces"].tap()
        XCTAssertTrue(app.staticTexts["wifiStatus"].exists)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "network-diagnostics"
        shot.lifetime = .keepAlways
        add(shot)
        app.tabBars.buttons["服務探索"].tap()
        XCTAssertTrue(app.buttons["startDiscovery"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["discoveryStatus"].exists)
        // Deliberately do not claim the simulator can test helmet discovery.
        app.tabBars.buttons["錯誤日誌"].tap()
        XCTAssertTrue(app.buttons["exportLog"].waitForExistence(timeout: 5))
        app.buttons["clearLog"].tap()
        XCTAssertTrue(app.staticTexts["emptyLog"].waitForExistence(timeout: 5))
    }
}
