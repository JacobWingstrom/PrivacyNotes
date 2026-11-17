import SwiftUI

/// App-wide navigation state: the current section, the drawer and the bottom bar's + button.
@Observable
final class Router {
    var section: AppSection
    var drawerOpen = false
    /// Bumped by the + button; the visible section creates a new item when it changes.
    var createRequest = 0
    /// A tag picked in the drawer, consumed by the Notes list.
    var noteTag: String?
    /// A folder picked in the drawer, opened by the Notes list.
    var noteFolder: UUID?
    /// Set when "+" on Home or All picks another section; that section creates an item when it appears.
    var pendingCreate: AppSection?

    /// Asks for the focus timer, a voice memo or today's note from outside the app.
    var showFocus = false
    /// A new email to write (from Mail, a mailto: link or a reply).
    var composeRequest: ComposeRequest?
    var showMemo = false
    var dailyRequest = 0

    static weak var shared: Router?

    init(section: AppSection) {
        self.section = section
        Router.shared = self
    }

    /// hush://new/<section>, hush://open/<section>, hush://daily, hush://focus, hush://memo
    func handle(_ url: URL) {
        guard url.scheme == "hush" else { return }
        switch url.host() {
        case "new": if let s = AppSection(rawValue: url.lastPathComponent) { startNew(in: s) }
        case "open":
            if let s = AppSection(rawValue: url.lastPathComponent) {
                if s == .mail, url.query?.contains("review=1") == true { UserDefaults.standard.set("review", forKey: "mailLastMailbox") }
                go(s)
            }
        case "daily": go(.notes); dailyRequest += 1
        case "focus": showFocus = true
        case "memo": showMemo = true
        default: break
        }
    }

    func go(_ s: AppSection) {
        section = s
        withAnimation(.snappy(duration: 0.25)) { drawerOpen = false }
    }

    func create() { createRequest += 1 }

    @ObservationIgnored private var dailyHandled = 0
    /// True once per daily request, so a freshly opened Notes list handles it exactly once.
    func consumeDaily() -> Bool {
        guard dailyRequest > dailyHandled else { return false }
        dailyHandled = dailyRequest
        return true
    }

    func startNew(in s: AppSection) {
        pendingCreate = s
        go(s)
    }
}

/// Runs `action` when the + button is tapped while this section is showing,
/// or when Home/All asked this section to create something.
struct OnCreate: ViewModifier {
    let section: AppSection
    let action: () -> Void
    @Environment(Router.self) private var router

    func body(content: Content) -> some View {
        content
            .onChange(of: router.createRequest) { action() }
            .onAppear {
                if router.pendingCreate == section {
                    router.pendingCreate = nil
                    DispatchQueue.main.async { action() }
                }
            }
    }
}

struct NewItemDialog: ViewModifier {
    static let kinds: [(AppSection, String)] = [
        (.notes, "Note"), (.tasks, "Task"), (.calendar, "Event"), (.journals, "Journal Entry"),
        (.drawings, "Drawing"), (.contacts, "Contact"), (.bookmarks, "Bookmark"),
    ]
    @Binding var isPresented: Bool
    @Environment(Router.self) private var router

    func body(content: Content) -> some View {
        content.confirmationDialog("New", isPresented: $isPresented) {
            ForEach(Self.kinds, id: \.0) { section, label in
                Button(label) { router.startNew(in: section) }
            }
        }
    }
}

extension View {
    func onCreate(_ section: AppSection, perform action: @escaping () -> Void) -> some View {
        modifier(OnCreate(section: section, action: action))
    }
    func newItemDialog(isPresented: Binding<Bool>) -> some View {
        modifier(NewItemDialog(isPresented: isPresented))
    }
}
