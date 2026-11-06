import UIKit
import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// "Save to Hush" in the iPhone share sheet. Text and links become notes, bookmarks or tasks right away;
/// photos and files wait in Hush's private inbox until the app encrypts them.
final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        let model = ShareModel(context: extensionContext)
        let host = UIHostingController(rootView: ShareView(model: model))
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
        Task { await model.load() }
    }
}

@Observable
final class ShareModel {
    var text = ""
    var url: URL?
    var files: [(name: String, data: Data)] = []
    var loading = true
    var kind = "note"
    var title = ""
    @ObservationIgnored weak var context: NSExtensionContext?

    init(context: NSExtensionContext?) { self.context = context }

    @MainActor
    func load() async {
        let providers = (context?.inputItems as? [NSExtensionItem] ?? []).flatMap { $0.attachments ?? [] }
        for p in providers {
            if p.hasItemConformingToTypeIdentifier(UTType.url.identifier),
               let u = try? await p.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL, !u.isFileURL {
                url = u
            } else if p.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                if let data = try? await loadData(p, UTType.image.identifier) {
                    let ext = p.registeredTypeIdentifiers.compactMap { UTType($0)?.preferredFilenameExtension }.first ?? "jpg"
                    files.append(("Shared \(Date().formatted(.iso8601.year().month().day())).\(ext)", data))
                }
            } else if p.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
                      let t = try? await p.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String {
                text += (text.isEmpty ? "" : "\n\n") + t
            } else if p.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier),
                      let fu = try? await p.loadItem(forTypeIdentifier: UTType.fileURL.identifier) as? URL,
                      let data = try? Data(contentsOf: fu) {
                files.append((fu.lastPathComponent, data))
            }
        }
        if let u = url, text.isEmpty { kind = "bookmark"; title = u.host() ?? "" }
        if !files.isEmpty && text.isEmpty && url == nil { kind = "files" }
        if kind == "note" { title = text.split(separator: "\n").first.map { String($0.prefix(80)) } ?? "" }
        loading = false
    }

    private func loadData(_ p: NSItemProvider, _ type: String) async throws -> Data? {
        let item = try await p.loadItem(forTypeIdentifier: type)
        if let d = item as? Data { return d }
        if let u = item as? URL { return try Data(contentsOf: u) }
        if let img = item as? UIImage { return img.jpegData(compressionQuality: 0.9) }
        return nil
    }

    @MainActor
    func save() {
        let ctx = Storage.shared.mainContext
        switch kind {
        case "bookmark":
            let b = Bookmark()
            b.urlString = url?.absoluteString ?? text
            b.title = title
            b.notes = url == nil ? "" : text
            ctx.insert(b)
        case "task":
            let t = TaskItem(title: title.isEmpty ? String(text.prefix(80)) : title)
            t.notes = [text, url?.absoluteString ?? ""].filter { !$0.isEmpty }.joined(separator: "\n")
            ctx.insert(t)
        case "files":
            break
        default:
            let n = Note()
            n.title = title
            var body = text
            if let u = url { body += (body.isEmpty ? "" : "\n\n") + "[\(u.host() ?? "Link")](\(u.absoluteString))" }
            if body.hasPrefix(title) && !title.isEmpty { body = String(body.dropFirst(title.count)).trimmingCharacters(in: .whitespacesAndNewlines) }
            n.body = body
            n.tags = ["shared"]
            ctx.insert(n)
        }
        for f in files { ShareInbox.save(f.data, name: f.name) }
        try? ctx.save()
        context?.completeRequest(returningItems: nil)
    }

    func cancel() {
        context?.cancelRequest(withError: NSError(domain: "Hush", code: 0))
    }
}

struct ShareView: View {
    @Bindable var model: ShareModel

    var body: some View {
        NavigationStack {
            Form {
                if model.loading {
                    ProgressView()
                } else {
                    Section {
                        Picker("Save as", selection: $model.kind) {
                            Text("Note").tag("note")
                            if model.url != nil { Text("Bookmark").tag("bookmark") }
                            Text("Task").tag("task")
                            if !model.files.isEmpty && model.text.isEmpty && model.url == nil { Text("Files").tag("files") }
                        }
                        .pickerStyle(.segmented)
                        if model.kind != "files" {
                            TextField("Title", text: $model.title)
                        }
                    }
                    if !model.text.isEmpty {
                        Section("Text") { Text(model.text).lineLimit(8).font(.callout) }
                    }
                    if let u = model.url {
                        Section("Link") { Text(u.absoluteString).font(.footnote).lineLimit(3) }
                    }
                    if !model.files.isEmpty {
                        Section {
                            ForEach(model.files.indices, id: \.self) { i in Label(model.files[i].name, systemImage: "doc") }
                        } header: { Text("Files") } footer: {
                            Text("Saved to Hush → Files, encrypted the next time you open Hush.")
                        }
                    }
                }
            }
            .navigationTitle("Save to Hush")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { model.cancel() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { model.save() }.disabled(model.loading) }
            }
        }
    }
}
