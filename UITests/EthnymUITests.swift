import XCTest

/// Drives the app in a simulator. Launch arguments `-demo` and `-empty` swap in an in-memory model,
/// so nothing touches the Keychain or real files.
final class EthnymUITests: XCTestCase {
    static let phrase = "test test test test test test test test test test test junk"
    static let password = "correct horse battery staple"

    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments
        app.launch()
        return app
    }

    /// Forms build rows lazily, so swipe until the element exists and can be tapped.
    @MainActor
    @discardableResult
    private func reveal(_ element: XCUIElement, in app: XCUIApplication, maxSwipes: Int = 6) -> XCUIElement {
        var swipes = 0
        while !(element.exists && element.isHittable) && swipes < maxSwipes {
            app.swipeUp(velocity: .slow)
            swipes += 1
        }
        return element
    }

    @MainActor
    private func snapshot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testScreens() {
        let app = launch(["-demo"])
        XCTAssertTrue(app.staticTexts["Wallets"].waitForExistence(timeout: 5))
        sleep(4)
        snapshot(app, "01-home")

        app.buttons["Send"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 3))
        sleep(2)
        snapshot(app, "02-send-eth")
        app.buttons["Token"].tap()
        sleep(2)
        snapshot(app, "03-send-token")
        app.buttons["NFT"].tap()
        sleep(1)
        snapshot(app, "04-send-nft")
        app.buttons["Sign"].tap()
        sleep(1)
        snapshot(app, "05-send-sign")
        app.buttons["Close"].tap()

        app.buttons["Receive"].firstMatch.tap()
        sleep(1)
        snapshot(app, "06-receive")
        app.buttons["Done"].tap()

        reveal(app.buttons["NFTs"], in: app).tap()
        sleep(2)
        snapshot(app, "07-nfts")

        for (tab, name) in [("Address Book", "08-address-book"), ("Activity", "09-activity"), ("Backup", "10-backup"), ("Settings", "11-settings")] {
            app.tabBars.buttons[tab].tap()
            sleep(1)
            snapshot(app, name)
        }
    }

    @MainActor
    func testCreateWallet() {
        let app = launch(["-empty"])
        app.buttons["Create Wallet"].firstMatch.tap()

        let name = app.textFields["Wallet name"]
        XCTAssertTrue(name.waitForExistence(timeout: 3))
        name.tap()
        name.typeText("Spending")
        app.secureTextFields["Strong password"].tap()
        app.secureTextFields["Strong password"].typeText("hunter22")
        app.secureTextFields["Confirm password"].tap()
        app.secureTextFields["Confirm password"].typeText("hunter2")
        XCTAssertTrue(app.staticTexts["Passwords don't match"].waitForExistence(timeout: 2))
        app.secureTextFields["Confirm password"].typeText("2")
        snapshot(app, "20-create-wallet")

        app.buttons["Create Wallet"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Spending"].waitForExistence(timeout: 10))
        snapshot(app, "21-created")
    }

    @MainActor
    func testImportPhraseAndSignOffline() {
        // Offline from launch: this test must never be able to broadcast.
        let app = launch(["-empty", "-offline"])
        app.buttons["Import Wallet"].firstMatch.tap()

        let name = app.textFields["Wallet name"]
        XCTAssertTrue(name.waitForExistence(timeout: 3))
        name.tap()
        name.typeText("Imported")
        app.secureTextFields["Strong password"].tap()
        app.secureTextFields["Strong password"].typeText(Self.password)
        let phrase = app.textFields["Enter your secret phrase"]
        phrase.tap()
        phrase.typeText(Self.phrase)
        snapshot(app, "30-import")
        app.buttons["Import Wallet"].firstMatch.tap()

        XCTAssertTrue(app.staticTexts["Imported"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] %@", "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266")).firstMatch.waitForExistence(timeout: 2))

        // Sign transaction JSON without broadcasting.
        app.buttons["Send"].firstMatch.tap()
        app.buttons["Sign"].tap()

        let json = app.textFields.firstMatch
        json.tap()
        json.typeText(#"{"to":"0x70997970C51812dc3A010C7d01b50e0d17dc79C8","chainId":1,"value":"0x2bb2c8eabcc000","nonce":7,"gas":"0x5208","maxFeePerGas":"0x7558bdb00","maxPriorityFeePerGas":"0x4a817c80"}"#)
        let password = reveal(app.secureTextFields["Wallet password"], in: app)
        password.tap()
        password.typeText(Self.password)
        let submit = reveal(app.buttons["submit"], in: app)
        XCTAssertEqual(submit.label, "Sign", "Offline mode must be on, or this would broadcast")
        submit.tap()

        // Same transaction as the viem fixture, so the signature is known.
        let raw = app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH %@", "0x02f8720107844a817c808507558bdb00")).firstMatch
        XCTAssertTrue(raw.waitForExistence(timeout: 10) || reveal(raw, in: app).exists)
        snapshot(app, "31-signed-offline")
    }
}
