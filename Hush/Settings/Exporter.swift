import SwiftUI
import SwiftData
import Contacts

/// Writes readable, unencrypted copies of your data for sharing or moving elsewhere.
enum Exporter {
    static var dir: URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("hush-export", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    static func clear() { try? FileManager.default.removeItem(at: dir) }

    static func safeName(_ s: String, fallback: String) -> String {
        let bad = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        let cleaned = s.components(separatedBy: bad).joined(separator: "-").trimmed
        return String((cleaned.isEmpty ? fallback : cleaned).prefix(80))
    }

    static func write(_ data: Data, name: String) -> URL? {
        var url = dir.appendingPathComponent(name)
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            let base = (name as NSString).deletingPathExtension, ext = (name as NSString).pathExtension
            url = dir.appendingPathComponent("\(base) \(n).\(ext)")
            n += 1
        }
        do { try data.write(to: url, options: .atomic); return url } catch { return nil }
    }

    // MARK: Single note

    static func markdown(for note: Note) -> String {
        var s = ""
        if !note.title.isEmpty { s += "# \(note.title)\n\n" }
        if !note.tags.isEmpty { s += note.tags.map { "#\($0)" }.joined(separator: " ") + "\n\n" }
        return s + note.body
    }

    static func markdownFile(for note: Note) -> URL? {
        write(Data(markdown(for: note).utf8), name: safeName(note.displayTitle, fallback: "Note") + ".md")
    }

    static func textFile(for note: Note) -> URL? {
        let text = (note.title.isEmpty ? "" : note.title + "\n\n") + Markdown.plain(note.body)
        return write(Data(text.utf8), name: safeName(note.displayTitle, fallback: "Note") + ".txt")
    }

    static func pdfFile(for note: Note) -> URL? {
        write(pdf(MarkdownStyler.printable(title: note.title, body: note.body)), name: safeName(note.displayTitle, fallback: "Note") + ".pdf")
    }

    static func pdf(_ text: NSAttributedString) -> Data {
        let page = CGRect(x: 0, y: 0, width: 612, height: 792)
        let formatter = UISimpleTextPrintFormatter(attributedText: text)
        let renderer = UIPrintPageRenderer()
        renderer.addPrintFormatter(formatter, startingAtPageAt: 0)
        renderer.setValue(page, forKey: "paperRect")
        renderer.setValue(page.insetBy(dx: 54, dy: 54), forKey: "printableRect")
        let data = NSMutableData()
        UIGraphicsBeginPDFContextToData(data, page, nil)
        for i in 0..<max(renderer.numberOfPages, 1) {
            UIGraphicsBeginPDFPage()
            renderer.drawPage(at: i, in: UIGraphicsGetPDFContextBounds())
        }
        UIGraphicsEndPDFContext()
        return data as Data
    }

    // MARK: Collections

    static func notes(_ notes: [Note]) -> [URL] {
        notes.compactMap { markdownFile(for: $0) }
    }

    static func journal(_ entries: [JournalEntry]) -> URL? {
        let text = entries.sorted { $0.date < $1.date }.map { e in
            "## \(e.date.formatted(date: .complete, time: .shortened))\(e.mood == .none ? "" : " \(e.mood.emoji)")\n\n"
                + (e.title.isEmpty ? "" : "**\(e.title)**\n\n") + e.body
        }.joined(separator: "\n\n---\n\n")
        return write(Data(("# Journal\n\n" + text).utf8), name: "Journal.md")
    }

    static func csv(_ rows: [[String]]) -> Data {
        Data(rows.map { $0.map { "\"" + $0.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }.joined(separator: ",") }
            .joined(separator: "\n").utf8)
    }

    static func tasks(_ tasks: [TaskItem]) -> URL? {
        let iso = ISO8601DateFormatter()
        var rows = [["Title", "Notes", "Done", "Due", "Priority", "List", "Repeat", "Subtasks"]]
        for t in tasks {
            rows.append([t.title, t.notes, t.isDone ? "yes" : "no", t.dueDate.map(iso.string) ?? "", t.priority.label,
                         t.list, t.repeatRule.label, t.subtasks.map { ($0.done ? "[x] " : "[ ] ") + $0.title }.joined(separator: "; ")])
        }
        return write(csv(rows), name: "Tasks.csv")
    }

    static func habits(_ habits: [Habit]) -> URL? {
        var rows = [["Habit", "Date", "Count", "Target"]]
        for h in habits {
            for (day, count) in h.log.sorted(by: { $0.key < $1.key }) { rows.append([h.name, day, "\(count)", "\(h.target)"]) }
        }
        return write(csv(rows), name: "Habits.csv")
    }

    static func bookmarks(_ items: [Bookmark]) -> URL? {
        var html = "<!DOCTYPE NETSCAPE-Bookmark-file-1>\n<META HTTP-EQUIV=\"Content-Type\" CONTENT=\"text/html; charset=UTF-8\">\n<TITLE>Bookmarks</TITLE>\n<H1>Bookmarks</H1>\n<DL><p>\n"
        for b in items {
            let title = b.displayTitle.replacingOccurrences(of: "<", with: "&lt;")
            html += "<DT><A HREF=\"\(b.urlString)\" ADD_DATE=\"\(Int(b.createdAt.timeIntervalSince1970))\" TAGS=\"\(b.tags.joined(separator: ","))\">\(title)</A>\n"
        }
        html += "</DL><p>\n"
        return write(Data(html.utf8), name: "Bookmarks.html")
    }

    static func contacts(_ items: [Contact]) -> URL? {
        let cards: [CNContact] = items.map { c in
            let m = CNMutableContact()
            m.givenName = c.firstName; m.familyName = c.lastName; m.organizationName = c.company
            m.phoneNumbers = c.phones.map { CNLabeledValue(label: $0.label, value: CNPhoneNumber(stringValue: $0.value)) }
            m.emailAddresses = c.emails.map { CNLabeledValue(label: $0.label, value: $0.value as NSString) }
            if let b = c.birthday { m.birthday = Calendar.current.dateComponents([.year, .month, .day], from: b) }
            if !c.address.isEmpty {
                let a = CNMutablePostalAddress(); a.street = c.address
                m.postalAddresses = [CNLabeledValue(label: CNLabelHome, value: a)]
            }
            return m
        }
        guard let data = try? CNContactVCardSerialization.data(with: cards) else { return nil }
        return write(data, name: "Contacts.vcf")
    }

    static func events(_ items: [CalendarEvent]) -> URL? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        let day = DateFormatter(); day.locale = f.locale; day.dateFormat = "yyyyMMdd"
        func esc(_ s: String) -> String {
            s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\n", with: "\\n")
                .replacingOccurrences(of: ",", with: "\\,").replacingOccurrences(of: ";", with: "\\;")
        }
        var lines = ["BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//Hush//EN"]
        for e in items {
            lines.append("BEGIN:VEVENT")
            lines.append("UID:\(e.id.uuidString)@hush")
            lines.append("DTSTAMP:\(f.string(from: .now))")
            if e.isAllDay {
                lines.append("DTSTART;VALUE=DATE:\(day.string(from: e.start))")
                lines.append("DTEND;VALUE=DATE:\(day.string(from: Calendar.current.date(byAdding: .day, value: 1, to: e.end) ?? e.end))")
            } else {
                lines.append("DTSTART:\(f.string(from: e.start))")
                lines.append("DTEND:\(f.string(from: e.end))")
            }
            lines.append("SUMMARY:\(esc(e.title))")
            if !e.location.isEmpty { lines.append("LOCATION:\(esc(e.location))") }
            if !e.notes.isEmpty { lines.append("DESCRIPTION:\(esc(e.notes))") }
            lines.append("END:VEVENT")
        }
        lines.append("END:VCALENDAR")
        return write(Data(lines.joined(separator: "\r\n").utf8), name: "Calendar.ics")
    }
}

struct ExportView: View {
    @Query private var notes: [Note]
    @Query private var journals: [JournalEntry]
    @Query private var tasks: [TaskItem]
    @Query private var habits: [Habit]
    @Query private var bookmarks: [Bookmark]
    @Query private var contacts: [Contact]
    @Query private var events: [CalendarEvent]
    @Environment(AppSettings.self) private var settings
    @State private var share: ShareItem?
    @State private var onlyThisSpace = false

    var body: some View {
        let space = onlyThisSpace ? settings.spaceFilter : nil
        HushForm {
            Section {
                if settings.spaceFilter != nil {
                    Toggle("Only \(settings.currentSpaceInfo?.name ?? "this space")", isOn: $onlyThisSpace)
                }
            } footer: {
                Text("Exports are normal, unencrypted files that other apps can open. For a private, complete copy use Backup & Restore instead.")
            }
            Section("Export") {
                exportRow("Notes", "Markdown files", "square.and.pencil", notes.live(space).count) {
                    Exporter.clear(); return Exporter.notes(notes.live(space))
                }
                exportRow("Journal", "One Markdown file", "book.closed", journals.live(space).count) {
                    Exporter.clear(); return [Exporter.journal(journals.live(space))].compactMap { $0 }
                }
                exportRow("Tasks", "Spreadsheet (CSV)", "checkmark.circle", tasks.live(space).count) {
                    Exporter.clear(); return [Exporter.tasks(tasks.live(space))].compactMap { $0 }
                }
                exportRow("Habits", "Spreadsheet (CSV)", "flame", habits.live(space).count) {
                    Exporter.clear(); return [Exporter.habits(habits.live(space))].compactMap { $0 }
                }
                exportRow("Calendar", "Calendar file (.ics)", "calendar", events.live(space).count) {
                    Exporter.clear(); return [Exporter.events(events.live(space))].compactMap { $0 }
                }
                exportRow("Contacts", "Contact cards (.vcf)", "person.crop.rectangle", contacts.live(space).count) {
                    Exporter.clear(); return [Exporter.contacts(contacts.live(space))].compactMap { $0 }
                }
                exportRow("Bookmarks", "Browser bookmarks (.html)", "bookmark", bookmarks.live(space).count) {
                    Exporter.clear(); return [Exporter.bookmarks(bookmarks.live(space))].compactMap { $0 }
                }
            }
        }
        .navigationTitle("Export")
        .sheet(item: $share) { item in ActivityView(items: item.urls).ignoresSafeArea() }
    }

    private func exportRow(_ title: String, _ format: String, _ symbol: String, _ count: Int, make: @escaping () -> [URL]) -> some View {
        Button {
            let urls = make()
            if !urls.isEmpty { share = ShareItem(urls: urls) }
        } label: {
            HStack {
                Label {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(title).foregroundStyle(.primary)
                        Text(format).font(.caption).foregroundStyle(.secondary)
                    }
                } icon: { Image(systemName: symbol) }
                Spacer()
                Text("\(count)").foregroundStyle(.secondary).monospacedDigit()
                Image(systemName: "square.and.arrow.up").foregroundStyle(.tint)
            }
        }
        .disabled(count == 0)
    }
}
