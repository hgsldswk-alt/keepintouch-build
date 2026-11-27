import CallKit
import Contacts
import ContactsUI
import Foundation
import MessageUI
import SwiftUI
import UIKit
import UserNotifications

struct ContactInfo: Equatable, Sendable {
    var name: String
    var phones: [String]
    var thumbnail: Data?
    var birthday: DateComponents?
}

struct Suggestion: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let relation: Relation
    var thumbnail: Data?
    var birthday: DateComponents?
    var picked = true
}


enum ContactsService {
    static var authorized: Bool {
        let status = CNContactStore.authorizationStatus(for: .contacts)
        if #available(iOS 18.0, *), status == .limited { return true }
        return status == .authorized
    }

    static func request() async -> Bool {
        do { return try await CNContactStore().requestAccess(for: .contacts) }
        catch { return false }
    }

    private static let keys: [CNKeyDescriptor] = [
        CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
        CNContactNicknameKey as CNKeyDescriptor,
        CNContactPhoneNumbersKey as CNKeyDescriptor,
        CNContactThumbnailImageDataKey as CNKeyDescriptor,
        CNContactBirthdayKey as CNKeyDescriptor
    ]

    private static func info(_ contact: CNContact) -> ContactInfo {
        let mobile = contact.phoneNumbers.filter {
            [CNLabelPhoneNumberMobile, CNLabelPhoneNumberiPhone].contains($0.label ?? "")
        }
        let numbers = (mobile + contact.phoneNumbers.filter { !mobile.contains($0) })
            .map(\.value.stringValue).filter { $0.contains(where: \.isNumber) }
        let name = CNContactFormatter.string(from: contact, style: .fullName) ?? contact.nickname
        return ContactInfo(name: name, phones: numbers, thumbnail: contact.thumbnailImageData,
                           birthday: contact.birthday.map { DateComponents(month: $0.month, day: $0.day) })
    }

    static func info(_ ids: [String]) async -> [String: ContactInfo] {
        await Task.detached(priority: .userInitiated) {
            let store = CNContactStore()
            var result: [String: ContactInfo] = [:]
            let request = CNContactFetchRequest(keysToFetch: keys)
            request.predicate = CNContact.predicateForContacts(withIdentifiers: ids)
            try? store.enumerateContacts(with: request) { contact, _ in result[contact.identifier] = info(contact) }
            return result
        }.value
    }

    static func suggestions(excluding: Set<String>) async -> [Suggestion] {
        await Task.detached(priority: .userInitiated) {
            let store = CNContactStore()
            var found: [Suggestion] = []
            let request = CNContactFetchRequest(keysToFetch: keys)
            try? store.enumerateContacts(with: request) { contact, stop in
                guard !excluding.contains(contact.identifier), !contact.phoneNumbers.isEmpty else { return }
                let text = [contact.nickname, contact.givenName, contact.familyName, contact.middleName].joined(separator: " ")
                guard let relation = RelationGuess.guess(text) else { return }
                let value = info(contact)
                found.append(Suggestion(id: contact.identifier, name: value.name, relation: relation,
                                        thumbnail: value.thumbnail, birthday: value.birthday))
                if found.count >= 12 { stop.pointee = true }
            }
            let rank: [Relation] = [.mother, .father, .grandparent, .sibling, .child, .other, .friend]
            return found.sorted { (rank.firstIndex(of: $0.relation) ?? 9) < (rank.firstIndex(of: $1.relation) ?? 9) }
        }.value
    }

    static func picked(_ contact: CNContact) -> (id: String, info: ContactInfo) {
        (contact.identifier, info(contact))
    }
}

final class ContactPicker: NSObject, CNContactPickerDelegate {
    static let shared = ContactPicker()
    private var completion: ((CNContact?) -> Void)?

    func present(_ completion: @escaping (CNContact?) -> Void) {
        guard let host = UIApplication.shared.topController else { completion(nil); return }
        self.completion = completion
        let picker = CNContactPickerViewController()
        picker.delegate = self
        picker.predicateForEnablingContact = NSPredicate(format: "phoneNumbers.@count > 0")
        host.present(picker, animated: true)
    }

    func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
        completion?(contact)
        completion = nil
    }

    func contactPickerDidCancel(_ picker: CNContactPickerViewController) {
        completion?(nil)
        completion = nil
    }
}

final class MessageComposer: NSObject, MFMessageComposeViewControllerDelegate {
    static let shared = MessageComposer()
    private var completion: ((Bool) -> Void)?

    static var available: Bool { MFMessageComposeViewController.canSendText() }

    func present(to number: String, _ completion: @escaping (Bool) -> Void) {
        self.completion = completion
        let controller = MFMessageComposeViewController()
        controller.recipients = [number]
        controller.messageComposeDelegate = self
        UIApplication.shared.topController?.present(controller, animated: true)
    }

    func messageComposeViewController(_ controller: MFMessageComposeViewController, didFinishWith result: MessageComposeResult) {
        controller.dismiss(animated: true)
        completion?(result == .sent)
        completion = nil
    }
}

extension UIApplication {
    var topController: UIViewController? {
        let scene = connectedScenes.compactMap { $0 as? UIWindowScene }.first { $0.activationState == .foregroundActive }
            ?? connectedScenes.compactMap { $0 as? UIWindowScene }.first
        var top = scene?.windows.first { $0.isKeyWindow }?.rootViewController ?? scene?.windows.first?.rootViewController
        while let next = top?.presentedViewController { top = next }
        return top
    }
}


final class CallWatcher: NSObject, CXCallObserverDelegate {
    private let observer = CXCallObserver()
    private(set) var attempt: DialAttempt?
    var onConnected: ((UUID, UUID, Date) -> Void)?

    override init() {
        super.init()
        observer.setDelegate(self, queue: .main)
    }

    func begin(person: UUID, now: Date) {
        attempt = DialAttempt(personID: person, started: now, before: Set(observer.calls.map(\.uuid)))
    }

    func cancel() { attempt = nil }

    func callObserver(_ callObserver: CXCallObserver, callChanged call: CXCall) {
        evaluate(call, now: Date())
    }

    private func evaluate(_ call: CXCall, now: Date) {
        guard var value = attempt else { return }
        if value.observe(call: call.uuid, outgoing: call.isOutgoing, connected: call.hasConnected, at: now) {
            attempt = value
            onConnected?(value.personID, value.session, now)
        } else {
            attempt = value
        }
    }

    func resume(now: Date) -> UUID? {
        for call in observer.calls { evaluate(call, now: Date()) }
        guard let value = attempt else { return nil }
        if value.consumed { attempt = nil; return nil }
        guard now.timeIntervalSince(value.started) > 3 else { return nil }
        if observer.calls.contains(where: { $0.uuid == value.matched && !$0.hasEnded }) { return nil }
        attempt = nil
        return value.personID
    }
}


actor ReminderService {
    private let center = UNUserNotificationCenter.current()
    private let prefix = "kc."

    func requestIfNeeded() async {
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
        }
    }

    struct Plan: Equatable {
        let id: String
        let date: Date
        let body: String
    }

    static func plans(data: AppData, now: Date, calendar: Calendar, chinese: Bool, pro: Bool, proUntil: Date? = nil) -> [Plan] {
        let prefs = data.prefs
        func at(_ day: Date, hour: Int? = nil, minute: Int? = nil) -> Date {
            calendar.date(bySettingHour: hour ?? prefs.hour, minute: minute ?? prefs.minute, second: 0, of: day) ?? day
        }
        func allowsPro(at date: Date) -> Bool {
            pro && (proUntil.map { date < $0 } ?? true)
        }
        var plans: [Plan] = []
        for person in data.people {
            let standing = Schedule.standing(person, events: data.events, now: now, calendar: calendar)
            let snooze = person.snoozedUntil.map { calendar.startOfDay(for: $0) }.flatMap { at($0) > now ? $0 : nil }
            func reminderDay(_ day: Date) -> Date {
                guard pro, person.movesReminderToWeekend == true, day != snooze else { return day }
                let weekday = calendar.component(.weekday, from: day)
                guard (2...6).contains(weekday),
                      let saturday = calendar.date(byAdding: .day, value: 7 - weekday, to: day),
                      allowsPro(at: at(saturday)) else { return day }
                return saturday
            }
            var cycleDay = max(standing.due, snooze ?? standing.due)
            var day = reminderDay(cycleDay)
            var fire = at(day)
            var guardCount = 0
            while fire <= now && guardCount < 400 {
                cycleDay = calendar.date(byAdding: .day, value: max(1, person.cycleDays), to: cycleDay) ?? cycleDay
                day = reminderDay(cycleDay)
                fire = at(day)
                guardCount += 1
            }
            plans.append(Plan(id: "kc.due." + person.id.uuidString, date: fire, body: L.f("notify.due", person.displayName)))
            if pro, let extra = person.extraHour {
                let second = at(day, hour: extra, minute: 0)
                if second > now && second != fire && allowsPro(at: second) {
                    plans.append(Plan(id: "kc.due2." + person.id.uuidString, date: second, body: L.f("notify.due", person.displayName)))
                }
            }
            if let month = person.birthMonth, let dayOfMonth = person.birthDay,
               let birthday = Holidays.nextBirthday(month: month, day: dayOfMonth, after: now, calendar: calendar),
               let eve = calendar.date(byAdding: .day, value: -1, to: birthday), at(eve) > now {
                plans.append(Plan(id: "kc.bday." + person.id.uuidString, date: at(eve), body: L.f("notify.birthday", person.displayName)))
            }
        }
        if prefs.holidaysOn {
            var holidays: [String: [String]] = [:]
            for person in data.people {
                for key in Holidays.keys(for: person.relation, chinese: chinese) { holidays[key, default: []].append(person.displayName) }
            }
            for (key, names) in holidays {
                guard let date = Holidays.next(key, after: now, calendar: calendar),
                      let eve = calendar.date(byAdding: .day, value: -1, to: date), at(eve) > now else { continue }
                let year = calendar.component(.year, from: date)
                plans.append(Plan(id: "kc.hol.\(key).\(year)", date: at(eve),
                                  body: L.f("notify.holiday", L.t("holiday." + key), names.prefix(3).joined(separator: "、"))))
            }
        }
        return plans.sorted { $0.date == $1.date ? $0.id < $1.id : $0.date < $1.date }
    }

    func reconcile(data: AppData, now: Date, calendar: Calendar, testing: Bool) async {
        guard !testing else { return }
        let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix) }
        guard data.prefs.remindersOn else {
            center.removePendingNotificationRequests(withIdentifiers: pending)
            return
        }
        let settings = await center.notificationSettings()
        guard [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus) else { return }
        let entitlement = await Purchases.shared.entitlement
        let pro = entitlement?.hasPro(at: now) ?? Launch.isFree
        let proUntil = Launch.isFree || entitlement?.purchasedPro == true ? nil : entitlement?.trialEnd
        let plans = Self.plans(data: data, now: now, calendar: calendar, chinese: L.chinese, pro: pro, proUntil: proUntil).prefix(60)
        center.removePendingNotificationRequests(withIdentifiers: pending)
        for plan in plans {
            let content = UNMutableNotificationContent()
            content.title = L.t("notify.title")
            content.body = plan.body
            content.sound = .default
            let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: plan.date)
            let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: plan.id, content: content, trigger: trigger))
        }
    }
}
