import SwiftUI
import UIKit

struct RecordRoute: Identifiable {
    let id = UUID()
    let event: ContactEvent?
}

struct PersonDetail: View {
    @ObservedObject var model: AppModel
    let person: Person
    let back: () -> Void
    let edit: () -> Void
    let share: (Bool) -> Void
    let addPhoto: () -> Void
    let takePhoto: () -> Void

    @State private var record: RecordRoute?
    @State private var viewing: PhotoEntry?
    @State private var showingMilestone = false
    @State private var milestoneClosed = false
    @State private var viewportHeight: CGFloat = 0

    private var photos: [PhotoEntry] { model.photos(of: person) }
    private var highlightAddPhoto: Bool {
        guard let latest = photos.first else { return false }
        return Schedule.isPhotoOlderThanSixMonths(latest.takenAt, now: model.now, calendar: model.calendar)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                nav
                VStack(spacing: 12) {
                    status
                    actions
                }
                cover
                records
                timeline
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 18)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .coordinateSpace(name: "detailScroll")
        .background(Palette.paper.ignoresSafeArea())
        .overlay(alignment: .top) {
            GeometryReader { g in
                Palette.paper.opacity(0.97)
                    .frame(height: g.safeAreaInsets.top)
                    .offset(y: -g.safeAreaInsets.top)
            }
            .allowsHitTesting(false)
        }
        .background {
            GeometryReader { geometry in
                Color.clear.onChange(of: geometry.size.height, initial: true) { _, height in viewportHeight = height }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                ToastBar(model: model)
                if model.photoPrompt?.personID == person.id { visitHint }
            }
        }
        .sheet(item: $record) { route in RecordEditor(model: model, person: person, event: route.event) }
        .sheet(item: $viewing) { entry in PhotoViewer(model: model, entry: entry) }
    }

    private var nav: some View {
        HStack {
            Button(action: back) { Label(L.t("common.back"), systemImage: "chevron.left").frame(minHeight: 44) }
                .accessibilityIdentifier("detail.back")
            Spacer()
            Button(action: edit) {
                Label(L.t("common.edit"), systemImage: "pencil")
                    .padding(.horizontal, 12).frame(minHeight: 44)
                    .foregroundStyle(Palette.accentText)
                    .background(Palette.pale, in: RoundedRectangle(cornerRadius: 14))
                    .contentShape(Rectangle())
            }
            .accessibilityIdentifier("detail.edit")
        }
        .font(.body.weight(.semibold))
    }

    @ViewBuilder
    private var cover: some View {
        if let latest = photos.first {
            Button { viewing = latest } label: {
                PhotoTile(image: model.image(latest, thumbnail: false), height: 230)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L.f("photo.view", L.day(latest.takenAt, "yMMMd")))
        } else {
            Button { addPhoto() } label: { EmptyFrame() }
                .buttonStyle(.plain)
                .accessibilityIdentifier("detail.cover.add")
        }
    }

    private var status: some View {
        let avatar = ContactAvatar(image: model.avatar(person), person: person, standing: model.standing(person), size: 58)
        return HeroCard {
            HStack(alignment: .top, spacing: 12) {
                avatar
                VStack(alignment: .leading, spacing: 5) {
                    Text(person.displayName).font(.title2.bold())
                    Text(model.statusLine(person)).font(.system(.title3, design: .rounded).bold()).monospacedDigit()
                        .accessibilityIdentifier("detail.status")
                    StatusPill(text: L.f("detail.cycle", person.cycleDays), color: avatar.statusColor)
                    Text(L.f("detail.due-date", L.day(model.standing(person).due, "yMMMd")))
                        .font(.caption).foregroundStyle(Palette.muted)
                        .accessibilityIdentifier("detail.due-date")
                    Text(model.lastLine(person)).font(.subheadline).foregroundStyle(Palette.muted)
                    Text(model.photoLine(photos.first)).font(.subheadline).foregroundStyle(Palette.accentText)
                        .accessibilityIdentifier("detail.photo.age")
                    if let info = model.info(person), info.name != person.displayName {
                        Text(info.name).font(.caption).foregroundStyle(Palette.muted)
                    }
                    if !person.note.isEmpty { Text(person.note).font(.subheadline).padding(.top, 2) }
                }
            }
        }
    }

    private var actions: some View {
        VStack(spacing: 10) {
            VStack(spacing: 8) {
                CallButton(model: model, person: person, identifier: "detail.call")
                Button { model.record(person.id, method: .visit) } label: {
                    Label(L.t("action.visit"), systemImage: ContactMethod.visit.symbol)
                }
                    .buttonStyle(PrimaryButton(filled: false))
                    .accessibilityIdentifier("detail.visit")
            }
            HStack(spacing: 10) {
                Button { sendMessage() } label: { Label(L.t("action.sms"), systemImage: ContactMethod.sms.symbol) }
                    .buttonStyle(PrimaryButton(filled: false))
                    .accessibilityIdentifier("detail.sms")
                Button { model.openExternal(person, method: .wechat) } label: {
                    Label(L.t("action.wechat"), systemImage: ContactMethod.wechat.symbol)
                }
                    .buttonStyle(PrimaryButton(filled: false))
                    .accessibilityIdentifier("detail.wechat")
                Button { model.faceTime(person) } label: {
                    Label(L.t("action.facetime"), systemImage: ContactMethod.faceTime.symbol)
                }
                    .buttonStyle(PrimaryButton(filled: false))
                    .disabled(model.phones(person).isEmpty)
                    .accessibilityIdentifier("detail.facetime")
            }
            HStack {
                Button { model.snooze(person) } label: { Label(L.t("action.snooze"), systemImage: "clock") }
                    .buttonStyle(PrimaryButton(filled: false))
                    .accessibilityIdentifier("detail.snooze")
            }
            if let candidate = model.candidate, candidate.personID == person.id {
                CandidatePrompt(model: model, person: person, method: candidate.method)
            }
        }
    }

    private var visitHint: some View {
        HStack(alignment: .top, spacing: 4) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { visitHintContent }
                    .fixedSize(horizontal: true, vertical: false)
                VStack(alignment: .leading, spacing: 4) { visitHintContent }
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            Button { model.dismissPhotoPrompt(for: person.id) } label: {
                Image(systemName: "xmark").font(.subheadline.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Palette.accentText)
            .accessibilityLabel(L.t("common.close"))
            .accessibilityIdentifier("detail.hint.close")
        }
        .padding(.leading, 14).padding(.trailing, 4).padding(.vertical, 4)
        .background(Palette.pale, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 16).padding(.bottom, 8)
        .frame(maxWidth: 560)
    }

    @ViewBuilder private var visitHintContent: some View {
        Text(L.t("photo.visit-hint")).font(.subheadline.weight(.semibold))
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("detail.hint.title")
        Button(action: takePhoto) {
            Label(L.t("photo.camera"), systemImage: "camera.fill").font(.subheadline.weight(.semibold))
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Palette.accentText)
        .accessibilityIdentifier("detail.hint.camera")
    }

    private var records: some View {
        let list = model.events(of: person)
        return VStack(alignment: .leading, spacing: 10) {
            Text(L.t("detail.records")).sectionTitle()
            if list.isEmpty {
                VStack(spacing: 8) {
                    EmptyIllustration(symbol: "clock.arrow.circlepath")
                    Text(L.t("status.no-record")).font(.subheadline).foregroundStyle(Palette.muted)
                }
                .frame(maxWidth: .infinity)
            }
            Button { record = RecordRoute(event: nil) } label: {
                Label(L.t("detail.backfill"), systemImage: "plus.circle")
            }
            .buttonStyle(PrimaryButton(filled: list.isEmpty))
            .accessibilityIdentifier("detail.backfill")
            ForEach(list.prefix(12)) { event in
                Button { record = RecordRoute(event: event) } label: {
                    IconRow(title: event.method.label, subtitle: L.day(event.occurredAt, "yMMMd"),
                            symbol: event.method.symbol, color: event.method.iconColor,
                            pill: event.automatic ? L.t("record.auto") : nil)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("detail.record")
            }
        }
        .cardStyle()
    }

    private var timeline: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L.t("detail.timeline")).sectionTitle()
                Spacer()
                let highlighted = highlightAddPhoto
                Button(action: addPhoto) {
                    Label(L.t("photo.add"), systemImage: "photo.badge.plus").font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 10)
                        .frame(minHeight: 44)
                        .foregroundStyle(highlighted ? Palette.onAccent : Palette.accentText)
                        .background(highlighted ? Palette.accent : Palette.pale, in: RoundedRectangle(cornerRadius: 14))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("detail.photo.add")
            }
            if !photos.isEmpty {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                    ForEach(photos) { entry in
                        Button { viewing = entry } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                PhotoTile(image: model.image(entry), height: 96)
                                Text(L.day(entry.takenAt, "yMMMd")).font(.caption2.weight(.semibold)).foregroundStyle(Palette.muted)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("detail.photo")
                    }
                }
                if !milestoneClosed, photos.count >= 3, showingMilestone || model.data.showsPhotoMilestone(for: person) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            IconBadge(symbol: "sparkles", color: Palette.butter)
                            Text(L.f("milestone.three", person.displayName)).font(.subheadline.weight(.semibold))
                            Spacer(minLength: 0)
                            Button(action: closeMilestone) {
                                Image(systemName: "xmark").frame(width: 44, height: 44).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(Palette.muted)
                            .accessibilityLabel(L.t("common.close"))
                            .accessibilityIdentifier("milestone.close")
                        }
                        Button { closeMilestone(); share(true) } label: {
                            Label(L.t("milestone.make"), systemImage: "wand.and.stars")
                        }
                        .buttonStyle(PrimaryButton(filled: false))
                        .accessibilityIdentifier("milestone.make")
                    }
                    .padding(12)
                    .background(Palette.warm, in: RoundedRectangle(cornerRadius: 14))
                    .background {
                        GeometryReader { geometry in
                            let frame = geometry.frame(in: .named("detailScroll"))
                            let visible = min(frame.maxY, viewportHeight) - max(frame.minY, 0) >= frame.height / 2 && frame.height > 0
                            Color.clear.onChange(of: visible, initial: true) { _, visible in
                                guard visible, !showingMilestone else { return }
                                showingMilestone = true
                                model.markMilestone(model.data.photoMilestoneKey(for: person))
                            }
                        }
                    }
                }
                Button { share(false) } label: { Label(L.t("share.timeline"), systemImage: "square.and.arrow.up") }
                    .buttonStyle(PrimaryButton(filled: false))
                    .accessibilityIdentifier("detail.share")
            }
        }
        .cardStyle()
    }

    private func closeMilestone() {
        model.markMilestone(model.data.photoMilestoneKey(for: person))
        milestoneClosed = true
    }

    private func sendMessage() {
        guard let number = model.phones(person).first else { model.message = L.t("call.no-number"); return }
        if MessageComposer.available && !model.testing {
            MessageComposer.shared.present(to: number) { sent in
                Task { @MainActor in if sent { model.record(person.id, method: .sms, automatic: true) } }
            }
        } else {
            model.openExternal(person, method: .sms)
        }
    }
}

struct RecordEditor: View {
    @ObservedObject var model: AppModel
    let person: Person
    let event: ContactEvent?
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date()
    @State private var method: ContactMethod = .call

    var body: some View {
        NavigationStack {
            Form {
                DatePicker(selection: $date, in: ...model.now, displayedComponents: .date) {
                    Label(L.t("record.date"), systemImage: "calendar")
                }
                Picker(selection: $method) {
                    ForEach(ContactMethod.allCases, id: \.self) { Label($0.label, systemImage: $0.symbol).tag($0) }
                } label: {
                    Label(L.t("record.method"), systemImage: "bubble.left")
                }
                if let event {
                    Button(L.t("record.delete"), role: .destructive) { model.deleteEvent(event.id); dismiss() }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Palette.paper.ignoresSafeArea())
            .tint(Palette.accentText)
            .navigationTitle(L.t(event == nil ? "detail.backfill" : "record.edit"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L.t("common.cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L.t("common.save")) {
                        if var event {
                            event.occurredAt = date
                            event.method = method
                            model.updateEvent(event)
                        } else {
                            model.record(person.id, method: method, at: date)
                        }
                        dismiss()
                    }
                    .accessibilityIdentifier("record.save")
                }
            }
            .onAppear {
                date = event?.occurredAt ?? model.now
                method = event?.method ?? .call
            }
        }
        .presentationDetents([.medium])
    }
}

struct PhotoViewer: View {
    @ObservedObject var model: AppModel
    let entry: PhotoEntry
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date()

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if let image = model.image(entry, thumbnail: false) {
                    Image(uiImage: image).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 14))
                }
                DatePicker(selection: $date, in: ...model.now, displayedComponents: .date) {
                    Label(L.t("photo.date"), systemImage: "calendar")
                }
                .cardStyle()
                Button(L.t("photo.delete"), role: .destructive) { model.deletePhoto(entry); dismiss() }
                Spacer()
            }
            .padding()
            .background(Palette.paper.ignoresSafeArea())
            .tint(Palette.accentText)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L.t("common.done")) {
                        if !Calendar.current.isDate(date, inSameDayAs: entry.takenAt) { model.setPhotoDate(entry, date) }
                        dismiss()
                    }
                }
            }
            .onAppear { date = entry.takenAt }
        }
    }
}

struct CameraView: UIViewControllerRepresentable {
    let done: (UIImage?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(done: done) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let done: (UIImage?) -> Void
        init(done: @escaping (UIImage?) -> Void) { self.done = done }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            done(info[.originalImage] as? UIImage)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { done(nil) }
    }
}
