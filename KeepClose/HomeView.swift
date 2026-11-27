import SwiftUI
import UIKit

struct HomeView: View {
    @ObservedObject var model: AppModel
    let open: (Person) -> Void
    let manual: () -> Void
    let more: () -> Void
    let addPhoto: (Person) -> Void
    @Binding var pickingContact: Bool
    let showExpiryNotice: Bool
    let expiryNoticeAppeared: () -> Void
    let dismissExpiryNotice: () -> Void
    let unlock: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                if showExpiryNotice { expiryNotice.onAppear(perform: expiryNoticeAppeared) }
                if !model.suggestions.isEmpty { SuggestionPanel(model: model) }
                if let candidate = model.candidate, let person = model.person(candidate.personID) {
                    CandidatePrompt(model: model, person: person, method: candidate.method)
                }
                if model.data.people.isEmpty && model.suggestions.isEmpty { empty }
                let people = model.ordered
                ForEach(people) { person in
                    PersonCard(model: model, person: person, featured: person.id == people.first?.id,
                               open: { open(person) }, addPhoto: { addPhoto(person) })
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .padding(.bottom, 90)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .background(Palette.paper.ignoresSafeArea())
        .overlay(alignment: .bottom) { ToastBar(model: model) }
    }

    private var expiryNotice: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L.t("purchase.expiry-title"))
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("purchase.expiry-title")
            Text(L.t("purchase.expiry-free"))
                .font(.subheadline).foregroundStyle(Palette.muted)
            Text(L.t("purchase.expiry-pro"))
                .font(.subheadline).foregroundStyle(Palette.muted)
            expiryNoticeActions
        }
        .cardStyle()
    }

    @ViewBuilder private var expiryNoticeActions: some View {
        Button(action: unlock) { Label(L.t("purchase.expiry-buy"), systemImage: "sparkles") }
            .buttonStyle(PrimaryButton())
            .accessibilityIdentifier("purchase.expiry-buy")
        Button(action: dismissExpiryNotice) { Label(L.t("purchase.expiry-dismiss"), systemImage: "xmark") }
            .buttonStyle(PrimaryButton(filled: false))
            .accessibilityIdentifier("purchase.expiry-dismiss")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L.t("app.name")).sectionTitle()
            Text(L.t("home.title")).font(.largeTitle.bold()).accessibilityIdentifier("home.title")
            if !model.data.people.isEmpty {
                Text(model.summaryLine).font(.subheadline).foregroundStyle(Palette.muted)
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                Menu {
                    Button { pickContact() } label: { Label(L.t("add.contact"), systemImage: "person.crop.circle.badge.plus") }
                        .accessibilityIdentifier("add.contact")
                    Button(action: manual) { Label(L.t("add.manual"), systemImage: "square.and.pencil") }
                        .accessibilityIdentifier("add.manual")
                } label: {
                    IconTile(title: L.t("home.add"), symbol: "person.badge.plus", color: Palette.sage)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L.t("home.add"))
                .accessibilityIdentifier("home.add")
                Button(action: more) {
                    IconTile(title: L.t("home.more"), symbol: "ellipsis", color: Palette.mist)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L.t("home.more"))
                .accessibilityIdentifier("home.more")
            }
        }
    }

    private var empty: some View {
        HeroCard {
            VStack(spacing: 12) {
                EmptyIllustration()
                Text(L.t("empty.title")).font(.title2.bold())
                Text(L.t("empty.body")).font(.subheadline).foregroundStyle(Palette.muted)
                Button { Task { await model.requestContacts() } } label: {
                    Label(L.t("empty.contacts"), systemImage: "person.crop.circle.badge.plus")
                }
                .buttonStyle(PrimaryButton())
                .accessibilityIdentifier("empty.contacts")
                Button(action: manual) { Label(L.t("add.manual"), systemImage: "square.and.pencil") }
                .buttonStyle(PrimaryButton(filled: false))
                .accessibilityIdentifier("empty.manual")
            }
            .multilineTextAlignment(.center)
        }
    }

    private func pickContact() {
        if model.testing {
            let s = Seed.suggestions()[0]
            model.addSuggestions([s])
            return
        }
        pickingContact = true
        ContactPicker.shared.present { contact in
            Task { @MainActor in
                pickingContact = false
                guard let contact else { return }
                let picked = ContactsService.picked(contact)
                guard !model.data.people.contains(where: { $0.contactID == picked.id }) else {
                    model.message = L.t("add.exists")
                    return
                }
                let text = [contact.nickname, contact.givenName, contact.familyName].joined(separator: " ")
                let relation = RelationGuess.guess(text) ?? .other
                let usesContactName = ![.mother, .father].contains(relation)
                let name = usesContactName ? picked.info.name : relation.callName
                var person = model.newPerson(name: name, relation: relation, contactID: picked.id, usesContactName: usesContactName)
                if let b = picked.info.birthday { person.birthMonth = b.month; person.birthDay = b.day }
                model.save(person)
                await model.refreshContacts()
                model.showToast(L.f("toast.added", person.displayName))
            }
        }
    }
}

struct SuggestionPanel: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L.t("suggest.title")).sectionTitle()
            ForEach(model.suggestions) { item in
                Toggle(isOn: Binding(
                    get: { model.suggestions.first(where: { $0.id == item.id })?.picked ?? false },
                    set: { value in
                        if let i = model.suggestions.firstIndex(where: { $0.id == item.id }) { model.suggestions[i].picked = value }
                    })) {
                    HStack(spacing: 10) {
                        if let image = item.thumbnail.flatMap(UIImage.init(data:)) {
                            Avatar(image: image, size: 38)
                        } else {
                            IconBadge(symbol: "person.fill", color: item.relation.isFamily ? Palette.sage : Palette.mist)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name).font(.subheadline.weight(.semibold))
                            Text(item.relation.label).font(.caption).foregroundStyle(Palette.muted)
                        }
                    }
                }
                .accessibilityIdentifier("suggest.item")
            }
            Button { model.addSuggestions(model.suggestions.filter(\.picked)) } label: {
                Label(L.t("suggest.add"), systemImage: "person.badge.plus")
            }
            .buttonStyle(PrimaryButton())
            .disabled(!model.suggestions.contains(where: \.picked))
            .accessibilityIdentifier("suggest.add")
            Button { model.dismissSuggestions() } label: { Label(L.t("suggest.skip"), systemImage: "xmark") }
                .buttonStyle(PrimaryButton(filled: false))
                .accessibilityIdentifier("suggest.skip")
        }
        .cardStyle(padding: 16)
    }
}

struct CandidatePrompt: View {
    @ObservedObject var model: AppModel
    let person: Person
    let method: ContactMethod

    var body: some View {
        HStack(spacing: 10) {
            IconBadge(symbol: method.symbol, color: method.iconColor)
            Text(L.f("candidate.ask", person.displayName)).font(.subheadline.weight(.semibold))
            Spacer(minLength: 4)
            Button { model.record(person.id, method: method) } label: {
                Text(L.t("candidate.yes"))
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 12).frame(minWidth: 44, minHeight: 44)
                    .background(Palette.pale, in: Capsule()).foregroundStyle(Palette.accentText)
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("candidate.yes")
            Button { model.candidate = nil } label: {
                Image(systemName: "xmark").frame(width: 44, height: 44).contentShape(Rectangle())
            }
                .accessibilityLabel(L.t("common.close"))
                .foregroundStyle(Palette.muted)
        }
        .padding(10)
        .background(Palette.warm, in: RoundedRectangle(cornerRadius: 18))
    }
}

struct PersonCard: View {
    @ObservedObject var model: AppModel
    let person: Person
    let featured: Bool
    let open: () -> Void
    let addPhoto: () -> Void

    private var photo: PhotoEntry? { model.photos(of: person).first }
    private var avatar: ContactAvatar {
        ContactAvatar(image: model.avatar(person), person: person, standing: model.standing(person), size: featured ? 58 : 38)
    }

    @ViewBuilder
    var body: some View {
        if featured {
            HeroCard { content }
        } else {
            content.cardStyle()
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 10) {
            if featured { Text(L.t("home.featured")).sectionTitle() }
            detailButton
            actions
            if photo == nil {
                photoButton {
                    Label(L.t("photo.add"), systemImage: "photo.badge.plus")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 12).frame(minHeight: 44)
                        .foregroundStyle(Palette.accentText)
                        .background(Palette.pale, in: RoundedRectangle(cornerRadius: 14))
                        .contentShape(Rectangle())
                }
            }
        }
    }

    private func photoButton<Label: View>(@ViewBuilder label: () -> Label) -> some View {
        Button(action: addPhoto, label: label)
            .buttonStyle(.plain)
            .accessibilityLabel(L.f("photo.add.for", person.displayName))
            .accessibilityIdentifier("home.photo.add")
    }

    private var detailButton: some View {
        Button(action: open) { top }
            .buttonStyle(.plain)
            .accessibilityIdentifier("home.card")
    }

    private var top: some View {
        HStack(alignment: .top, spacing: 12) {
            avatar
            VStack(alignment: .leading, spacing: 5) {
                Text(person.displayName).font(featured ? .title2.bold() : .headline)
                Text(model.statusLine(person))
                    .font(.system(featured ? .title2 : .subheadline, design: .rounded).bold())
                    .monospacedDigit()
                StatusPill(text: model.dueLine(person), color: avatar.statusColor)
                Text(model.lastLine(person)).font(.caption).foregroundStyle(Palette.muted)
                Label(model.photoLine(photo), systemImage: "photo.on.rectangle").font(.caption)
                    .foregroundStyle(Palette.accentText)
                if !person.note.isEmpty {
                    Text(person.note).font(.caption).foregroundStyle(Palette.ink).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let photo {
                PhotoTile(image: model.image(photo), height: 44).frame(width: 44)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var actions: some View {
        Group {
            if featured {
                VStack(spacing: 8) {
                    doneButton
                    CallButton(model: model, person: person, identifier: "card.call", filled: false)
                }
            } else {
                HStack(spacing: 8) {
                    CallButton(model: model, person: person, identifier: "card.call", filled: false)
                    doneButton
                }
            }
        }
    }

    private var doneButton: some View {
        Button { model.record(person.id, method: .other) } label: {
            Label(L.t("action.done"), systemImage: "checkmark.circle.fill")
        }
        .buttonStyle(PrimaryButton(filled: featured))
        .accessibilityIdentifier("card.done")
    }
}

struct CallButton: View {
    @ObservedObject var model: AppModel
    let person: Person
    let identifier: String
    var filled = true

    var body: some View {
        let phones = model.phones(person)
        if phones.isEmpty {
            let linked = person.contactID != nil
            Button {
                model.message = L.t(linked ? "contacts.update.hint" : "call.no-number")
            } label: {
                Label(L.t(linked ? "contacts.update" : "action.add-number"), systemImage: "phone.badge.plus")
            }
                .buttonStyle(PrimaryButton(filled: filled))
                .accessibilityIdentifier(identifier)
        } else if phones.count > 1 {
            Menu {
                ForEach(phones, id: \.self) { number in Button(number) { model.call(person, number: number) } }
            } label: {
                Label(L.t("action.call"), systemImage: "phone.fill")
                    .actionStyle(filled: filled)
            } primaryAction: {
                model.call(person)
            }
            .accessibilityIdentifier(identifier)
        } else {
            Button { model.call(person) } label: { Label(L.t("action.call"), systemImage: "phone.fill") }
                .buttonStyle(PrimaryButton(filled: filled))
                .accessibilityIdentifier(identifier)
        }
    }
}

struct EmptyFrame: View {
    var height: CGFloat = 150

    var body: some View {
        VStack(spacing: 8) {
            EmptyIllustration(symbol: "photo.on.rectangle.angled")
            Text(L.t("photo.none.hint")).font(.caption).foregroundStyle(Palette.muted)
            Label(L.t("photo.add"), systemImage: "plus").actionStyle(filled: true)
        }
        .frame(maxWidth: .infinity, minHeight: height)
        .cardStyle()
        .contentShape(Rectangle())
    }
}

struct ToastBar: View {
    @ObservedObject var model: AppModel

    var body: some View {
        if let toast = model.toast {
            HStack(spacing: 12) {
                Text(toast.text).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.onDarkPanel).lineLimit(2)
                    .accessibilityIdentifier("toast.text")
                Spacer(minLength: 4)
                if let id = toast.undoEvent {
                    Button(L.t("toast.undo")) { model.undo(id) }
                        .font(.subheadline.weight(.bold)).foregroundStyle(Palette.accentOnDarkPanel)
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("toast.undo")
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 6)
            .background(Palette.darkPanel, in: RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 16).padding(.bottom, 10)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}
