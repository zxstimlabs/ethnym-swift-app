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

    /// Next to a username field, Password AutoFill offers a strong password in a sheet that replaces
    /// the keyboard. Close it and type our own.
    @MainActor
    private func typeNewPassword(_ text: String, into field: XCUIElement, in app: XCUIApplication) {
        field.tap()
        if app.buttons["GenerateStrongPasswordButton"].waitForExistence(timeout: 2) {
            app.buttons["xmark"].tap()
        }
        field.typeText(text)
    }

    /// Once that form closes, AutoFill offers to save or update the password. Decline.
    @MainActor
    private func declineSavingPassword(in app: XCUIApplication) {
        let notNow = app.buttons["Not Now"]
        if notNow.waitForExistence(timeout: 3) { notNow.tap() }
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

        // Section info opens in a sheet that X and OK both close.
        for close in ["Close", "OK"] {
            app.buttons["About Wallets"].tap()
            XCTAssertTrue(app.buttons[close].waitForExistence(timeout: 2))
            if close == "Close" { snapshot(app, "01-home-info") }
            app.buttons[close].tap()
            XCTAssertTrue(app.buttons[close].waitForNonExistence(timeout: 2))
        }

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
        app.tabBars.buttons["Home"].tap()

        app.buttons["Receive"].firstMatch.tap()
        sleep(1)
        snapshot(app, "06-receive")
        app.buttons["Close"].tap()

        app.buttons["Manage"].tap()
        XCTAssertTrue(app.buttons["Create Wallet"].waitForExistence(timeout: 2))
        snapshot(app, "06-manage")
        // Choosing an action opens that screen full screen over the pop-up. Back returns to the
        // pop-up; X closes both.
        app.buttons["Create Wallet"].tap()
        XCTAssertTrue(app.textFields["Wallet name"].waitForExistence(timeout: 3))
        snapshot(app, "06-manage-create")
        app.navigationBars.buttons["Back"].tap()
        XCTAssertTrue(app.buttons["Import Wallet"].waitForExistence(timeout: 3))
        app.buttons["Import Wallet"].tap()
        XCTAssertTrue(app.textFields["Wallet name"].waitForExistence(timeout: 3))
        app.navigationBars.buttons["Close"].tap()
        XCTAssertTrue(app.buttons["Import Wallet"].waitForNonExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Manage"].isHittable)

        reveal(app.buttons["NFTs"], in: app).tap()
        sleep(2)
        snapshot(app, "07-nfts")

        for (tab, name) in [("Address Book", "08-address-book"), ("Activity", "09-activity"), ("Backup", "10-backup")] {
            app.tabBars.buttons[tab].tap()
            sleep(1)
            snapshot(app, name)
            if tab == "Address Book" {
                let search = app.textFields["Search address book"]
                search.tap()
                search.typeText("bob")
                XCTAssertTrue(app.staticTexts["Alice"].waitForNonExistence(timeout: 2))
                XCTAssertTrue(app.staticTexts["Bob"].exists)
                app.buttons["Clear search"].tap()
                XCTAssertTrue(app.staticTexts["Alice"].waitForExistence(timeout: 2))
                // The keyboard's Search key closes it, uncovering the tab bar.
                search.typeText("\n")
                app.buttons["Edit"].tap()
                sleep(1)
                snapshot(app, "08-address-book-editing")
                app.buttons["Done"].tap()
            }
        }

        // Log Out lives in Settings, the header's only button.
        app.navigationBars.buttons["Settings"].tap()
        sleep(1)
        snapshot(app, "11-settings")
        app.swipeUp()
        sleep(1)
        snapshot(app, "11-settings-more")
        app.swipeDown()
        app.buttons["Log Out"].tap()
        app.tabBars.buttons["Home"].tap()
        XCTAssertTrue(app.buttons["Wallet: none selected"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testCreateWallet() {
        let app = launch(["-empty"])
        app.buttons["Create"].firstMatch.tap()

        let name = app.textFields["Wallet name"]
        XCTAssertTrue(name.waitForExistence(timeout: 3))
        name.tap()
        name.typeText("Spending")
        typeNewPassword("hunter22", into: app.secureTextFields["Strong password"], in: app)
        typeNewPassword("hunter2", into: app.secureTextFields["Confirm password"], in: app)
        XCTAssertTrue(app.staticTexts["Passwords don't match"].waitForExistence(timeout: 2))
        app.secureTextFields["Confirm password"].typeText("2")
        snapshot(app, "20-create-wallet")

        app.buttons["Create Wallet"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Spending"].waitForExistence(timeout: 10))
        declineSavingPassword(in: app)
        snapshot(app, "21-created")
    }

    @MainActor
    func testImportPhraseAndSignOffline() {
        // Offline from launch: this test must never be able to broadcast.
        let app = launch(["-empty", "-offline"])
        app.buttons["Import"].firstMatch.tap()

        let name = app.textFields["Wallet name"]
        XCTAssertTrue(name.waitForExistence(timeout: 3))
        name.tap()
        name.typeText("Imported")
        typeNewPassword(Self.password, into: app.secureTextFields["Strong password"], in: app)
        let phrase = app.textFields["Enter your secret phrase"]
        phrase.tap()
        phrase.typeText(Self.phrase)
        snapshot(app, "30-import")
        app.buttons["Import Wallet"].firstMatch.tap()

        XCTAssertTrue(app.staticTexts["Imported"].waitForExistence(timeout: 10))
        declineSavingPassword(in: app)
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
