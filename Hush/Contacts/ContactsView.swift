import SwiftUI
import SwiftData

struct ContactsView: View {
    let title: String
    @Environment(\.modelContext) private var context
    @Environment(Router.self) private var router
    @Query private var contactsStored: [Contact]
    @Environment(AppSettings.self) private var contactsSpace
    private var contacts: [Contact] { contactsStored.live(contactsSpace.spaceFilter) }
    @State private var search = ""
    @State private var newContact: Contact?

    private var filtered: [Contact] {
        contacts.filter { c in
            search.isEmpty || c.displayName.localizedCaseInsensitiveContains(search)
                || c.company.localizedCaseInsensitiveContains(search)
                || c.phones.contains { $0.value.contains(search) }
                || c.emails.contains { $0.value.localizedCaseInsensitiveContains(search) }
        }
        .sorted { $0.sortKey < $1.sortKey }
    }

    private var groups: [(String, [Contact])] {
        let rest = search.isEmpty ? filtered.filter { !$0.isFavorite } : filtered
        let dict = Dictionary(grouping: rest) { c -> String in
            let ch = c.sortKey.first.map { String($0).uppercased() } ?? "#"
            return ch.rangeOfCharacter(from: .letters) == nil ? "#" : ch
        }
        return dict.keys.sorted().map { ($0, dict[$0] ?? []) }
    }

    var body: some View {
        let favorites = filtered.filter(\.isFavorite)
        List {
            if !favorites.isEmpty && search.isEmpty {
                Section { ForEach(favorites) { row($0) } } header: { ListHeader(title: "Favorites") }
            }
            ForEach(groups, id: \.0) { letter, items in
                Section { ForEach(items) { row($0) } } header: { ListHeader(title: letter) }
            }
            if contacts.isEmpty {
                EmptyMessage(text: "No contacts yet. They stay inside Hush, apart from your iPhone's address book.")
            }
        }
        .hushList()
        .safeAreaInset(edge: .top, spacing: 0) { SearchHeader(text: $search, prompt: "Search contacts…") }
        .navigationTitle(title)
        .navigationDestination(item: $newContact) { ContactEditorView(contact: $0, isNew: true) }
        .onCreate(.contacts) {
            let c = Contact()
            context.insert(c)
            newContact = c
        }
    }

    private func row(_ c: Contact) -> some View {
        NavigationLink { ContactEditorView(contact: c) } label: { ContactRow(contact: c) }
            .swipeActions {
                Button(role: .destructive) {
                    TrashActions.trash(c)
                } label: { Label("Delete", systemImage: "trash") }
                Button { c.isFavorite.toggle() } label: {
                    Label(c.isFavorite ? "Unfavorite" : "Favorite", systemImage: c.isFavorite ? "star.slash" : "star")
                }
                .tint(.yellow)
            }
            .hushRow()
    }
}

struct ContactRow: View {
    let contact: Contact
    var body: some View {
        HStack(spacing: 12) {
            Avatar(text: contact.initials, emoji: contact.emoji, size: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(contact.displayName)
                if !contact.company.isEmpty && contact.displayName != contact.company {
                    Text(contact.company).font(.hush(.caption)).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if contact.isFavorite { Image(systemName: "star.fill").font(.hush(.caption)).foregroundStyle(.yellow) }
        }
        .padding(.vertical, 4)
    }
}

struct ContactEditorView: View {
    @Bindable var contact: Contact
    var isNew = false
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var deleting = false

    static let phoneLabels = ["mobile", "home", "work", "other"]
    static let emailLabels = ["personal", "work", "other"]

    var body: some View {
        HushForm {
            Section {
                VStack(spacing: 10) {
                    Avatar(text: contact.initials, emoji: contact.emoji, size: 80)
                    Text(contact.displayName).font(.hush(.title2).bold())
                    actionButtons
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }
            Section {
                TextField("First name", text: $contact.firstName).textContentType(.givenName)
                TextField("Last name", text: $contact.lastName).textContentType(.familyName)
                TextField("Company", text: $contact.company).textContentType(.organizationName)
                HStack {
                    Text("Icon")
                    TextField("Emoji (optional)", text: $contact.emoji)
                        .multilineTextAlignment(.trailing)
                        .onChange(of: contact.emoji) { _, v in if v.count > 1 { contact.emoji = String(v.suffix(1)) } }
                }
                Toggle("Favorite", isOn: $contact.isFavorite)
            }
            Section("Phone") {
                ForEach($contact.phones) { $p in
                    HStack {
                        Picker("", selection: $p.label) { ForEach(Self.phoneLabels, id: \.self) { Text($0).tag($0) } }
                            .labelsHidden().fixedSize()
                        TextField("Phone", text: $p.value).keyboardType(.phonePad)
                    }
                }
                .onDelete { contact.phones.remove(atOffsets: $0) }
                Button { contact.phones.append(LabeledValue(label: "mobile", value: "")) } label: { Label("Add Phone", systemImage: "plus") }
            }
            Section("Email") {
                ForEach($contact.emails) { $e in
                    HStack {
                        Picker("", selection: $e.label) { ForEach(Self.emailLabels, id: \.self) { Text($0).tag($0) } }
                            .labelsHidden().fixedSize()
                        TextField("Email", text: $e.value)
                            .keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                    }
                }
                .onDelete { contact.emails.remove(atOffsets: $0) }
                Button { contact.emails.append(LabeledValue(label: "personal", value: "")) } label: { Label("Add Email", systemImage: "plus") }
            }
            Section("Address") {
                TextField("Address", text: $contact.address, axis: .vertical).lineLimit(2...5)
            }
            Section {
                Toggle("Birthday", isOn: Binding(
                    get: { contact.birthday != nil },
                    set: { on in
                        contact.birthday = on ? (Calendar.current.date(byAdding: .year, value: -25, to: .now) ?? .now) : nil
                        if !on { contact.birthdayReminder = false }
                    }))
                if contact.birthday != nil {
                    DatePicker("Date", selection: Binding(get: { contact.birthday ?? .now }, set: { contact.birthday = $0 }),
                               displayedComponents: .date)
                    Toggle("Remind Me Each Year", isOn: $contact.birthdayReminder)
                }
            }
            Section("Notes") {
                TextField("Notes", text: $contact.notes, axis: .vertical).lineLimit(3...10)
            }
            Section {
                Button("Delete Contact", role: .destructive) {
                    deleting = true
                    dismiss()
                }
            }
        }
        .hushBackground()
        .navigationTitle(isNew ? "New Contact" : "Contact")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: contact.birthdayReminder) { _, on in
            if on { Task { await Reminders.requestPermission() } }
        }
        .onDisappear {
            contact.phones = contact.phones.filter { !$0.value.trimmed.isEmpty }
            contact.emails = contact.emails.filter { !$0.value.trimmed.isEmpty }
            if contact.isEmpty {
                Reminders.cancel("birthday.\(contact.id.uuidString)")
                context.delete(contact)
            } else if deleting {
                TrashActions.trash(contact)
            } else {
                Reminders.sync(contact)
            }
        }
    }

    @ViewBuilder private var actionButtons: some View {
        let phone = contact.phones.first { !$0.value.trimmed.isEmpty }?.value
        let email = contact.emails.first { !$0.value.trimmed.isEmpty }?.value
        if phone != nil || email != nil {
            HStack(spacing: 14) {
                if let phone, let tel = URL(string: "tel:\(phone.filter { "+0123456789".contains($0) })") {
                    action("Call", "phone.fill", tel)
                }
                if let phone, let sms = URL(string: "sms:\(phone.filter { "+0123456789".contains($0) })") {
                    action("Message", "message.fill", sms)
                }
                if let email, let mail = URL(string: "mailto:\(email.trimmed)") {
                    action("Email", "envelope.fill", mail)
                }
            }
        }
    }

    private func action(_ label: String, _ symbol: String, _ url: URL) -> some View {
        Link(destination: url) {
            VStack(spacing: 4) {
                Image(systemName: symbol).font(.hush(.title3))
                Text(label).font(.hush(.caption2))
            }
            .frame(width: 72, height: 54)
            .background(.tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.tint)
    }
}
