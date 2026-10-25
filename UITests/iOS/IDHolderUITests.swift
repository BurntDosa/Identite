import XCTest

@MainActor final class IDHolderUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    private func launch(seed: Bool = false, skip: Bool = true, extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestingInMemoryStore"] + (skip ? ["-uiTestingSkipAuth"] : [])
            + (seed ? ["-seedSampleData"] : []) + extra
        app.launch()
        return app
    }
    private func select(_ name: String, in app: XCUIApplication) {
        let card = app.buttons["card-" + name]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        for _ in 0..<8 {
            let y = card.frame.minY + 30
            if y < 180 {
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4)).press(forDuration: 0.01, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.65)))
            } else if y > 720 {
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.65)).press(forDuration: 0.01, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4)))
            } else { break }
        }
        card.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15)).tap()
        XCTAssertTrue(app.buttons["done"].waitForExistence(timeout: 3))
    }
    private func capture(_ name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name; attachment.lifetime = .keepAlways
        add(attachment)
        do {
            try FileManager.default.createDirectory(atPath: "/tmp/identite-shots", withIntermediateDirectories: true)
            try screenshot.pngRepresentation.write(to: URL(fileURLWithPath: "/tmp/identite-shots/\(name).png"))
        } catch { XCTFail("Could not save screenshot: \(error)") }
        FileHandle.standardOutput.write(Data(("CAPTURE:" + name + "\n").utf8))
    }
    func testLockWithoutBypass() {
        for dark in [false, true] {
            let app = launch(skip: false, extra: dark ? ["-uiDark"] : [])
            let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
            if springboard.buttons["Cancel"].waitForExistence(timeout: 3) { springboard.buttons["Cancel"].tap() }
            XCTAssertTrue(app.buttons["unlock"].waitForExistence(timeout: 8))
            XCTAssertFalse(app.buttons["add-id"].exists)
            XCTAssertFalse(app.buttons["copy-name"].exists)
            capture("iphone15-lock-" + (dark ? "dark" : "light"))
            app.terminate()
        }
    }
    func testAddCopyDeletePAN() {
        let app = launch()
        XCTAssertTrue(app.staticTexts["Add your first ID"].waitForExistence(timeout: 5))
        app.buttons["add-id"].tap()
        XCTAssertTrue(app.buttons["add-pan"].waitForExistence(timeout: 3))
        capture("iphone15-add-grid-light")
        app.buttons["add-pan"].tap()
        let name = app.textFields["editor-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 3))
        name.tap()
        if app.buttons["Continue"].exists { app.buttons["Continue"].tap() }
        name.typeText("Test Person")
        let pan = app.textFields["editor-panNumber"]
        pan.tap(); pan.typeText("abcde1234f")
        XCTAssertEqual(pan.value as? String, "ABCDE1234F")
        app.swipeDown()
        capture("iphone15-editor-light")
        app.buttons["editor-save"].tap()
        app.buttons["Save anyway"].tap()
        XCTAssertTrue(app.buttons["card-pan"].waitForExistence(timeout: 5))
        select("pan", in: app)
        let row = app.buttons["copy-panNumber"]
        XCTAssertTrue(row.waitForExistence(timeout: 3))
        XCTAssertEqual(row.value as? String, "ABCDE1234F")
        row.tap()
        XCTAssertEqual(row.value as? String, "Copied")
        XCTAssertTrue(app.staticTexts["✓ Copied"].exists)
        app.buttons["ID actions"].tap()
        app.buttons["Delete"].tap()
        app.buttons["Delete ID"].tap()
        XCTAssertTrue(app.staticTexts["Add your first ID"].waitForExistence(timeout: 3))
    }
    func testSelectionRevealDismissAndEvidence() {
        let app = launch(seed: true)
        XCTAssertTrue(app.buttons["card-HSBC Live+"].waitForExistence(timeout: 5))
        capture("iphone15-home-light")
        select("HSBC Live+", in: app)
        XCTAssertTrue(app.buttons["copy-bank"].waitForExistence(timeout: 3))
        capture("iphone15-selected-bank-light")
        let row = app.buttons["copy-cardNumber"]
        XCTAssertEqual(row.value as? String, "hidden")
        app.buttons["reveal-cardNumber"].tap()
        XCTAssertEqual(row.value as? String, "4242424242424242")
        app.buttons["reveal-cardNumber"].tap()
        XCTAssertEqual(row.value as? String, "hidden")
        app.buttons["selected-card"].swipeDown(velocity: .fast)
        XCTAssertTrue(app.buttons["add-id"].waitForExistence(timeout: 3))
        app.scrollViews["home-scroll"].swipeUp()
        select("aadhaar", in: app)
        XCTAssertTrue(app.buttons["copy-aadhaarNumber"].waitForExistence(timeout: 3))
        capture("iphone15-selected-aadhaar-light")
        XCTAssertEqual(app.buttons["copy-dateOfBirth"].value as? String, "01/01/1990")
        app.buttons["reveal-aadhaarNumber"].tap()
        XCTAssertEqual(app.buttons["copy-aadhaarNumber"].value as? String, "234123412346")
        app.buttons["done"].tap()
        select("aadhaar", in: app)
        XCTAssertEqual(app.buttons["copy-aadhaarNumber"].value as? String, "hidden")
        app.buttons["bottom-pile"].swipeUp(velocity: .fast)
        XCTAssertTrue(app.buttons["add-id"].waitForExistence(timeout: 3))
    }
    func testSearchIsDisclosedAndFilters() {
        let app = launch(seed: true)
        XCTAssertFalse(app.textFields["search-ids"].exists)
        app.buttons["Search"].tap()
        let search = app.textFields["search-ids"]
        XCTAssertTrue(search.waitForExistence(timeout: 3))
        search.tap(); search.typeText("HSBC")
        XCTAssertTrue(app.buttons["card-HSBC Live+"].exists)
        XCTAssertFalse(app.buttons["card-HDFC Millennia"].exists)
        app.buttons["Search"].tap()
        XCTAssertFalse(search.exists)
        XCTAssertTrue(app.buttons["card-HDFC Millennia"].exists)
    }

    func testDarkEvidence() {
        let app = launch(seed: true, extra: ["-uiDark"])
        XCTAssertTrue(app.buttons["card-HSBC Live+"].waitForExistence(timeout: 5))
        capture("iphone15-home-dark")
        select("HSBC Live+", in: app)
        XCTAssertTrue(app.buttons["copy-bank"].waitForExistence(timeout: 3))
        capture("iphone15-selected-bank-dark")
    }
    func testScrollEdgeEvidence() {
        for dark in [false, true] {
            let app = launch(seed: true, extra: dark ? ["-uiDark"] : [])
            XCTAssertTrue(app.buttons["card-HSBC Live+"].waitForExistence(timeout: 5))
            // Scroll part-way so cards sit under the status bar and header.
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6)).press(forDuration: 0.01, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)))
            sleep(1)
            let name = "iphone15-scroll-edge-" + (dark ? "dark" : "light")
            capture(name)
            let card = app.buttons["card-HDFC Millennia"]
            let homeY = card.frame.minY
            card.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15)).tap()
            XCTAssertTrue(app.buttons["done"].waitForExistence(timeout: 3))
            XCTAssertTrue(app.buttons["copy-bank"].waitForExistence(timeout: 3))
            capture("iphone15-scrolled-open-" + (dark ? "dark" : "light"))
            app.buttons["done"].tap()
            XCTAssertTrue(app.buttons["add-id"].waitForExistence(timeout: 3))
            XCTAssertEqual(card.frame.minY, homeY, accuracy: 1)
            capture("iphone15-scrolled-closed-" + (dark ? "dark" : "light"))
            app.terminate()
        }
    }
    func testAccessibilitySize() {
        let app = launch(seed: true, extra: ["-uiAX5"])
        select("HSBC Live+", in: app)
        XCTAssertTrue(app.buttons["copy-cardNumber"].waitForExistence(timeout: 3))
        capture("iphone15-ax-selected")
        XCTAssertTrue(app.buttons["reveal-cardNumber"].isHittable)
        app.buttons["reveal-cardNumber"].tap()
        XCTAssertEqual(app.buttons["copy-cardNumber"].value as? String, "4242424242424242")
        app.buttons["done"].tap()
        XCTAssertTrue(app.buttons["add-id"].waitForExistence(timeout: 3))
    }
    func testRecording() {
        let app = launch(seed: true)
        XCTAssertTrue(app.buttons["card-HDFC Millennia"].waitForExistence(timeout: 5))
        FileHandle.standardOutput.write(Data("RECORD_START\n".utf8))
        Thread.sleep(forTimeInterval: 0.5)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.70)).press(forDuration: 0.01,
            thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.49)))
        app.buttons["card-HDFC Millennia"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15)).tap()
        Thread.sleep(forTimeInterval: 0.6)
        app.buttons["copy-bank"].tap()
        XCTAssertEqual(app.buttons["copy-bank"].value as? String, "Copied")
        Thread.sleep(forTimeInterval: 0.6)
        app.buttons["selected-card"].swipeDown(velocity: .fast)
        select("aadhaar", in: app)
        Thread.sleep(forTimeInterval: 0.6)
        app.buttons["reveal-aadhaarNumber"].tap()
        XCTAssertNotEqual(app.buttons["copy-aadhaarNumber"].value as? String, "hidden")
        Thread.sleep(forTimeInterval: 0.6)
        app.buttons["done"].tap()
        Thread.sleep(forTimeInterval: 0.5)
        FileHandle.standardOutput.write(Data("RECORD_END\n".utf8))
        XCTAssertTrue(app.buttons["add-id"].exists)
    }

    func testPFMemberCopyPreservesLetters() {
        let app = launch(seed: true)
        select("uan", in: app)
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Member ID ·")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 3))
        row.tap()
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 3))
        app.activate()
        app.buttons["done"].tap()
        app.buttons["add-id"].tap()
        app.buttons["add-pan"].tap()
        let name = app.textFields["editor-name"]
        name.tap()
        name.press(forDuration: 1.1)
        app.menuItems["Paste"].tap()
        XCTAssertEqual(name.value as? String, "MHBAN00000000000000001")
    }

    func testCVVCannotRevealOrCopyWithoutFreshAuthentication() {
        let app = launch(seed: true, extra: ["-uiTestingCVV"])
        select("HSBC Live+", in: app)
        let row = app.buttons["copy-cvv"]
        XCTAssertTrue(row.waitForExistence(timeout: 3))
        XCTAssertEqual(row.value as? String, "hidden")
        func rejectAuthentication() {
            let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
            if springboard.buttons["Cancel"].waitForExistence(timeout: 2) { springboard.buttons["Cancel"].tap() }
            let failure = app.alerts["Authentication required"]
            XCTAssertTrue(failure.waitForExistence(timeout: 4))
            failure.buttons["OK"].tap()
            XCTAssertEqual(row.value as? String, "hidden")
        }
        app.buttons["reveal-cvv"].tap()
        rejectAuthentication()
        row.tap()
        rejectAuthentication()
        app.buttons["done"].tap()
        select("HSBC Live+", in: app)
        XCTAssertEqual(app.buttons["copy-cvv"].value as? String, "hidden")
    }

    func testPrivacyWhileEditing() {
        let app = launch()
        app.buttons["add-id"].tap()
        app.buttons["add-pan"].tap()
        let name = app.textFields["editor-name"]
        name.tap(); name.typeText("Private Test Draft")
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 3))
        app.activate()
        XCTAssertEqual(name.value as? String, "Private Test Draft")
        XCTAssertFalse(app.buttons["unlock"].exists)
    }

    func testTimedOutEditorStaysCoveredWithoutReauthentication() {
        let app = launch(seed: true, extra: ["-uiTestingUnlockOnce"])
        select("HSBC Live+", in: app); editSelected(in: app)
        let nickname = app.textFields["editor-nickname"]
        nickname.tap(); nickname.typeText(" Audit draft")
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 3))
        Thread.sleep(forTimeInterval: 306)
        app.activate()
        XCTAssertTrue(app.buttons["unlock"].waitForExistence(timeout: 5))
        XCTAssertFalse(nickname.exists)
        XCTAssertFalse(app.buttons["editor-save"].exists)
        capture("iphone15-expired-editor-covered")
    }

    func testNativeEditorCopyCutAndPaste() {
        let app = launch()
        app.buttons["add-id"].tap(); app.buttons["add-pan"].tap()
        let name = app.textFields["editor-name"]
        name.tap(); name.typeText("Audit editor")
        name.press(forDuration: 0.7)
        let selectAll = app.menuItems["Select All"]
        XCTAssertTrue(selectAll.waitForExistence(timeout: 3)); selectAll.tap()
        let copy = app.menuItems["Copy"]
        XCTAssertTrue(copy.waitForExistence(timeout: 3)); copy.tap()
        name.tap()
        name.press(forDuration: 0.7)
        if selectAll.waitForExistence(timeout: 1) { selectAll.tap() }
        let cut = app.menuItems["Cut"]
        XCTAssertTrue(cut.waitForExistence(timeout: 3)); cut.tap()
        XCTAssertTrue((name.value as? String) != "Audit editor")
        name.press(forDuration: 0.7)
        let paste = app.menuItems["Paste"]
        XCTAssertTrue(paste.waitForExistence(timeout: 3)); paste.tap()
        XCTAssertTrue(name.value as? String == "Audit editor")
    }

    func testPeopleRenameRetainsNativeCopyCutAndPaste() {
        let app = launch()
        app.buttons["More"].tap(); app.buttons["People"].tap()
        app.buttons["Add person"].tap()
        let name = app.textFields["person-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 3))
        name.tap(); name.typeText("Audit Person")
        app.buttons["Save"].tap()
        let rename = app.buttons["Rename Audit Person"]
        XCTAssertTrue(rename.waitForExistence(timeout: 3)); rename.tap()
        XCTAssertTrue(name.waitForExistence(timeout: 3))
        name.tap(); name.press(forDuration: 0.7)
        let selectAll = app.menuItems["Select All"]
        XCTAssertTrue(selectAll.waitForExistence(timeout: 3)); selectAll.tap()
        let cut = app.menuItems["Cut"]
        XCTAssertTrue(cut.waitForExistence(timeout: 3)); cut.tap()
        XCTAssertFalse(name.value as? String == "Audit Person")
        name.press(forDuration: 0.7)
        let paste = app.menuItems["Paste"]
        XCTAssertTrue(paste.waitForExistence(timeout: 3)); paste.tap()
        XCTAssertTrue(name.value as? String == "Audit Person")
        capture("iphone15-person-rename-pasted")
        XCTAssertTrue(app.buttons["Save"].isEnabled, "Paste must update the name binding")
        app.buttons["Save"].tap()
        XCTAssertTrue(rename.waitForExistence(timeout: 3))
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication, towardsTop: Bool = false) {
        for _ in 0..<12 {
            if element.exists && element.isHittable { return }
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: towardsTop ? 0.30 : 0.78)).press(forDuration: 0.01,
                thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: towardsTop ? 0.78 : 0.30)))
        }
        XCTAssertTrue(element.isHittable)
    }

    private func designButton(_ id: String, in app: XCUIApplication) throws -> XCUIElement {
        let ids = ["hsbcLivePlus", "hdfcPixelPlay", "hdfcMillennia"] + (1...30).map { "cardy.\($0)" }
            + ["astra.horizonTicket", "astra.counterform", "astra.postageGarden", "astra.swissSignal",
               "astra.celestialMechanism", "astra.mosaicField", "astra.overprintPress"]
        let raw = app.buttons["editor-save"].value as? String ?? ""
        var current = raw.hasPrefix("design1:") ? try faceDesign(in: app)["design"] as? String ?? "" : raw
        if !ids.contains(current) {
            let selected = app.buttons.allElementsBoundByIndex.first { $0.identifier.hasPrefix("design-") && $0.isSelected }
            current = String((selected?.identifier ?? "").dropFirst("design-".count))
        }
        let forward = (ids.firstIndex(of: id) ?? 0) > (ids.firstIndex(of: current) ?? 0)
        let button = app.buttons["design-" + id], strip = app.scrollViews["customize-design-strip"]
        alignForCapture(strip, top: 190, in: app)
        for _ in 0..<20 {
            if button.exists && button.isHittable { return button }
            strip.coordinate(withNormalizedOffset: CGVector(dx: forward ? 0.85 : 0.15, dy: 0.5))
                .press(forDuration: 0.01,
                       thenDragTo: strip.coordinate(withNormalizedOffset: CGVector(dx: forward ? 0.15 : 0.85, dy: 0.5)),
                       withVelocity: .slow, thenHoldForDuration: 0.2)
        }
        XCTAssertTrue(button.isHittable, "Design is unreachable: \(id)")
        return button
    }

    private func editSelected(in app: XCUIApplication) {
        app.buttons["ID actions"].tap()
        app.buttons["Edit"].tap()
        XCTAssertTrue(app.buttons["editor-save"].waitForExistence(timeout: 5))
    }

    private func customizePreview(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "customize-preview").firstMatch
    }

    private func alignForCapture(_ element: XCUIElement, top: CGFloat, in app: XCUIApplication) {
        for _ in 0..<4 {
            let distance = max(-0.25, min(0.25, (element.frame.minY - top) / app.frame.height))
            if abs(distance) < 0.03 { break }
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.65)).press(forDuration: 0.01,
                thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.65 - distance)),
                withVelocity: .slow, thenHoldForDuration: 0.2)
        }
    }

    private func faceDesign(in app: XCUIApplication) throws -> [String: Any] {
        let raw = try XCTUnwrap(app.buttons["editor-save"].value as? String)
        XCTAssertTrue(raw.hasPrefix("design1:"), "Expected a saved fixed design")
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(raw.dropFirst(8).utf8)) as? [String: Any])
    }

    func testCustomiseShowsOnlyDesignAndColours() throws {
        let app = launch(seed: true, extra: ["-uiTestingFixedDesigns"])
        select("HDFC Millennia", in: app); editSelected(in: app)
        reveal(customizePreview(in: app), in: app)
        let strip = app.scrollViews["customize-design-strip"]
        reveal(strip, in: app)
        XCTAssertTrue(strip.exists, "Missing Design strip")
        let initialDesign = try XCTUnwrap(try faceDesign(in: app)["design"] as? String)
        XCTAssertTrue(app.buttons["design-" + initialDesign].isHittable, "The selected design must be visible when opening the strip")
        for label in ["Pattern", "Layout", "Panel", "Background", "Shape", "Grain"] {
            XCTAssertFalse(app.staticTexts[label].exists)
        }
        let design = try designButton("cardy.12", in: app)
        XCTAssertTrue(design.isHittable); design.tap()
        XCTAssertTrue(design.isSelected)
        XCTAssertEqual(design.label, "Cardy 12")
        reveal(customizePreview(in: app), in: app)
        XCTAssertTrue((customizePreview(in: app).value as? String ?? "").contains("Cardy 12"))
        let before = try faceDesign(in: app)
        app.buttons["customize-shuffle"].tap()
        let after = try faceDesign(in: app)
        XCTAssertNotEqual(before["design"] as? String, after["design"] as? String)
        XCTAssertEqual(before["colors"] as? NSDictionary, after["colors"] as? NSDictionary)
        XCTAssertEqual(before["colorway"] as? String, after["colorway"] as? String)
    }

    func testSavingLegacyDesignUsesCurrentEncoding() throws {
        let app = launch(seed: true, extra: ["-uiTestingLegacyDesign"])
        select("HDFC Millennia", in: app); editSelected(in: app)
        XCTAssertEqual(app.buttons["editor-save"].value as? String, "generic.ocean")
        app.buttons["editor-save"].tap()
        editSelected(in: app)
        let saved = try faceDesign(in: app)
        XCTAssertEqual(saved["presetID"] as? String, "ocean")
        XCTAssertEqual(saved["colorway"] as? String, "preset")
    }

    func testUnrelatedSavePreservesMissingDesign() throws {
        try assertUnrelatedSavePreservesDesign(flag: "-uiTestingMissingDesign", raw: "")
    }

    func testUnrelatedSavePreservesFutureDesign() throws {
        try assertUnrelatedSavePreservesDesign(flag: "-uiTestingFutureDesign", raw: "design99:future-format")
    }

    func testRevealedCVVBlocksNativeExportAndStillEdits() throws {
        let app = launch(seed: true, extra: ["-uiTestingCVV", "-uiTestingCVVReveal"])
        select("HSBC Live+", in: app); editSelected(in: app)
        let show = app.buttons["editor-cvv"]
        reveal(show, in: app); show.tap()
        let field = app.textFields["CVV"]
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        XCTAssertEqual(field.value as? String, "987")
        field.tap(); field.press(forDuration: 0.7)
        let selectAll = app.menuItems["Select All"]
        XCTAssertTrue(selectAll.waitForExistence(timeout: 3))
        selectAll.tap()
        for action in ["Copy", "Cut", "Share…"] { XCTAssertFalse(app.menuItems[action].exists) }
        field.typeText("123")
        XCTAssertEqual(field.value as? String, "123")
        app.buttons["editor-save"].tap()
        editSelected(in: app)
        reveal(show, in: app); show.tap()
        XCTAssertEqual(field.value as? String, "123")
    }

    func testNicknameSavePreservesUnknownDesign1Bytes() throws {
        try assertUnrelatedSavePreservesDesign(flag: "-uiTestingUnknownDesign1",
            raw: ##"design1:{ "future": {"finish":"foil"}, "design":"cardy.999", "colors":{"primary":"#F5B635","secondary":"#0DB774","accent":"#0DB774"}, "colorway":"custom" }"##)
    }

    func testNamedSelectorsReachOverlappingEffectiveHandles() throws {
        let app = launch(seed: true, extra: ["-uiTestingOverlappingColours"])
        select("HDFC Millennia", in: app); editSelected(in: app)
        for role in ["primary", "secondary", "accent"] {
            let selector = app.buttons["customize-select-" + role]
            reveal(selector, in: app); selector.tap()
            XCTAssertEqual(selector.label, "Select " + role + " colour")
            XCTAssertTrue(selector.isSelected)
            XCTAssertFalse(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'customize-overlap-'")).firstMatch.exists)
            let handle = app.buttons["customize-handle-" + role]
            reveal(handle, in: app, towardsTop: true)
            XCTAssertTrue(handle.isHittable)
            let before = try faceDesign(in: app)["colors"] as? [String: String]
            handle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.1,
                thenDragTo: app.otherElements["customize-colour-field"].coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.65)))
            let after = try faceDesign(in: app)["colors"] as? [String: String]
            XCTAssertNotEqual(before?[role], after?[role])
            for other in ["primary", "secondary", "accent"] where other != role { XCTAssertEqual(before?[other], after?[other]) }
        }
        capture("fixed-review-editor-roles")
    }

    private func assertUnrelatedSavePreservesDesign(flag: String, raw: String) throws {
        let app = launch(seed: true, extra: [flag])
        select("HDFC Millennia", in: app); editSelected(in: app)
        XCTAssertEqual(app.buttons["editor-save"].value as? String, raw)
        reveal(customizePreview(in: app), in: app)
        let preview = customizePreview(in: app).value as? String
        let nickname = app.textFields["editor-nickname"]
        reveal(nickname, in: app, towardsTop: true)
        nickname.tap(); nickname.typeText(" Edited")
        app.buttons["editor-save"].tap()
        editSelected(in: app)
        XCTAssertEqual(app.textFields["editor-nickname"].value as? String, "HDFC Millennia Edited")
        XCTAssertEqual(app.buttons["editor-save"].value as? String, raw)
        reveal(customizePreview(in: app), in: app)
        XCTAssertEqual(customizePreview(in: app).value as? String, preview)
        if !raw.isEmpty {
            reveal(app.scrollViews["customize-design-strip"], in: app)
            try designButton("cardy.1", in: app).tap()
            app.buttons["editor-save"].tap()
            editSelected(in: app)
            XCTAssertEqual(try faceDesign(in: app)["design"] as? String, "cardy.1")
        }
    }

    func testOnlyEffectiveColoursAreEditableAndHiddenColoursSurvive() throws {
        let app = launch(seed: true, extra: ["-uiTestingFixedDesigns"])
        select("HDFC Millennia", in: app); editSelected(in: app)
        let strip = app.scrollViews["customize-design-strip"]
        reveal(strip, in: app)
        try designButton("cardy.1", in: app).tap()
        let colourway = app.segmentedControls["customize-colourway"]
        reveal(colourway, in: app); colourway.buttons["Custom"].tap()
        let accent = app.buttons["customize-select-accent"]
        reveal(accent, in: app); accent.tap()
        let before = try faceDesign(in: app)["colors"] as? NSDictionary
        reveal(strip, in: app, towardsTop: true)
        try designButton("cardy.8", in: app).tap()
        let brightness = app.sliders["customize-brightness"]
        reveal(brightness, in: app)
        for role in ["secondary", "accent"] {
            for control in ["handle", "colour", "select", "overlap"] {
                XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "customize-\(control)-\(role)").firstMatch.exists)
            }
        }
        XCTAssertEqual(brightness.label, "Primary Brightness")
        XCTAssertEqual(try faceDesign(in: app)["colors"] as? NSDictionary, before)
        brightness.adjust(toNormalizedSliderPosition: 0.72)
        let after = try faceDesign(in: app)["colors"] as? NSDictionary
        XCTAssertNotEqual(after?["primary"] as? String, before?["primary"] as? String)
        for role in ["secondary", "accent"] { XCTAssertEqual(after?[role] as? String, before?[role] as? String) }
        capture("fixed-effective-colours-cardy8")
        reveal(strip, in: app, towardsTop: true)
        try designButton("cardy.1", in: app).tap()
        reveal(app.buttons["customize-select-accent"], in: app)
        XCTAssertEqual(try faceDesign(in: app)["colors"] as? NSDictionary, after)
        XCTAssertTrue(app.buttons["customize-select-secondary"].exists)
        XCTAssertTrue(app.buttons["customize-select-accent"].exists)
    }

    func testCustomizeCardDesign() throws {
        let app = launch(seed: true, extra: ["-uiTestingFixedDesigns"])
        select("HDFC Millennia", in: app)
        editSelected(in: app)
        let shuffle = app.buttons["customize-shuffle"]
        reveal(shuffle, in: app)
        let before = try faceDesign(in: app)
        shuffle.tap()
        let after = try faceDesign(in: app)
        XCTAssertTrue((before as NSDictionary) != (after as NSDictionary))
        XCTAssertTrue((before["colors"] as? NSDictionary) == (after["colors"] as? NSDictionary))
        XCTAssertTrue((before["cardColors"] as? NSDictionary) == (after["cardColors"] as? NSDictionary))
        let strip = app.scrollViews["customize-design-strip"]
        reveal(strip, in: app)
        let celestial = try designButton("astra.celestialMechanism", in: app)
        XCTAssertTrue(celestial.isHittable)
        celestial.tap()
        XCTAssertTrue(celestial.isSelected)
        for row in ["layout", "background", "shape", "panel"] {
            XCTAssertFalse(app.scrollViews["customize-\(row)-strip"].exists, "Astra must hide \(row)")
        }
        app.buttons["editor-save"].tap()
        editSelected(in: app)
        reveal(customizePreview(in: app), in: app)
        XCTAssertTrue(try faceDesign(in: app)["design"] as? String == "astra.celestialMechanism")
    }

    func testCustomizeColourwaysAndHandle() throws {
        let app = launch(seed: true, extra: ["-uiTestingFixedDesigns"])
        select("HDFC Millennia", in: app)
        editSelected(in: app)
        let colourway = app.segmentedControls["customize-colourway"]
        reveal(colourway, in: app)
        let scanned = try faceDesign(in: app)["cardColors"] as? NSDictionary
        let ocean = app.buttons["customize-colours-1"]
        reveal(ocean, in: app); ocean.tap()
        XCTAssertTrue(try faceDesign(in: app)["presetID"] as? String == "ocean")
        colourway.buttons["Custom"].tap()
        let handle = app.descendants(matching: .any).matching(identifier: "customize-handle-primary").firstMatch
        reveal(handle, in: app)
        let before = try faceDesign(in: app)["colors"] as? [String: String]
        let field = app.otherElements["customize-colour-field"]
        handle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.1,
            thenDragTo: field.coordinate(withNormalizedOffset: CGVector(dx: 0.78, dy: 0.65)))
        let after = try faceDesign(in: app)["colors"] as? [String: String]
        XCTAssertTrue(before?["primary"] != after?["primary"])
        XCTAssertTrue(before?["secondary"] == after?["secondary"] && before?["accent"] == after?["accent"])
        let brightness = app.sliders["customize-brightness"]
        reveal(brightness, in: app)
        brightness.adjust(toNormalizedSliderPosition: 0.72)
        let dimmed = try faceDesign(in: app)["colors"] as? [String: String]
        XCTAssertTrue(after?["primary"] != dimmed?["primary"], "Brightness must change the selected colour")
        XCTAssertTrue(after?["secondary"] == dimmed?["secondary"] && after?["accent"] == dimmed?["accent"])
        capture("fixed-customize-custom")
        for _ in 0..<4 {
            if colourway.buttons["Card"].isHittable { break }
            app.swipeDown()
        }
        colourway.buttons["Card"].tap()
        XCTAssertTrue((try faceDesign(in: app)["colors"] as? NSDictionary) == scanned)
        for role in ["primary", "secondary", "accent"] {
            let swatch = app.descendants(matching: .any).matching(identifier: "customize-card-" + role).firstMatch
            XCTAssertTrue(swatch.exists)
            XCTAssertEqual(swatch.label, role.capitalized + " colour")
            XCTAssertFalse((swatch.value as? String ?? "").isEmpty, "Each scanned colour needs a spoken description")
        }
        colourway.buttons["Presets"].tap()
        colourway.buttons["Card"].tap()
        app.buttons["editor-save"].tap()
        editSelected(in: app)
        reveal(customizePreview(in: app), in: app)
        XCTAssertTrue(try faceDesign(in: app)["colorway"] as? String == "card")
        XCTAssertTrue((try faceDesign(in: app)["cardColors"] as? NSDictionary) == scanned)
    }

    func testNewCardGetsFixedDesign() throws {
        let app = launch(seed: true)
        app.buttons["add-id"].tap()
        app.buttons["add-debitCard"].tap()
        let bank = app.textFields["editor-bank"]
        XCTAssertTrue(bank.waitForExistence(timeout: 3))
        let initial = try faceDesign(in: app)
        XCTAssertEqual(initial["colorway"] as? String, "preset")
        bank.tap(); bank.typeText("Test Bank")
        let number = app.textFields["editor-cardNumber"]
        number.tap(); number.typeText("4111 1111 1111 1111")
        app.buttons["editor-save"].tap()
        if app.buttons["Save anyway"].waitForExistence(timeout: 2) { app.buttons["Save anyway"].tap() }
        select("debitCard", in: app)
        editSelected(in: app)
        reveal(customizePreview(in: app), in: app)
        let saved = try faceDesign(in: app)
        XCTAssertTrue(saved["colorway"] as? String == "preset")
        XCTAssertNotNil(saved["presetID"])
        XCTAssertNil(saved["cardColors"])
        XCTAssertEqual(saved["design"] as? String, initial["design"] as? String)
        let colourway = app.segmentedControls["customize-colourway"]
        reveal(colourway, in: app)
        XCTAssertFalse(colourway.buttons["Card"].exists)
        app.buttons["Cancel"].tap()
        XCTAssertFalse(app.buttons["Discard Changes"].exists)
    }

    func testEditorConfirmsDiscardOnlyAfterChanges() {
        let app = launch(seed: true)
        select("HDFC Millennia", in: app)
        editSelected(in: app)
        app.buttons["Cancel"].tap()
        XCTAssertFalse(app.buttons["Discard Changes"].exists)
        editSelected(in: app)
        let nickname = app.textFields["editor-nickname"]
        nickname.tap(); nickname.typeText(" Draft")
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["Discard Changes"].waitForExistence(timeout: 3))
        // iOS can present this as a popover, whose cancel action is tapping outside.
        if app.buttons["Keep Editing"].exists { app.buttons["Keep Editing"].tap() }
        else { app.navigationBars["Edit Debit Card"].staticTexts["Edit Debit Card"].tap() }
        XCTAssertFalse(app.buttons["Discard Changes"].exists)
        XCTAssertTrue(app.buttons["editor-save"].exists)
        app.buttons["Cancel"].tap(); app.buttons["Discard Changes"].tap()
        editSelected(in: app)
        XCTAssertTrue(app.textFields["editor-nickname"].value as? String == "HDFC Millennia")
    }

    func testDirtySwipeOffersDiscardAndKeepsDraftUntilConfirmed() {
        let app = launch(seed: true)
        select("HDFC Millennia", in: app)
        editSelected(in: app)
        let nickname = app.textFields["editor-nickname"]
        nickname.tap(); nickname.typeText(" Draft")
        let bar = app.navigationBars["Edit Debit Card"]
        bar.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.05,
            thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85)))
        XCTAssertTrue(app.buttons["Discard Changes"].waitForExistence(timeout: 3))
        if app.buttons["Keep Editing"].exists { app.buttons["Keep Editing"].tap() }
        else { bar.staticTexts["Edit Debit Card"].tap() }
        XCTAssertTrue(app.buttons["editor-save"].exists)
        XCTAssertTrue((nickname.value as? String ?? "").hasSuffix(" Draft"))
        app.buttons["Cancel"].tap(); app.buttons["Discard Changes"].tap()
        editSelected(in: app)
        XCTAssertTrue(nickname.value as? String == "HDFC Millennia")
        bar.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.05,
            thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85)))
        XCTAssertTrue(app.buttons["done"].waitForExistence(timeout: 3), "A clean editor should dismiss")
    }

    func testReplicaHidesColoursAndRestoresPreviousFaceColours() throws {
        let app = launch(seed: true, extra: ["-uiTestingFixedDesigns"])
        select("HDFC Millennia", in: app); editSelected(in: app)
        let before = try faceDesign(in: app)
        let strip = app.scrollViews["customize-design-strip"]
        reveal(strip, in: app)
        let replica = try designButton("hsbcLivePlus", in: app)
        replica.tap()
        XCTAssertTrue(replica.isSelected)
        XCTAssertEqual(app.buttons["editor-save"].value as? String, "hsbcLivePlus")
        XCTAssertFalse(app.segmentedControls["customize-colourway"].exists)
        XCTAssertFalse(app.staticTexts["This design uses its own colours."].exists)
        try designButton("cardy.1", in: app).tap()
        let restored = try faceDesign(in: app)
        XCTAssertEqual(before["colors"] as? NSDictionary, restored["colors"] as? NSDictionary)
        XCTAssertEqual(before["cardColors"] as? NSDictionary, restored["cardColors"] as? NSDictionary)
        XCTAssertEqual(before["colorway"] as? String, restored["colorway"] as? String)
        XCTAssertEqual(before["presetID"] as? String, restored["presetID"] as? String)
    }

    func testFreshReplicaGetsPresetWhenChoosingDesign() throws {
        let app = launch(seed: true)
        select("HDFC Millennia", in: app); editSelected(in: app)
        reveal(app.scrollViews["customize-design-strip"], in: app)
        try designButton("cardy.1", in: app).tap()
        let saved = try faceDesign(in: app)
        XCTAssertEqual(saved["colorway"] as? String, "preset")
        XCTAssertNotNil(saved["presetID"])
        XCTAssertNil(saved["cardColors"])
        reveal(app.segmentedControls["customize-colourway"], in: app)
        XCTAssertFalse(app.segmentedControls["customize-colourway"].buttons["Card"].exists)
    }

    func testOverlappingHandlesRemainReachable() throws {
        let app = launch(seed: true, extra: ["-uiTestingFixedDesignsWallet"])
        select("Design 01", in: app); editSelected(in: app)
        let colourway = app.segmentedControls["customize-colourway"]
        reveal(colourway, in: app); colourway.buttons["Custom"].tap()
        let secondary = app.buttons["customize-select-secondary"]
        reveal(secondary, in: app)
        XCTAssertTrue(secondary.isHittable, "Nearby handles need a reachable role selector")
        secondary.tap()
        let handle = app.buttons["customize-handle-secondary"]
        XCTAssertTrue(handle.isSelected)
        let before = try faceDesign(in: app)["colors"] as? [String: String]
        let field = app.otherElements["customize-colour-field"]
        alignForCapture(field, top: 230, in: app)
        capture("fixed-colour-field-secondary-selected")
        handle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.1,
            thenDragTo: field.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.5)))
        let after = try faceDesign(in: app)["colors"] as? [String: String]
        XCTAssertTrue(before?["secondary"] != after?["secondary"])
        XCTAssertTrue(before?["primary"] == after?["primary"] && before?["accent"] == after?["accent"])
        for role in ["primary", "secondary", "accent"] { XCTAssertTrue(app.buttons["customize-handle-" + role].exists) }
    }

    func testNativeColourWellEditsSelectedRole() throws {
        let app = launch(seed: true, extra: ["-uiTestingFixedDesignsWallet"])
        select("Design 01", in: app); editSelected(in: app)
        let colourway = app.segmentedControls["customize-colourway"]
        reveal(colourway, in: app); colourway.buttons["Custom"].tap()
        let well = app.buttons["customize-colour-secondary"]
        reveal(well, in: app)
        let before = try faceDesign(in: app)["colors"] as? [String: String]
        well.tap()
        XCTAssertTrue(app.buttons["Sliders"].waitForExistence(timeout: 3))
        app.buttons["Sliders"].tap()
        let slider = app.sliders.matching(NSPredicate(format: "identifier != %@", "customize-brightness")).firstMatch
        XCTAssertTrue(slider.waitForExistence(timeout: 3))
        slider.adjust(toNormalizedSliderPosition: 0.25)
        app.buttons["close"].tap()
        let after = try faceDesign(in: app)["colors"] as? [String: String]
        XCTAssertTrue(before?["secondary"] != after?["secondary"])
        XCTAssertTrue(before?["primary"] == after?["primary"] && before?["accent"] == after?["accent"])
        XCTAssertTrue(app.buttons["customize-handle-secondary"].isSelected)
    }

    func testFixedDesignWalletEvidence() throws {
        for dark in [false, true] {
            let mode = dark ? "dark" : "light"
            let app = launch(seed: true, extra: ["-uiTestingFixedDesignsWallet"] + (dark ? ["-uiDark"] : []))
            XCTAssertTrue(app.buttons["card-Design 01"].waitForExistence(timeout: 5))
            XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "card-Design ")).count, 10)
            capture("fixed-wallet-" + mode)
            for (name, network) in [("Design 01", "visa"), ("Design 02", "mastercard"), ("Design 03", "rupay")] {
                select(name, in: app)
                capture("fixed-" + network + "-" + mode)
                app.buttons["done"].tap()
            }
            select("Design 01", in: app)
            editSelected(in: app)
            reveal(app.buttons["customize-shuffle"], in: app)
            alignForCapture(customizePreview(in: app), top: 170, in: app)
            capture(dark ? "fixed-customize-dark" : "fixed-customize")
            let colourway = app.segmentedControls["customize-colourway"]
            reveal(colourway, in: app)
            colourway.buttons["Custom"].tap()
            reveal(app.sliders["customize-brightness"], in: app)
            alignForCapture(app.otherElements["customize-colour-field"], top: 230, in: app)
            capture("fixed-colour-field-" + mode)
            reveal(app.scrollViews["customize-design-strip"], in: app, towardsTop: true)
            let design = try designButton("cardy.1", in: app)
            design.tap()
            XCTAssertTrue(design.isSelected)
            alignForCapture(app.scrollViews["customize-design-strip"], top: 190, in: app)
            capture("fixed-design-" + mode)
            app.terminate()
        }
    }

    func testReviewDesignEvidence() throws {
        for id in ["cardy.12", "cardy.15", "cardy.22", "cardy.26"] { for dark in [false, true] {
            let mode = dark ? "dark" : "light"
            let app = launch(seed: true, extra: ["-uiTestingReviewDesign", id] + (dark ? ["-uiDark"] : []))
            select("Review Card", in: app)
            capture("fixed-review-\(id)-\(mode)")
            editSelected(in: app)
            reveal(customizePreview(in: app), in: app)
            alignForCapture(customizePreview(in: app), top: 170, in: app)
            capture("fixed-review-\(id)-editor-\(mode)")
            app.terminate()
        } }
    }

    func testStressWalletAndCustomizeEvidence() throws {
        for index in 0..<6 { for dark in [false, true] {
            let suffix = "\(index + 1)-" + (dark ? "dark" : "light")
            let app = launch(seed: true, extra: ["-uiTestingStressCase", String(index)] + (dark ? ["-uiDark"] : []))
            XCTAssertTrue(app.buttons["card-Stress Card"].waitForExistence(timeout: 5))
            capture("stress-wallet-" + suffix)
            select("Stress Card", in: app)
            XCTAssertFalse(app.buttons["reveal-cvv"].exists, "A fixture with no CVV must not show a CVV row")
            editSelected(in: app)
            let preview = customizePreview(in: app)
            reveal(preview, in: app)
            alignForCapture(preview, top: 170, in: app)
            capture("stress-customize-" + suffix)
            try preview.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "/tmp/identite-shots/stress-preview-\(suffix).png"))
            let raw = try faceDesign(in: app)
            XCTAssertNotNil(raw["design"])
            app.terminate()
        } }
    }

    func testCustomizeColoursAtLargestTextSize() {
        let app = launch(seed: true, extra: ["-uiTestingFixedDesignsWallet",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        select("Design 01", in: app)
        editSelected(in: app)
        let colourway = app.segmentedControls["customize-colourway"]
        reveal(colourway, in: app); colourway.buttons["Custom"].tap()
        reveal(app.sliders["customize-brightness"], in: app)
        XCTAssertTrue(app.buttons["customize-handle-primary"].exists)
        alignForCapture(app.otherElements["customize-colour-field"], top: 170, in: app)
        capture("fixed-customize-accessibility")
        let primary = app.buttons["customize-colour-primary"]
        let secondary = app.buttons["customize-colour-secondary"]
        let accent = app.buttons["customize-colour-accent"]
        reveal(accent, in: app)
        XCTAssertGreaterThanOrEqual(secondary.frame.minY, primary.frame.maxY,
                                   "Large-text colour controls need separate rows to keep role labels readable")
        XCTAssertGreaterThanOrEqual(accent.frame.minY, secondary.frame.maxY)
        alignForCapture(primary, top: 200, in: app)
        capture("fixed-colour-wells-accessibility")
    }

}
