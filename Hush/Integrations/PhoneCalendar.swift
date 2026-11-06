import SwiftUI
import EventKit
import EventKitUI

/// Live, read-through access to the calendars on this iPhone (iCloud, Outlook/Exchange, Google…).
/// iOS does the syncing; Hush never connects to the internet and stores none of these events.
@Observable
final class PhoneCalendar {
    @ObservationIgnored let store = EKEventStore()
    @ObservationIgnored private var observer: NSObjectProtocol?

    var status: EKAuthorizationStatus = EKEventStore.authorizationStatus(for: .event)
    var calendars: [EKCalendar] = []
    var changeToken = 0
    var linked: Bool { didSet { UserDefaults.standard.set(linked, forKey: "phoneCalendarLinked") } }
    var enabledIDs: Set<String> { didSet { UserDefaults.standard.set(Array(enabledIDs), forKey: "phoneCalendarIDs") } }

    init() {
        linked = UserDefaults.standard.bool(forKey: "phoneCalendarLinked")
        enabledIDs = Set(UserDefaults.standard.stringArray(forKey: "phoneCalendarIDs") ?? [])
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            self?.reload()
        }
        reload()
    }

    var hasAccess: Bool { status == .fullAccess }
    var isActive: Bool { linked && hasAccess }

    func requestAccess() async {
        let granted = (try? await store.requestFullAccessToEvents()) ?? false
        await MainActor.run {
            status = EKEventStore.authorizationStatus(for: .event)
            if granted {
                linked = true
                if enabledIDs.isEmpty {
                    enabledIDs = Set(store.calendars(for: .event).map(\.calendarIdentifier))
                }
            }
            reload()
        }
    }

    func reload() {
        status = EKEventStore.authorizationStatus(for: .event)
        guard hasAccess else { calendars = []; return }
        calendars = store.calendars(for: .event).sorted { a, b in
            if a.source.title != b.source.title {
                return a.source.title.localizedCaseInsensitiveCompare(b.source.title) == .orderedAscending
            }
            return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
        }
        changeToken += 1
    }

    /// Calendars grouped by account (e.g. "iCloud", "Outlook", "Gmail").
    var groupedCalendars: [(String, [EKCalendar])] {
        let dict = Dictionary(grouping: calendars) { $0.source.title }
        return dict.keys.sorted().map { ($0, dict[$0] ?? []) }
    }

    func events(from start: Date, to end: Date) -> [EKEvent] {
        _ = changeToken
        guard isActive else { return [] }
        let cals = calendars.filter { enabledIDs.contains($0.calendarIdentifier) }
        guard !cals.isEmpty else { return [] }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: cals)
        return store.events(matching: predicate).sorted { $0.startDate < $1.startDate }
    }

    func toggle(_ cal: EKCalendar) {
        if enabledIDs.contains(cal.calendarIdentifier) { enabledIDs.remove(cal.calendarIdentifier) }
        else { enabledIDs.insert(cal.calendarIdentifier) }
    }
}

extension EKEvent {
    func occurs(on day: Date) -> Bool {
        let start = Calendar.current.startOfDay(for: day)
        let end = start.addingTimeInterval(86400)
        return startDate < end && max(endDate, startDate.addingTimeInterval(1)) > start
    }
}

/// Something to open in the system event editor: an existing phone event, or a new one starting at `start`.
struct PhoneEventRef: Identifiable {
    let id = UUID()
    var event: EKEvent?
    var start: Date = .now
}

struct PhoneEventRow: View {
    let event: EKEvent
    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(cgColor: event.calendar.cgColor))
                .frame(width: 4)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title?.isEmpty == false ? event.title! : "Event").foregroundStyle(.primary)
                Group {
                    if event.isAllDay {
                        Text("All day")
                    } else {
                        Text("\(event.startDate.formatted(date: .omitted, time: .shortened)) – \(event.endDate.formatted(date: .omitted, time: .shortened))")
                    }
                }
                .font(.hush(.caption)).foregroundStyle(.secondary)
                if let loc = event.location, !loc.isEmpty {
                    Label(loc, systemImage: "mappin").font(.hush(.caption)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
            Text(event.calendar.title)
                .font(.hush(.caption2))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .contentShape(Rectangle())
    }
}

/// Apple's own event editor, used for viewing, editing or adding events in your iPhone calendars.
struct PhoneEventEditor: UIViewControllerRepresentable {
    let store: EKEventStore
    let ref: PhoneEventRef
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> EKEventEditViewController {
        let vc = EKEventEditViewController()
        vc.eventStore = store
        if let event = ref.event {
            vc.event = event
        } else {
            let e = EKEvent(eventStore: store)
            e.startDate = ref.start
            e.endDate = ref.start.addingTimeInterval(3600)
            e.calendar = store.defaultCalendarForNewEvents
            vc.event = e
        }
        vc.editViewDelegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ vc: EKEventEditViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator { dismiss() } }

    final class Coordinator: NSObject, EKEventEditViewDelegate {
        let done: () -> Void
        init(done: @escaping () -> Void) { self.done = done }
        func eventEditViewController(_ controller: EKEventEditViewController, didCompleteWith action: EKEventEditViewAction) {
            done()
        }
    }
}

struct ConnectedCalendarsView: View {
    @Environment(PhoneCalendar.self) private var phone

    var body: some View {
        @Bindable var p = phone
        HushForm {
            if !phone.hasAccess {
                Section {
                    if phone.status == .denied || phone.status == .restricted {
                        Text("Hush doesn't have permission to read your calendars.")
                        Button("Open iPhone Settings") { openSettings() }
                    } else {
                        Button("Connect iPhone Calendars") { Task { await phone.requestAccess() } }
                    }
                } footer: {
                    Text("Shows events from Apple Calendar and any account on your iPhone — including Outlook — right inside Hush's Calendar and Home. Hush reads them through iOS and never connects to the internet.")
                }
            } else {
                Section {
                    Toggle("Show iPhone Calendars in Hush", isOn: $p.linked)
                } footer: {
                    Text("Events stay in your iPhone calendars and are never copied into Hush unless you import them.")
                }
                if phone.linked {
                    ForEach(phone.groupedCalendars, id: \.0) { account, cals in
                        Section(account) {
                            ForEach(cals, id: \.calendarIdentifier) { cal in
                                Toggle(isOn: Binding(get: { phone.enabledIDs.contains(cal.calendarIdentifier) },
                                                     set: { _ in phone.toggle(cal) })) {
                                    HStack(spacing: 10) {
                                        Circle().fill(Color(cgColor: cal.cgColor)).frame(width: 12, height: 12)
                                        Text(cal.title)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            Section {
                Label("Open the iPhone **Settings** app", systemImage: "1.circle")
                Label("Go to **Apps → Calendar → Calendar Accounts**", systemImage: "2.circle")
                Label("Tap **Add Account → Microsoft Exchange** (or Outlook.com) and sign in", systemImage: "3.circle")
                Label("Come back here; Outlook calendars appear in the list", systemImage: "4.circle")
            } header: {
                Text("Adding Outlook")
            } footer: {
                Text("The same works for Google and other calendar accounts.")
            }
        }
        .navigationTitle("Connected Calendars")
        .onAppear { phone.reload() }
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
    }
}
