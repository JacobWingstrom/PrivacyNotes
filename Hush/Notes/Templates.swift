import SwiftUI
import SwiftData

struct BuiltInTemplate: Identifiable {
    let category: String
    let name: String
    let emoji: String
    let title: String
    let body: String
    var id: String { category + name }
}

/// Fills in {{date}}, {{time}}, {{weekday}} and {{week}}.
enum TemplateFill {
    static func apply(_ s: String) -> String {
        let now = Date()
        let week = Calendar.current.component(.weekOfYear, from: now)
        return s
            .replacingOccurrences(of: "{{date}}", with: now.formatted(date: .long, time: .omitted))
            .replacingOccurrences(of: "{{time}}", with: now.formatted(date: .omitted, time: .shortened))
            .replacingOccurrences(of: "{{weekday}}", with: now.formatted(.dateTime.weekday(.wide)))
            .replacingOccurrences(of: "{{week}}", with: "\(week)")
    }
}

enum TemplateLibrary {
    static let categories = ["Notes", "Homelab", "Work", "Personal", "Planning"]

    static let all: [BuiltInTemplate] = [
        // MARK: Notes
        .init(category: "Notes", name: "Meeting Notes", emoji: "calendar", title: "Meeting – {{date}}", body: """
        **When:** {{date}}, {{time}}
        **Who:**

        ## Agenda
        -

        ## Notes
        -

        ## Decisions
        -

        ## Action items
        - [ ] Owner — task — due
        """),
        .init(category: "Notes", name: "Quick Capture", emoji: "bolt", title: "", body: """
        ## Idea


        ## Why it matters


        ## Next step
        - [ ]
        """),
        .init(category: "Notes", name: "Reading Notes", emoji: "books.vertical", title: "Reading: ", body: """
        **Author:**
        **Started:** {{date}}
        **Rating:** /5

        ## Summary in three sentences


        ## Key ideas
        -

        ## Quotes worth keeping
        >

        ## How I'll use this
        -
        """),
        .init(category: "Notes", name: "Research Topic", emoji: "magnifyingglass", title: "Research: ", body: """
        ## Question
        What exactly am I trying to find out?

        ## What I already know
        -

        ## Sources
        - [Title](https://)

        ## Findings
        -

        ## Open questions
        - [ ]
        """),
        .init(category: "Notes", name: "Lecture / Class", emoji: "graduationcap", title: "Class – {{date}}", body: """
        **Course:**
        **Topic:**

        ## Main points
        -

        ## Definitions
        - **Term** — meaning

        ## Questions to ask
        - [ ]

        ## Homework
        - [ ]
        """),

        // MARK: Homelab
        .init(category: "Homelab", name: "Server Inventory", emoji: "server.rack", title: "Server: ", body: """
        ## Hardware
        - **Model:**
        - **CPU:**
        - **RAM:**
        - **Storage:**
        - **NICs:**

        ## System
        - **OS / hypervisor:**
        - **Hostname:**
        - **IP address:**
        - **Management / IPMI:**
        - **Location / rack slot:**

        ## Services running
        | Service | Port | Notes |
        |---|---|---|
        |  |  |  |

        ## Credentials
        Stored in the Hush Vault under "".

        ## Notes
        - Purchased:
        - Warranty until:
        """),
        .init(category: "Homelab", name: "Service / Container", emoji: "shippingbox", title: "Service: ", body: """
        **Runs on:**
        **URL:** http://
        **Image / version:**
        **Data path:**

        ## Compose / config
        ```
        services:
          app:
            image:
            ports:
              - "8080:80"
            volumes:
              - ./data:/data
            restart: unless-stopped
        ```

        ## Environment variables
        - `KEY` —

        ## Backups
        - [ ] Included in nightly backup
        - [ ] Restore tested

        ## Update steps
        1. Read the release notes
        2. Snapshot / back up data
        3. Pull new image and restart
        4. Check logs and the web UI
        """),
        .init(category: "Homelab", name: "Network / IP Plan", emoji: "network", title: "Network Plan", body: """
        ## Subnets & VLANs
        | VLAN | Name | Subnet | Gateway | Purpose |
        |---|---|---|---|---|
        | 1 | Default | 192.168.1.0/24 | .1 | Management |
        | 10 | Trusted |  |  | Personal devices |
        | 20 | IoT |  |  | Smart home |
        | 30 | Guest |  |  | Visitors |

        ## Static reservations
        | Device | IP | MAC |
        |---|---|---|
        |  |  |  |

        ## DNS
        - **Resolver:**
        - **Local domain:**

        ## Firewall rules worth remembering
        -
        """),
        .init(category: "Homelab", name: "Change Log", emoji: "list.bullet.clipboard", title: "Change – {{date}}", body: """
        **System:**
        **Date:** {{date}} {{time}}
        **Risk:** Low / Medium / High

        ## What I changed
        -

        ## Why


        ## How to roll back
        1.

        ## Checked afterwards
        - [ ] Service reachable
        - [ ] Logs clean
        - [ ] Backups still running
        """),
        .init(category: "Homelab", name: "Incident Write-up", emoji: "exclamationmark.triangle", title: "Incident – {{date}}", body: """
        **Started:**
        **Resolved:**
        **Impact:**

        ## Timeline
        - {{time}} —

        ## Root cause


        ## What fixed it


        ## Follow-ups
        - [ ] Prevent it happening again
        - [ ] Add monitoring / alert
        - [ ] Update documentation
        """),
        .init(category: "Homelab", name: "Backup Plan", emoji: "externaldrive", title: "Backup Plan", body: """
        ## What gets backed up
        | Data | Source | Destination | Schedule | Retention |
        |---|---|---|---|---|
        |  |  |  | Nightly | 30 days |

        ## 3-2-1 check
        - [ ] 3 copies of important data
        - [ ] 2 different kinds of storage
        - [ ] 1 copy off-site

        ## Restore test log
        - {{date}} — restored ___ successfully
        """),
        .init(category: "Homelab", name: "Maintenance Checklist", emoji: "wrench.and.screwdriver", title: "Maintenance – {{date}}", body: """
        ## Monthly
        - [ ] Apply OS and package updates
        - [ ] Update containers / apps
        - [ ] Check disk health (SMART) and free space
        - [ ] Review backup logs
        - [ ] Test one restore
        - [ ] Check UPS battery status
        - [ ] Renew certificates expiring soon
        - [ ] Clean dust filters

        ## Notes
        -
        """),
        .init(category: "Homelab", name: "Hardware Build Log", emoji: "cpu", title: "Build: ", body: """
        ## Goal


        ## Parts
        | Part | Model | Price | Bought |
        |---|---|---|---|
        |  |  |  | - [ ] |

        ## Build steps
        1.

        ## Benchmarks / power draw
        - Idle:
        - Load:

        ## Lessons learned
        -
        """),

        // MARK: Work
        .init(category: "Work", name: "Daily Standup", emoji: "sun.max", title: "Standup – {{weekday}}", body: """
        ## Yesterday
        -

        ## Today
        - [ ]

        ## Blockers
        -
        """),
        .init(category: "Work", name: "1:1 Meeting", emoji: "person.2", title: "1:1 – {{date}}", body: """
        **With:**

        ## Their topics
        -

        ## My topics
        -

        ## Feedback
        -

        ## Follow-ups
        - [ ]
        """),
        .init(category: "Work", name: "Project Brief", emoji: "target", title: "Project: ", body: """
        ## Problem


        ## Goal
        What does done look like?

        ## Scope
        **In:**
        -
        **Out:**
        -

        ## Milestones
        - [ ]

        ## Risks
        -

        ## People
        - Owner:
        - Stakeholders:
        """),
        .init(category: "Work", name: "Bug Report", emoji: "ladybug", title: "Bug: ", body: """
        **Severity:** Low / Medium / High
        **Found:** {{date}}

        ## Steps to reproduce
        1.

        ## Expected


        ## Actual


        ## Environment
        - Version:
        - Device / OS:

        ## Notes
        -
        """),
        .init(category: "Work", name: "Decision Record", emoji: "scale.3d", title: "Decision: ", body: """
        **Date:** {{date}}
        **Status:** Proposed / Accepted / Replaced

        ## Context


        ## Options considered
        1. **Option A** — pros / cons
        2. **Option B** — pros / cons

        ## Decision


        ## Consequences
        -
        """),

        // MARK: Personal
        .init(category: "Personal", name: "Daily Journal", emoji: "book.closed", title: "{{weekday}}, {{date}}", body: """
        ## Three good things
        1.
        2.
        3.

        ## What's on my mind


        ## Tomorrow I want to
        - [ ]
        """),
        .init(category: "Personal", name: "Workout Log", emoji: "dumbbell", title: "Workout – {{date}}", body: """
        **Type:**
        **Duration:**
        **Energy:** /10

        | Exercise | Sets | Reps | Weight |
        |---|---|---|---|
        |  |  |  |  |

        ## Notes
        -
        """),
        .init(category: "Personal", name: "Recipe", emoji: "fork.knife", title: "Recipe: ", body: """
        **Serves:**
        **Prep:**  **Cook:**

        ## Ingredients
        - [ ]

        ## Steps
        1.

        ## Notes & tweaks
        -
        """),
        .init(category: "Personal", name: "Packing List", emoji: "suitcase", title: "Packing: ", body: """
        ## Essentials
        - [ ] ID / passport
        - [ ] Wallet and cards
        - [ ] Phone and charger
        - [ ] Keys
        - [ ] Medication

        ## Clothes
        - [ ]

        ## Toiletries
        - [ ] Toothbrush and toothpaste
        - [ ]

        ## Tech
        - [ ] Headphones
        - [ ] Power bank
        """),
        .init(category: "Personal", name: "Shopping List", emoji: "cart", title: "Shopping", body: """
        ## Produce
        - [ ]

        ## Dairy & eggs
        - [ ]

        ## Pantry
        - [ ]

        ## Household
        - [ ]
        """),
        .init(category: "Personal", name: "Gift Ideas", emoji: "gift", title: "Gift Ideas", body: """
        | Person | Occasion | Idea | Budget | Bought |
        |---|---|---|---|---|
        |  |  |  |  | - [ ] |
        """),

        // MARK: Planning
        .init(category: "Planning", name: "Weekly Plan", emoji: "square.grid.2x2", title: "Week {{week}}", body: """
        ## Top three this week
        1. [ ]
        2. [ ]
        3. [ ]

        ## Monday
        - [ ]
        ## Tuesday
        - [ ]
        ## Wednesday
        - [ ]
        ## Thursday
        - [ ]
        ## Friday
        - [ ]
        ## Weekend
        - [ ]
        """),
        .init(category: "Planning", name: "Weekly Review", emoji: "arrow.triangle.2.circlepath", title: "Review – Week {{week}}", body: """
        ## What went well
        -

        ## What didn't
        -

        ## What I learned
        -

        ## Next week's focus
        - [ ]
        """),
        .init(category: "Planning", name: "Goal Tracker", emoji: "flag.checkered", title: "Goal: ", body: """
        **Target date:**
        **Why it matters:**

        ## Milestones
        - [ ]
        - [ ]
        - [ ]

        ## Habits that support it
        -

        ## Progress log
        - {{date}} —
        """),
        .init(category: "Planning", name: "Trip Plan", emoji: "airplane", title: "Trip: ", body: """
        **Dates:**
        **Where:**

        ## Bookings
        - [ ] Travel
        - [ ] Stay
        - [ ] Car / transit

        ## Itinerary
        ### Day 1
        -

        ## Budget
        | Item | Cost |
        |---|---|
        |  |  |

        ## Ideas
        -
        """),
    ]
}

/// Pick a template (built-in or your own) to start a note.
struct TemplatePicker: View {
    var onPick: (_ title: String, _ body: String, _ emoji: String) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \NoteTemplate.createdAt, order: .reverse) private var mine: [NoteTemplate]
    @State private var search = ""
    @State private var preview: BuiltInTemplate?

    private func matches(_ name: String, _ body: String) -> Bool {
        search.isEmpty || name.localizedCaseInsensitiveContains(search) || body.localizedCaseInsensitiveContains(search)
    }

    var body: some View {
        NavigationStack {
            List {
                let myList = mine.filter { matches($0.name, $0.body) }
                if !myList.isEmpty {
                    Section {
                        ForEach(myList) { t in
                            Button { pick(t.title, t.body, t.emoji) } label: { row(t.emoji, t.name, Markdown.plain(t.body)) }
                                .hushRow()
                        }
                        .onDelete { $0.map { myList[$0] }.forEach(context.delete) }
                    } header: { ListHeader(title: "My Templates") }
                }
                ForEach(TemplateLibrary.categories, id: \.self) { cat in
                    let items = TemplateLibrary.all.filter { $0.category == cat && matches($0.name, $0.body) }
                    if !items.isEmpty {
                        Section {
                            ForEach(items) { t in
                                Button { pick(t.title, t.body, t.emoji) } label: { row(t.emoji, t.name, Markdown.plain(t.body)) }
                                    .contextMenu { Button("Preview") { preview = t } }
                                    .hushRow()
                            }
                        } header: { ListHeader(title: cat) }
                    }
                }
            }
            .hushList()
            .safeAreaInset(edge: .top, spacing: 0) { SearchHeader(text: $search, prompt: "Search templates…") }
            .navigationTitle("Templates")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .sheet(item: $preview) { t in
                NavigationStack {
                    ScrollView { Text(TemplateFill.apply(t.body)).font(.callout.monospaced()).padding() }
                        .navigationTitle(t.name)
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Use") { preview = nil; pick(t.title, t.body, t.emoji) }
                            }
                        }
                }
            }
        }
    }

    private func row(_ emoji: String, _ name: String, _ sub: String) -> some View {
        HStack(spacing: 12) {
            SymbolTile(name: emoji, fallback: "doc.text", size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).foregroundStyle(.primary)
                Text(sub.replacingOccurrences(of: "\n", with: " ").trimmed).font(.hush(.caption)).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }

    private func pick(_ title: String, _ body: String, _ emoji: String) {
        onPick(TemplateFill.apply(title), TemplateFill.apply(body), emoji)
        dismiss()
    }
}

struct TemplatesSettings: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \NoteTemplate.createdAt, order: .reverse) private var mine: [NoteTemplate]

    var body: some View {
        HushForm {
            Section {
                if mine.isEmpty {
                    Text("Save any note as a template from its ⋯ menu.").foregroundStyle(.secondary)
                }
                ForEach(mine) { t in
                    Label { Text(t.name) } icon: { SymbolIcon(name: t.emoji) }
                }
                .onDelete { $0.map { mine[$0] }.forEach(context.delete) }
            } header: {
                Text("My Templates")
            }
            Section {
                ForEach(TemplateLibrary.categories, id: \.self) { cat in
                    LabeledContent(cat, value: "\(TemplateLibrary.all.filter { $0.category == cat }.count)")
                }
            } header: {
                Text("Built-in")
            } footer: {
                Text("Templates can include {{date}}, {{time}}, {{weekday}} and {{week}}, which are filled in when you use them.")
            }
        }
        .navigationTitle("Templates")
    }
}
