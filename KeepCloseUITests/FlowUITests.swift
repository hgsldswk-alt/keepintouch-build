import XCTest

final class FlowUITests: XCTestCase {
    private enum Language: String, CaseIterable {
        case hans = "zh-Hans", hant = "zh-Hant", en

        var locale: String {
            switch self {
            case .hans: return "zh_CN"
            case .hant: return "zh_TW"
            case .en: return "en_US"
            }
        }

        var mom: String { self == .en ? "Mom" : (self == .hans ? "老妈" : "老媽") }
        var grandma: String { self == .en ? "Grandma" : "外婆" }
    }

    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    func testAAAWarmUpSimulator() {
        XCTExpectFailure("云端模拟器首次启动可能超时", strict: false)
        app.launchArguments = ["-ui-testing", "-reset"]  // 不留首启状态影响后面的用例
        app.launch()
        app.terminate()
    }

    private func launch(_ language: Language = .hans, seed: Bool = true, reset: Bool = true, extra: [String] = []) {
        app.launchArguments = ["-ui-testing", "-AppleLanguages", "(\(language.rawValue))", "-AppleLocale", language.locale,
                               "-now", "2026-11-24T10:00:00"] + (reset ? ["-reset"] : []) + (seed ? ["-seed", "store"] : []) + extra
        app.launch()
        let first = extra.contains("-paywall") ? app.staticTexts["paywall.title"] : app.staticTexts["home.title"]
        XCTAssertTrue(first.waitForExistence(timeout: 12))
    }

    private func tap(_ identifier: String, scroll: Bool = true, file: StaticString = #filePath, line: UInt = #line) {
        let button = app.buttons.matching(identifier: identifier).firstMatch
        if scroll {
            for _ in 0..<4 where !(button.exists && button.isHittable) { app.swipeUp() }
        }
        XCTAssertTrue(button.waitForExistence(timeout: 6), identifier, file: file, line: line)
        button.tap()
    }

    private func reveal(_ element: XCUIElement, in scrollView: XCUIElement, swipeUp: Bool = true,
                        file: StaticString = #filePath, line: UInt = #line) {
        if element.waitForExistence(timeout: 1), element.isHittable { return }
        XCTAssertTrue(scrollView.waitForExistence(timeout: 6), "未找到滚动容器", file: file, line: line)
        for _ in 0..<5 {
            if element.exists && element.isHittable { break }
            if swipeUp { scrollView.swipeUp() } else { scrollView.swipeDown() }
        }
        XCTAssertTrue(element.waitForExistence(timeout: 6) && element.isHittable, "未滚动到 \(element)", file: file, line: line)
    }

    private func openCard(_ name: String) {
        let card = app.buttons.matching(identifier: "home.card").matching(NSPredicate(format: "label CONTAINS %@", name)).firstMatch
        for _ in 0..<4 where !(card.exists && card.isHittable) { app.swipeUp() }
        XCTAssertTrue(card.waitForExistence(timeout: 6), name)
        card.tap()
        XCTAssertTrue(app.buttons["detail.back"].waitForExistence(timeout: 6))
    }

    private func back() {
        let button = app.buttons["detail.back"]
        XCTAssertTrue(button.waitForExistence(timeout: 6))
        for _ in 0..<2 {
            for name in ["完成", "Done"] where app.buttons[name].exists { app.buttons[name].firstMatch.tap(); sleep(1) }
            let f = button.frame
            app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: f.midX, dy: f.midY)).tap()
            if app.staticTexts["home.title"].waitForExistence(timeout: 4) { return }
        }
        shot("debug-after-back")
        print("DEBUG-TREE-BEGIN\n\(app.debugDescription)\nDEBUG-TREE-END")
        XCTFail("返回后没回到首页")
    }

    private func relaunch(_ language: Language) {
        app.terminate()
        launch(language)
    }

    private func waitToastGone() {
        let toast = app.staticTexts["toast.text"]
        if toast.exists { _ = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: toast)], timeout: 6) }
    }

    private func shot(_ name: String) {
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let path = ProcessInfo.processInfo.environment["TEST_RUNNER_SHOTS_DIR"] ?? ProcessInfo.processInfo.environment["SHOTS_DIR"] {
            let root = URL(fileURLWithPath: path, isDirectory: true)
            try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try? screenshot.pngRepresentation.write(to: root.appendingPathComponent(name + ".png"))
        }
    }

    private func storeShots(_ language: Language) {
        launch(language)
        XCTAssertTrue(app.buttons.matching(identifier: "card.call").firstMatch.waitForExistence(timeout: 6))
        shot("store-\(language.rawValue)-01-home")

        openCard(language.mom)
        tap("detail.call", scroll: false)
        XCTAssertTrue(app.staticTexts["toast.text"].waitForExistence(timeout: 6))
        shot("store-\(language.rawValue)-02-call")
        waitToastGone()
        relaunch(language)

        openCard(language.grandma)
        tap("detail.visit", scroll: false)
        let photoPrompt = app.descendants(matching: .any).matching(identifier: "detail.hint.camera").firstMatch
        XCTAssertTrue(photoPrompt.waitForExistence(timeout: 6))
        waitToastGone()
        shot("store-\(language.rawValue)-03-photo")
        relaunch(language)

        openCard(language.mom)
        app.swipeUp()
        XCTAssertTrue(app.buttons.matching(identifier: "detail.photo").firstMatch.waitForExistence(timeout: 6))
        shot("store-\(language.rawValue)-04-timeline")

        tap("detail.share")
        XCTAssertTrue(app.buttons["share.go"].waitForExistence(timeout: 15))
        shot("store-\(language.rawValue)-05-card")
        app.buttons["share.go"].tap()
        XCTAssertTrue(app.staticTexts["share.requested"].waitForExistence(timeout: 15))
    }

    func testStoreShotsHans() { storeShots(.hans) }
    func testStoreShotsHant() { storeShots(.hant) }
    func testStoreShotsEnglish() { storeShots(.en) }

    func testPaywallShot() {
        launch(.hans, extra: ["-paywall", "-paid-mode"])
        XCTAssertTrue(app.staticTexts["paywall.title"].waitForExistence(timeout: 8))
        shot("paid-01-paywall")
    }

    func testFirstRunSuggestionsAddAllThenLogAndUndo() {
        launch(.hans, seed: false, extra: ["-suggest"])
        tap("suggest.add", scroll: false)
        XCTAssertEqual(app.buttons.matching(identifier: "home.card").count, 3)
        let done = app.buttons.matching(identifier: "card.done").firstMatch
        done.tap()
        XCTAssertTrue(app.buttons["toast.undo"].waitForExistence(timeout: 4))
        app.buttons["toast.undo"].tap()
        XCTAssertFalse(app.buttons["toast.undo"].exists)
    }

    func testEmptyStateManualAdd() {
        launch(.en, seed: false)
        tap("empty.manual", scroll: false)
        let field = app.textFields["editor.name"]
        XCTAssertTrue(field.waitForExistence(timeout: 6))
        field.tap()
        field.typeText("Aunt May")
        app.buttons["editor.save"].tap()
        XCTAssertTrue(app.buttons.matching(identifier: "home.card").firstMatch.waitForExistence(timeout: 6))
        XCTAssertTrue(app.buttons.matching(identifier: "card.call").firstMatch.exists)
    }

    func testImportSettingsCode() {
        launch(.hans, extra: ["-paste-code", "KL1.P5G10S14K7F30O30T2000"])
        tap("home.more", scroll: false)
        tap("more.paste-code")
        XCTAssertTrue(app.buttons["import.apply"].waitForExistence(timeout: 6))
        app.buttons["import.apply"].tap()
        XCTAssertTrue(app.staticTexts["home.title"].waitForExistence(timeout: 6))
        openCard(Language.hans.mom)
        XCTAssertTrue(app.staticTexts["每 5 天提醒"].exists)
        XCTAssertTrue(app.staticTexts["detail.due-date"].exists)
    }

    func testHomePhotoOpensLibraryWithoutEnteringDetail() {
        launch(.en)
        let add = app.buttons.matching(identifier: "home.photo.add")
            .matching(NSPredicate(format: "label CONTAINS %@", Language.en.grandma)).firstMatch
        reveal(add, in: app.scrollViews.firstMatch)
        add.tap()
        let libraryByID = app.buttons.matching(identifier: "photo.library")
        let libraryByLabel = app.buttons.matching(NSPredicate(format: "label == %@", "Photo Library"))
        if !libraryByID.firstMatch.waitForExistence(timeout: 1) {
            XCTAssertTrue(libraryByLabel.firstMatch.waitForExistence(timeout: 6))
        }
        XCTAssertFalse(app.buttons["detail.back"].exists)
        guard let library = libraryByID.allElementsBoundByIndex.first(where: \.isHittable)
            ?? libraryByLabel.allElementsBoundByIndex.first(where: \.isHittable) else {
            XCTFail("未找到可点的 Photo Library 选项")
            return
        }
        library.tap()
        let fixture = app.descendants(matching: .any).matching(identifier: "photo.fixture").firstMatch
        XCTAssertTrue(fixture.waitForExistence(timeout: 6))
        fixture.tap()
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: add)],
                                      timeout: 8), .completed)
        openCard(Language.en.grandma)
        reveal(app.buttons["detail.photo"].firstMatch, in: app.scrollViews.firstMatch)
    }

    func testJustMetPhotoPromptStaysDismissedAfterAnotherVisitAndRelaunch() {
        launch(.en)
        openCard(Language.en.grandma)
        let elements = app.descendants(matching: .any)
        let justMet = elements.matching(identifier: "detail.visit").firstMatch
        let hint = elements.matching(identifier: "detail.hint.title").firstMatch
        let camera = elements.matching(identifier: "detail.hint.camera").firstMatch
        let close = elements.matching(identifier: "detail.hint.close").firstMatch
        let toast = elements.matching(identifier: "toast.text").firstMatch

        XCTAssertTrue(justMet.waitForExistence(timeout: 6))
        justMet.tap()
        XCTAssertTrue(hint.waitForExistence(timeout: 6))
        XCTAssertEqual(hint.label, "Take a photo together?")
        XCTAssertTrue(camera.isHittable)
        XCTAssertTrue(close.isHittable)
        close.tap()
        let disappeared = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: hint)
        XCTAssertEqual(XCTWaiter.wait(for: [disappeared], timeout: 6), .completed)
        waitToastGone()

        justMet.tap()
        XCTAssertTrue(toast.waitForExistence(timeout: 6))
        XCTAssertFalse(hint.waitForExistence(timeout: 2))

        app.terminate()
        launch(.en, seed: false, reset: false)
        openCard(Language.en.grandma)
        justMet.tap()
        XCTAssertTrue(toast.waitForExistence(timeout: 6))
        XCTAssertFalse(hint.waitForExistence(timeout: 2))
    }

    func testPhotoPromptSavesCaptureToTheCurrentPersonsTimeline() {
        launch(.en)
        openCard(Language.en.grandma)
        let elements = app.descendants(matching: .any)
        let age = elements.matching(identifier: "detail.photo.age").firstMatch
        let justMet = elements.matching(identifier: "detail.visit").firstMatch
        let camera = elements.matching(identifier: "detail.hint.camera").firstMatch
        let capture = elements.matching(identifier: "photo.fixture").firstMatch
        XCTAssertTrue(age.waitForExistence(timeout: 6))
        XCTAssertEqual(age.label, "No photos together yet")

        justMet.tap()
        XCTAssertTrue(camera.waitForExistence(timeout: 6))
        camera.tap()
        XCTAssertTrue(capture.waitForExistence(timeout: 6))
        capture.tap()
        let saved = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "Last photo together: 0 months ago"), object: age)
        XCTAssertEqual(XCTWaiter.wait(for: [saved], timeout: 8), .completed)
        XCTAssertFalse(camera.exists)
        let entry = elements.matching(identifier: "detail.photo").firstMatch
        for _ in 0..<4 where !entry.isHittable { app.swipeUp() }
        XCTAssertTrue(entry.isHittable)
    }

    func testMilestoneDismissalSurvivesRelaunch() {
        launch(.en)
        openCard(Language.en.mom)
        tap("milestone.close")
        XCTAssertFalse(app.buttons["milestone.make"].exists)
        app.terminate()
        launch(.en, seed: false, reset: false)
        openCard(Language.en.mom)
        let share = app.buttons["detail.share"]
        for _ in 0..<4 where !(share.exists && share.isHittable) { app.swipeUp() }
        XCTAssertTrue(share.isHittable)
        XCTAssertFalse(app.buttons["milestone.make"].exists)
    }

    func testShareKeepsFullNameAndNumberPrivateUntilEnabled() {
        launch(.en)
        openCard(Language.en.mom)
        tap("detail.share")
        let title = app.staticTexts["share.artwork.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 15))
        XCTAssertTrue(title.label.contains("Mom"))
        XCTAssertFalse(app.staticTexts["share.artwork.phone"].exists)
        let privacy = app.switches["share.show-details"]
        XCTAssertTrue(privacy.waitForExistence(timeout: 15))
        privacy.tap()
        XCTAssertTrue(title.label.contains("Linda Chen"))
        XCTAssertTrue(app.staticTexts["share.artwork.phone"].exists)
        privacy.tap()
        XCTAssertFalse(app.staticTexts["share.artwork.phone"].exists)
    }

    func testMonthlySummaryShowsWhoAndLargestContactGap() {
        launch(.en)
        tap("home.more", scroll: false)
        tap("more.summary")
        let people = app.staticTexts.matching(identifier: "summary.person")
        XCTAssertTrue(people.firstMatch.waitForExistence(timeout: 15))
        XCTAssertEqual(Set(people.allElementsBoundByIndex.map(\.label)), ["Mom", "Dad"])
        XCTAssertTrue(app.staticTexts["summary.longest"].label.contains("Alex"))
    }

    func testFaceTimeOffersManualRecordAfterReturning() {
        launch(.en)
        openCard(Language.en.mom)
        tap("detail.facetime", scroll: false)
        XCTAssertFalse(app.buttons["candidate.yes"].exists)
        XCUIDevice.shared.press(.home)
        app.activate()
        tap("candidate.yes")
        let faceTimeRecord = app.buttons.matching(identifier: "detail.record")
            .matching(NSPredicate(format: "label CONTAINS %@", "FaceTime")).firstMatch
        XCTAssertTrue(faceTimeRecord.waitForExistence(timeout: 6))
        XCTAssertFalse(app.buttons["candidate.yes"].exists)
    }

    func testExpiredTrialCanExportAndRestoreBackup() {
        launch(.en, extra: ["-expired", "-backup-fixture"])
        tap("home.more", scroll: false)
        XCTAssertTrue(app.buttons["more.done"].waitForExistence(timeout: 6))
        let collection = app.collectionViews.firstMatch
        let table = app.tables.firstMatch
        let form = collection.exists ? collection : (table.exists ? table : app.scrollViews.firstMatch)
        let export = app.buttons["backup.export"]
        reveal(export, in: form)
        export.tap()
        let exported = app.staticTexts["backup.exported"]
        if !exported.waitForExistence(timeout: 8) { reveal(exported, in: form) }
        let restore = app.buttons["backup.restore"]
        reveal(restore, in: form, swipeUp: false)
        restore.tap()
        let counts = app.staticTexts["backup.counts"]
        XCTAssertTrue(counts.waitForExistence(timeout: 6))
        XCTAssertEqual(counts.label, "4 people, 5 contact entries, 4 photos")
        let confirm = app.buttons["backup.confirm"]
        reveal(confirm, in: app.scrollViews.firstMatch)
        confirm.tap()
        XCTAssertTrue(app.staticTexts["home.title"].waitForExistence(timeout: 8))
        openCard(Language.en.mom)
        reveal(app.buttons["detail.photo"].firstMatch, in: app.scrollViews.firstMatch)
    }

    func testExpiryNoticeAppearsOnceAndKeepsCoreActionsAvailable() {
        launch(.en)
        let title = app.staticTexts["purchase.expiry-title"]
        XCTAssertFalse(title.exists)
        app.terminate()
        launch(.en, seed: false, reset: false, extra: ["-expired"])
        XCTAssertTrue(title.waitForExistence(timeout: 6))
        XCTAssertEqual(title.label, "Your trial has ended")
        XCTAssertTrue(app.buttons["purchase.expiry-buy"].exists)
        let homeScroll = app.scrollViews.firstMatch
        reveal(app.buttons.matching(identifier: "card.call").firstMatch, in: homeScroll)
        let dismiss = app.buttons["purchase.expiry-dismiss"]
        reveal(dismiss, in: homeScroll, swipeUp: false)
        dismiss.tap()
        XCTAssertFalse(title.exists)

        app.terminate()
        launch(.en, seed: false, reset: false, extra: ["-expired"])
        XCTAssertFalse(title.waitForExistence(timeout: 2))
        openCard(Language.en.mom)
        reveal(app.buttons["detail.photo"].firstMatch, in: app.scrollViews.firstMatch)
    }

    func testExpiryNoticeBuyOpensPaywallOnlyOnTap() {
        launch(.hant, extra: ["-expired"])
        let title = app.staticTexts["purchase.expiry-title"]
        let paywall = app.staticTexts["paywall.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 6))
        XCTAssertFalse(paywall.exists)
        tap("purchase.expiry-buy", scroll: false)
        XCTAssertTrue(paywall.waitForExistence(timeout: 6))
        tap("paywall.close", scroll: false)
        XCTAssertTrue(app.staticTexts["home.title"].waitForExistence(timeout: 6))
        XCTAssertFalse(title.exists)
    }

    func testWeekendReminderCanBeSetDuringTrialAndRestoredAfterUnlock() {
        launch(.en)
        openCard(Language.en.mom)
        tap("detail.edit", scroll: false)
        let editorName = app.descendants(matching: .any).matching(identifier: "editor.name").firstMatch
        if !editorName.waitForExistence(timeout: 4), app.buttons["detail.edit"].isHittable { app.buttons["detail.edit"].tap() }
        if !editorName.waitForExistence(timeout: 6) { print("EDIT-OPEN-TREE", app.debugDescription) }
        XCTAssertTrue(editorName.exists)
        let weekend = app.descendants(matching: .any).matching(identifier: "editor.weekend").firstMatch  // 11-23 Claude：云测11 Form 里找不到 Switch 类型，改按标识找任意类型
        for _ in 0..<5 where !(weekend.exists && weekend.isHittable) { app.swipeUp() }
        if !weekend.exists { print("EDITOR-TREE", app.debugDescription) }
        XCTAssertTrue(weekend.isEnabled)
        XCTAssertEqual(weekend.value as? String, "0")
        weekend.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        let switchedOn = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == '1'"), object: weekend)
        _ = XCTWaiter.wait(for: [switchedOn], timeout: 3)
        if (weekend.value as? String) != "1" { print("WEEKEND-TREE", weekend.debugDescription) }
        XCTAssertEqual(weekend.value as? String, "1")
        tap("editor.save", scroll: false)

        app.terminate()
        launch(.en, seed: false, reset: false, extra: ["-expired"])
        openCard(Language.en.mom)
        tap("detail.edit", scroll: false)
        for _ in 0..<5 where !(weekend.exists && weekend.isHittable) { app.swipeUp() }
        if !weekend.exists { print("EDITOR-TREE", app.debugDescription) }
        XCTAssertFalse(weekend.isEnabled)
        XCTAssertEqual(weekend.value as? String, "1")
        tap("editor.unlock")
        XCTAssertTrue(app.staticTexts["paywall.title"].waitForExistence(timeout: 6))
        tap("paywall.restore")
        let unlocked = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: weekend)
        XCTAssertEqual(XCTWaiter.wait(for: [unlocked], timeout: 6), .completed)
        XCTAssertEqual(weekend.value as? String, "1")
    }
}
