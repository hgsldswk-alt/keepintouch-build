import XCTest
@testable import KeepClose

final class CoreTests: XCTestCase {
    private var calendar: Calendar = {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return value
    }()

    private func day(_ text: String, hour: Int = 12) -> Date {
        let parts = text.split(separator: "-").compactMap { Int($0) }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: hour))!
    }

    private func person(_ cycle: Int, created: String = "2026-01-01", relation: Relation = .mother) -> Person {
        Person(nickname: "老妈", relation: relation, cycleDays: cycle, createdAt: day(created))
    }

    func testDefaultCyclesFollowRelation() {
        XCTAssertEqual(Relation.mother.defaultCycle, 7)
        XCTAssertEqual(Relation.grandparent.defaultCycle, 14)
        XCTAssertEqual(Relation.sibling.defaultCycle, 14)
        XCTAssertEqual(Relation.child.defaultCycle, 7)
        XCTAssertEqual(Relation.friend.defaultCycle, 30)
        XCTAssertEqual(Preferences().cycle(for: .other), 30)
    }

    func testNeverContactedIsDueOnCreationDay() {
        let p = person(7, created: "2026-11-20")
        let s = Schedule.standing(p, events: [], now: day("2026-11-24"), calendar: calendar)
        XCTAssertNil(s.daysSince)
        XCTAssertEqual(s.overdue, 4)
    }

    func testOverdueCountsFromLastContactPlusCycle() {
        let p = person(7)
        let events = [ContactEvent(personID: p.id, occurredAt: day("2026-11-01", hour: 23), method: .call),
                      ContactEvent(personID: p.id, occurredAt: day("2026-10-01"), method: .visit)]
        let s = Schedule.standing(p, events: events, now: day("2026-11-24", hour: 1), calendar: calendar)
        XCTAssertEqual(s.daysSince, 23)
        XCTAssertEqual(s.overdue, 16)
        XCTAssertEqual(s.last?.method, .call)
        let same = Schedule.standing(p, events: events, now: day("2026-11-01", hour: 23), calendar: calendar)
        XCTAssertEqual(same.daysSince, 0)
        XCTAssertEqual(same.overdue, -7)
    }

    func testOrderingIsMostOverdueThenCreationOrder() {
        let a = person(7, created: "2026-01-01"), b = person(30, created: "2026-01-02"), c = person(7, created: "2026-01-03")
        let events = [ContactEvent(personID: a.id, occurredAt: day("2026-11-20"), method: .call),
                      ContactEvent(personID: b.id, occurredAt: day("2026-10-01"), method: .call),
                      ContactEvent(personID: c.id, occurredAt: day("2026-11-20"), method: .call)]
        let order = Schedule.ordered([c, a, b], events: events, now: day("2026-11-24"), calendar: calendar).map(\.id)
        XCTAssertEqual(order, [b.id, a.id, c.id])
    }

    func testDialAttemptOnlyLogsNewOutgoingConnectedCallOnce() {
        let before = UUID(), fresh = UUID(), other = UUID()
        var attempt = DialAttempt(personID: UUID(), started: day("2026-11-24"), before: [before])
        let t = day("2026-11-24").addingTimeInterval(20)
        XCTAssertFalse(attempt.observe(call: before, outgoing: true, connected: true, at: t), "已在进行的通话不算")
        XCTAssertFalse(attempt.observe(call: other, outgoing: false, connected: true, at: t), "来电不算")
        XCTAssertFalse(attempt.observe(call: fresh, outgoing: true, connected: false, at: t), "拨出未接通不记")
        XCTAssertTrue(attempt.observe(call: fresh, outgoing: true, connected: true, at: t))
        XCTAssertFalse(attempt.observe(call: fresh, outgoing: true, connected: true, at: t), "重复回调只记一次")
        var late = DialAttempt(personID: UUID(), started: day("2026-11-24"), before: [])
        XCTAssertFalse(late.observe(call: fresh, outgoing: true, connected: true, at: t.addingTimeInterval(3600)))
        var second = DialAttempt(personID: UUID(), started: day("2026-11-24"), before: [])
        XCTAssertFalse(second.observe(call: fresh, outgoing: true, connected: false, at: t))
        XCTAssertFalse(second.observe(call: other, outgoing: true, connected: true, at: t), "只认第一通新拨出")
    }

    func testHolidayDates() {
        XCTAssertEqual(Holidays.next("mothers", after: day("2026-01-01"), calendar: calendar), calendar.startOfDay(for: day("2026-05-10")))
        XCTAssertEqual(Holidays.next("fathers", after: day("2026-07-01"), calendar: calendar), calendar.startOfDay(for: day("2027-06-20")))
        XCTAssertEqual(Holidays.next("spring", after: day("2026-01-01"), calendar: calendar), calendar.startOfDay(for: day("2026-02-17")))
        XCTAssertEqual(Holidays.next("midautumn", after: day("2026-01-01"), calendar: calendar), calendar.startOfDay(for: day("2026-09-25")))
        XCTAssertEqual(Holidays.next("spring", after: day("2026-02-17"), calendar: calendar), calendar.startOfDay(for: day("2026-02-17")))
        XCTAssertEqual(Holidays.keys(for: .mother, chinese: true), ["mothers", "spring", "midautumn"])
        XCTAssertEqual(Holidays.keys(for: .friend, chinese: true), [])
        XCTAssertEqual(Holidays.keys(for: .father, chinese: false), ["fathers"])
        XCTAssertEqual(Holidays.nextBirthday(month: 3, day: 8, after: day("2026-11-24"), calendar: calendar),
                       calendar.startOfDay(for: day("2027-03-08")))
    }

    func testReminderPlansFireOnDueDayAndRollForward() {
        var data = AppData()
        let p = person(7)
        data.people = [p]
        data.events = [ContactEvent(personID: p.id, occurredAt: day("2026-11-01"), method: .call)]
        data.prefs.holidaysOn = false
        let plans = ReminderService.plans(data: data, now: day("2026-11-24", hour: 20), calendar: calendar, chinese: true, pro: false)
        XCTAssertEqual(plans.count, 1)
        XCTAssertEqual(plans[0].date, calendar.date(bySettingHour: 19, minute: 0, second: 0, of: day("2026-11-29")))
        data.people[0].extraHour = 9
        XCTAssertEqual(ReminderService.plans(data: data, now: day("2026-11-24", hour: 20), calendar: calendar, chinese: true, pro: true).count, 2)
        XCTAssertEqual(ReminderService.plans(data: data, now: day("2026-11-24", hour: 20), calendar: calendar, chinese: true, pro: false).count, 1)
        data.prefs.holidaysOn = true
        let withHolidays = ReminderService.plans(data: data, now: day("2026-11-24", hour: 20), calendar: calendar, chinese: true, pro: false)
        XCTAssertTrue(withHolidays.contains { $0.id.hasPrefix("kc.hol.mothers") })
        XCTAssertTrue(withHolidays.contains { $0.id.hasPrefix("kc.hol.spring") })
    }

    func testWeekendReminderMovesWeekdaysOnlyAndKeepsTheBaseCycle() {
        var data = AppData()
        data.prefs.holidaysOn = false
        var friday = person(7, created: "2026-11-27")
        friday.movesReminderToWeekend = true
        friday.extraHour = 20
        var sunday = person(7, created: "2026-11-29")
        sunday.movesReminderToWeekend = true
        let regular = person(7, created: "2026-11-27")
        data.people = [friday, sunday, regular]

        let now = day("2026-11-27")
        let primary = "kc.due." + friday.id.uuidString
        let second = "kc.due2." + friday.id.uuidString
        let trial = ReminderService.plans(data: data, now: now, calendar: calendar, chinese: false,
                                          pro: true, proUntil: day("2026-12-01"))
        XCTAssertEqual(trial.first { $0.id == primary }?.date, day("2026-11-28", hour: 19))
        XCTAssertEqual(trial.first { $0.id == second }?.date, day("2026-11-28", hour: 20))
        XCTAssertEqual(trial.first { $0.id == "kc.due." + sunday.id.uuidString }?.date, day("2026-11-29", hour: 19))
        XCTAssertEqual(trial.first { $0.id == "kc.due." + regular.id.uuidString }?.date, day("2026-11-27", hour: 19))
        XCTAssertEqual(Schedule.standing(friday, events: [], now: now, calendar: calendar).overdue, 0)

        let expired = ReminderService.plans(data: data, now: now, calendar: calendar, chinese: false, pro: false)
        XCTAssertEqual(expired.first { $0.id == primary }?.date, day("2026-11-27", hour: 19))
        XCTAssertFalse(expired.contains { $0.id == second })

        let rolled = ReminderService.plans(data: data, now: day("2026-11-28", hour: 21), calendar: calendar, chinese: false, pro: true)
        XCTAssertEqual(rolled.first { $0.id == primary }?.date, day("2026-12-05", hour: 19))
    }

    func testWeekendReminderHonorsSnoozeAndTrialCutoff() {
        var data = AppData()
        data.prefs.holidaysOn = false
        var p = person(7, created: "2026-11-24")
        p.movesReminderToWeekend = true
        p.extraHour = 20
        data.people = [p]

        func dates(now: Date? = nil, until: Date? = nil) -> [Date] {
            ReminderService.plans(data: data, now: now ?? day("2026-11-24"), calendar: calendar,
                                  chinese: false, pro: true, proUntil: until).map(\.date)
        }
        XCTAssertEqual(dates(until: day("2026-11-28", hour: 19)), [day("2026-11-24", hour: 19), day("2026-11-24", hour: 20)])
        XCTAssertEqual(dates(until: day("2026-11-28", hour: 20)), [day("2026-11-28", hour: 19)])

        data.people[0].snoozedUntil = day("2026-11-25", hour: 0)
        XCTAssertEqual(dates(now: day("2026-11-25")), [day("2026-11-25", hour: 19), day("2026-11-25", hour: 20)])
    }

    func testSettingsCodeRoundTripAndRejectsBadInput() {
        var prefs = Preferences()
        prefs.cycles[Relation.friend.rawValue] = 45
        prefs.hour = 20
        prefs.minute = 30
        let code = SettingsCode.encode(prefs)
        XCTAssertEqual(code, "KL1.P7G14S14K7F45O30T2030")
        let back = SettingsCode.decode(code.lowercased())
        XCTAssertEqual(back?.cycle(for: .friend), 45)
        XCTAssertEqual(back?.cycle(for: .father), 7)
        XCTAssertEqual(back?.hour, 20)
        XCTAssertEqual(back?.minute, 30)
        for bad in ["", "KL2.P7G14S14K7F45O30T2030", "KL1.P0G14S14K7F45O30T2030", "KL1.P7G14S14K7F45O30T2560",
                    "KL1.P7G14S14K7F45T2030", "KL1.P7G14S14K7F999O30T2030", String(repeating: "K", count: 100)] {
            XCTAssertNil(SettingsCode.decode(bad), bad)
        }
    }

    func testRelationGuess() {
        XCTAssertEqual(RelationGuess.guess("老妈"), .mother)
        XCTAssertEqual(RelationGuess.guess("妈妈 王秀兰"), .mother)
        XCTAssertEqual(RelationGuess.guess("姑妈"), .other)
        XCTAssertEqual(RelationGuess.guess("外婆"), .grandparent)
        XCTAssertEqual(RelationGuess.guess("Mom"), .mother)
        XCTAssertEqual(RelationGuess.guess("Thomas"), nil)
        XCTAssertEqual(RelationGuess.guess("Dad Work"), .father)
        XCTAssertEqual(RelationGuess.guess("二姐"), .sibling)
        XCTAssertNil(RelationGuess.guess("张伟"))
    }

    func testReviewNeedsThreeRecordsThreeDaysAndOneRequestPerVersion() {
        var review = ReviewProgress()
        let start = day("2026-11-01")
        let thirdDay = start.addingTimeInterval(3 * 86_400)
        review.installedAt = start
        review.records = 2
        XCTAssertFalse(review.ready(at: thirdDay, version: "1.0"))
        review.records += 1
        XCTAssertFalse(review.ready(at: thirdDay.addingTimeInterval(-1), version: "1.0"))
        XCTAssertTrue(review.ready(at: thirdDay, version: "1.0"))
        review.requested("1.0")
        XCTAssertFalse(review.ready(at: thirdDay.addingTimeInterval(400 * 86_400), version: "1.0"))
        XCTAssertTrue(review.ready(at: thirdDay, version: "1.1"))
        review.requested("1.1")
        XCTAssertFalse(review.ready(at: thirdDay, version: "1.0"))
        XCTAssertFalse(review.ready(at: thirdDay, version: "1.1"))
    }

    func testImportUpdatesInheritedCyclesAndPreservesExplicitAndLegacyOverrides() throws {
        var data = AppData()
        var inherited = person(7)
        inherited.customCycle = false
        var explicitSameAsDefault = person(7)
        explicitSameAsDefault.customCycle = true
        let legacyCustom = person(17)
        let legacyDefault = person(7)
        data.people = [inherited, explicitSameAsDefault, legacyCustom, legacyDefault]
        data.prefs.remindersOn = true
        data.prefs.hideWidgetNames = true
        let incoming = try XCTUnwrap(SettingsCode.decode("KL1.P5G10S14K7F30O30T2000"))
        data.applySettingsCode(incoming)
        XCTAssertEqual(data.people.map(\.cycleDays), [5, 7, 17, 5])
        XCTAssertEqual(data.people.map(\.customCycle), [false, true, true, false])
        XCTAssertEqual(data.prefs.hour, 20)
        XCTAssertTrue(data.prefs.remindersOn)
        XCTAssertEqual(data.prefs.hideWidgetNames, true)
        data.applySettingsCode(Preferences())
        XCTAssertEqual(data.people.map(\.cycleDays), [7, 7, 17, 7])
    }

    func testPhotoPromptDismissalIsPerPersonAndLastsThirtyDays() throws {
        let dismissedAt = day("2026-10-25", hour: 15)
        var first = person(7)
        let second = person(7)
        let legacy = try JSONDecoder().decode(Person.self, from: JSONEncoder().encode(first))
        XCTAssertNil(legacy.photoPromptDismissedAt)
        XCTAssertTrue(legacy.allowsPhotoPrompt(at: dismissedAt, calendar: calendar))

        first.photoPromptDismissedAt = dismissedAt
        var data = AppData()
        data.people = [first, second]
        let restored = try JSONDecoder().decode(AppData.self, from: JSONEncoder().encode(data))
        let boundary = day("2026-11-24", hour: 15)
        XCTAssertFalse(restored.people[0].allowsPhotoPrompt(at: dismissedAt, calendar: calendar))
        XCTAssertFalse(restored.people[0].allowsPhotoPrompt(at: boundary.addingTimeInterval(-1), calendar: calendar))
        XCTAssertTrue(restored.people[0].allowsPhotoPrompt(at: boundary, calendar: calendar))
        XCTAssertTrue(restored.people[1].allowsPhotoPrompt(at: dismissedAt, calendar: calendar))
    }

    func testPhotoAgeUsesWholeCalendarMonthsAndClampsFutureDates() {
        let taken = day("2025-12-17", hour: 23)
        XCTAssertEqual(Schedule.months(from: taken, to: day("2025-12-17", hour: 1), calendar: calendar), 0)
        XCTAssertEqual(Schedule.months(from: taken, to: day("2026-01-16"), calendar: calendar), 0)
        XCTAssertEqual(Schedule.months(from: taken, to: day("2026-01-17", hour: 1), calendar: calendar), 1)
        XCTAssertEqual(Schedule.months(from: taken, to: day("2026-06-18"), calendar: calendar), 6)
        XCTAssertEqual(Schedule.months(from: taken, to: day("2025-09-01"), calendar: calendar), 0)
        XCTAssertFalse(Schedule.isPhotoOlderThanSixMonths(taken, now: day("2026-06-16"), calendar: calendar))
        XCTAssertFalse(Schedule.isPhotoOlderThanSixMonths(taken, now: day("2026-06-17"), calendar: calendar))
        XCTAssertTrue(Schedule.isPhotoOlderThanSixMonths(taken, now: day("2026-06-18"), calendar: calendar))
    }

    func testThreePhotoMilestoneIsPerPersonAndPersists() throws {
        var data = AppData()
        let first = person(7), second = person(14)
        data.people = [first, second]
        for owner in [first, second] {
            for _ in 0..<2 {
                data.photos.append(PhotoEntry(personID: owner.id, takenAt: day("2026-11-01"),
                                              dateFromFile: false, addedAt: day("2026-11-01"), file: "sample.jpg"))
            }
        }
        XCTAssertFalse(data.showsPhotoMilestone(for: first))
        data.photos.append(PhotoEntry(personID: first.id, takenAt: day("2026-11-02"),
                                      dateFromFile: false, addedAt: day("2026-11-02"), file: "third.jpg"))
        XCTAssertTrue(data.showsPhotoMilestone(for: first))
        XCTAssertFalse(data.showsPhotoMilestone(for: second))
        data.milestones.append(data.photoMilestoneKey(for: first))
        let restored = try JSONDecoder().decode(AppData.self, from: JSONEncoder().encode(data))
        XCTAssertFalse(restored.showsPhotoMilestone(for: first))
    }

    func testSharingUsesNicknamesAndFallsBackForImportedNamesAndNumbers() {
        var linked = person(7)
        linked.contactID = "contact"
        linked.nickname = "Linda Chen"
        XCTAssertEqual(linked.shareName, linked.relation.callName)
        linked.usesContactName = true
        XCTAssertEqual(linked.shareName, linked.relation.callName)
        linked.usesContactName = false
        linked.nickname = "Mum"
        XCTAssertEqual(linked.shareName, "Mum")
        linked.nickname = "+1 (555) 1234"
        XCTAssertEqual(linked.shareName, linked.relation.callName)
    }

    func testMonthlySummaryDeduplicatesPeopleAndUsesLastContactInsteadOfOverdue() {
        var data = AppData()
        let older = person(90), moreOverdue = person(3), never = person(7)
        data.people = [moreOverdue, older, never]
        data.events = [
            ContactEvent(personID: older.id, occurredAt: day("2026-10-27"), method: .call),
            ContactEvent(personID: moreOverdue.id, occurredAt: day("2026-11-05"), method: .faceTime),
            ContactEvent(personID: moreOverdue.id, occurredAt: day("2026-11-07"), method: .visit),
            ContactEvent(personID: older.id, occurredAt: day("2026-12-01"), method: .call)
        ]
        let now = day("2026-11-24")
        XCTAssertEqual(Schedule.ordered(data.people, events: Array(data.events.prefix(3)),
                                        now: now, calendar: calendar).first?.id, never.id)
        let summary = MonthlySummary(data: data, now: now, calendar: calendar)
        XCTAssertEqual(summary.people.map(\.id), [moreOverdue.id])
        XCTAssertEqual(summary.longest?.person.id, older.id)
        XCTAssertEqual(summary.longest?.days, 28)
        XCTAssertEqual(summary.calls, 1)
        XCTAssertEqual(summary.visits, 1)
    }

    func testBackupJSONRoundTripsDataAndBase64AndRejectsInvalidReferences() throws {
        var data = AppData()
        let owner = person(42)
        let photoFile = UUID().uuidString + ".jpg"
        data.people = [owner]
        data.events = [ContactEvent(personID: owner.id, occurredAt: day("2026-11-02"), method: .faceTime)]
        data.photos = [PhotoEntry(personID: owner.id, takenAt: day("2026-11-02"), dateFromFile: true,
                                  addedAt: day("2026-11-03"), file: photoFile)]
        data.review.records = 9
        data.prefs.hideWidgetNames = true
        let photo = Data([0xff, 0xd8, 0xff, 0xd9])
        let archive = BackupArchive(data: data, photoBytes: [photoFile: photo])
        let raw = try JSONEncoder().encode(archive)
        let fields = try XCTUnwrap(JSONSerialization.jsonObject(with: raw) as? [String: Any])
        XCTAssertEqual((fields["photoBytes"] as? [String: String])?[photoFile], photo.base64EncodedString())
        let copy = try JSONDecoder().decode(BackupArchive.self, from: raw)
        XCTAssertNoThrow(try copy.validate())
        XCTAssertEqual(copy.data.people, data.people)
        XCTAssertEqual(copy.data.events, data.events)
        XCTAssertEqual(copy.data.photos, data.photos)
        XCTAssertEqual(copy.data.prefs, data.prefs)
        XCTAssertEqual(copy.data.review.records, 0)
        XCTAssertEqual(copy.photoBytes[photoFile], photo)
        XCTAssertThrowsError(try BackupArchive(data: data, photoBytes: [:]).validate())
        data.photos[0].file = "../" + photoFile
        XCTAssertThrowsError(try BackupArchive(data: data, photoBytes: [data.photos[0].file: photo]).validate())
        data.photos[0].file = photoFile
        data.events[0].personID = UUID()
        XCTAssertThrowsError(try BackupArchive(data: data, photoBytes: [photoFile: photo]).validate())
    }

    func testEntitlementTrialAndPurchase() {
        let start = day("2026-11-01")
        var e = Entitlement(firstOpen: start)
        XCTAssertTrue(e.hasPro(at: start.addingTimeInterval(29 * 86_400), free: false))
        XCTAssertFalse(e.hasPro(at: start.addingTimeInterval(31 * 86_400), free: false))
        XCTAssertEqual(e.trialDaysLeft(at: start.addingTimeInterval(20 * 86_400)), 10)
        e.purchasedPro = true
        XCTAssertTrue(e.hasPro(at: start.addingTimeInterval(400 * 86_400), free: false))
        XCTAssertFalse(Launch.freePeriod)
    }

    func testTrialExpiryNoticeEligibilityStartsAtTheCutoff() {
        var e = Entitlement(firstOpen: day("2026-11-01"))
        XCTAssertFalse(e.hasExpiredTrial(at: e.trialEnd.addingTimeInterval(-1), free: false))
        XCTAssertTrue(e.hasExpiredTrial(at: e.trialEnd, free: false))
        XCTAssertFalse(e.hasExpiredTrial(at: e.trialEnd, free: true))
        e.purchasedPro = true
        XCTAssertFalse(e.hasExpiredTrial(at: e.trialEnd, free: false))
    }

    func testWeekendRuleRoundTripsAndOlderDataDefaultsToOff() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        var p = person(7)
        let oldData = try encoder.encode(p)
        XCTAssertNil(try decoder.decode(Person.self, from: oldData).movesReminderToWeekend)
        p.movesReminderToWeekend = true
        XCTAssertEqual(try decoder.decode(Person.self, from: encoder.encode(p)), p)
    }

    func testDataRoundTripsThroughJSON() throws {
        var data = AppData()
        let p = person(7)
        data.people = [p]
        data.events = [ContactEvent(personID: p.id, occurredAt: day("2026-11-01"), method: .wechat, automatic: true, session: UUID())]
        data.photos = [PhotoEntry(personID: p.id, takenAt: day("2026-02-17"), dateFromFile: true, addedAt: day("2026-11-01"), file: "a.jpg")]
        let back = try JSONDecoder().decode(AppData.self, from: JSONEncoder().encode(data))
        XCTAssertEqual(back, data)
    }

    func testWidgetCardStandingMatchesSchedule() {
        let card = WidgetSnapshot.Card(id: UUID(), name: "老妈", last: day("2026-11-12"), created: day("2026-01-01"), cycle: 7)
        XCTAssertEqual(card.standing(now: day("2026-11-24"), calendar: calendar).daysSince, 12)
        let snapshot = WidgetSnapshot(cards: [
            WidgetSnapshot.Card(id: UUID(), name: "A", last: day("2026-11-23"), created: day("2026-01-01"), cycle: 7), card
        ], showNames: true)
        XCTAssertEqual(snapshot.ordered(now: day("2026-11-24"), calendar: calendar).first?.name, "老妈")
    }

    func testLocalizedStringsExistInAllLanguages() {
        for key in ["home.title", "status.days", "share.hashtag", "relation.call.mother", "notify.due"] {
            XCTAssertNotEqual(L.t(key), key, key)
        }
    }
}
