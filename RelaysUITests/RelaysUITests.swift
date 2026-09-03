//
//  RelaysUITests.swift
//  RelaysUITests
//
//  What no unit test can reach: the app actually starting, and the screens a
//  person meets before they have an account. Everything past the sign-in needs
//  a real account, so these stop at the gate — which is exactly the part that
//  nothing else covers.
//

import XCTest

final class RelaysUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Starts the app in a known state: fixed theme, fixed language, fixed text
    /// size, and nothing switched on that would reach for the network.
    @MainActor
    private func launch(theme: String = "dark", textSize: String = "medium") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-relaysUITesting",
                               "-relaysTheme", theme,
                               "-relaysTextSize", textSize]
        app.launch()
        return app
    }

    // MARK: - The gate

    @MainActor
    func testSignInScreenAppears() throws {
        let app = launch()

        XCTAssertTrue(app.staticTexts["Relays"].waitForExistence(timeout: 10),
                      "the wordmark never appeared")
        XCTAssertTrue(app.textFields["Handle or DID"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.secureTextFields["App password"].exists)
    }

    /// Connect stays shut until there is something to send. A button that looks
    /// pressable and does nothing is worse than one that is plainly not ready.
    @MainActor
    func testConnectStaysDisabledUntilBothFieldsAreFilled() throws {
        let app = launch()
        let connect = app.buttons["Connect"]

        XCTAssertTrue(connect.waitForExistence(timeout: 10))
        XCTAssertFalse(connect.isEnabled)

        app.textFields["Handle or DID"].tap()
        app.typeText("someone.bsky.social")
        XCTAssertFalse(connect.isEnabled, "a handle alone is not enough")

        app.secureTextFields["App password"].tap()
        app.typeText("abcd-efgh-ijkl-mnop")
        XCTAssertTrue(connect.isEnabled)
    }

    // MARK: - Making an account

    /// The sign-in screen at the largest setting: everything still on screen and
    /// still reachable. This is the screen that has to survive it — a reader who
    /// cannot get past it never sees the rest.
    @MainActor
    func testSignInSurvivesTheLargestTextSize() throws {
        let app = launch(textSize: "large")

        XCTAssertTrue(app.staticTexts["Relays"].waitForExistence(timeout: 10))
        for element in [app.textFields["Handle or DID"],
                        app.secureTextFields["App password"],
                        app.buttons["Connect"]] {
            XCTAssertTrue(element.exists, "\(element) fell off the screen")
            XCTAssertTrue(element.isHittable, "\(element) is on screen but cannot be reached")
        }
    }

    // MARK: - Every ground

    @MainActor
    func testEveryThemeReachesTheSignInScreen() throws {
        for theme in ["light", "dim", "dark", "blue"] {
            let app = launch(theme: theme)
            XCTAssertTrue(app.staticTexts["Relays"].waitForExistence(timeout: 10),
                          "the \(theme) ground never got to the sign-in screen")
            app.terminate()
        }
    }
}
