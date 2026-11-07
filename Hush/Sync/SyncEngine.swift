import Foundation
import SwiftData
import CryptoKit
import UIKit
import WidgetKit

/// Runs a sync: pull what changed on the server, then push what changed here.
/// Does nothing at all unless sync has been set up in Settings > Sync.
@MainActor
@Observable
final class SyncEngine {
    static let shared = SyncEngine()

    enum Phase: Equatable { case idle, syncing, ok, failed }

    var phase: Phase = .idle
    var message = ""
    var lastSync: Date? = UserDefaults.standard.object(forKey: "sync.lastSync") as? Date
    var lastPulled = 0
    var lastPushed = 0
    var lastError: String? = nil

    @ObservationIgnored private var running = false
    @ObservationIgnored private var again = false
    @ObservationIgnored private var timer: Task<Void, Never>?

    private var container: ModelContainer { Storage.shared }

    // MARK: lifecycle

    /// Called when Hush becomes active: sync now, then every few minutes while open.
    func appBecameActive() {
        guard SyncSettings.isConfigured else { return }
        if !running { Task { await sync() } }
        timer?.cancel()
        let minutes = SyncSettings.intervalMinutes
        guard minutes > 0 else { return }
        timer = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(minutes * 60))
                if Task.isCancelled { break }
                await self?.sync()
            }
        }
    }

    /// Called when Hush goes to the background: one last sync while iOS gives us time.
    func appWentToBackground() {
        timer?.cancel()
        timer = nil
        guard SyncSettings.isConfigured else { return }
        var bg: UIBackgroundTaskIdentifier = .invalid
        bg = UIApplication.shared.beginBackgroundTask(withName: "HushSync") {
            UIApplication.shared.endBackgroundTask(bg)
        }
        Task {
            await sync()
            UIApplication.shared.endBackgroundTask(bg)
        }
    }

    // MARK: setup

    func client(url: String? = nil, token: String? = nil) throws -> SyncClient {
        guard let u = SyncSettings.normalizedURL(url ?? SyncSettings.serverURL) else { throw SyncError.badAddress }
        guard let t = token ?? SyncSettings.token, !t.isEmpty else { throw SyncError.notConfigured }
        return SyncClient(base: u, token: t.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Checks the address and token; returns whether the server already has a passphrase.
    func test(url: String, token: String) async throws -> (SyncClient.Health, SyncClient.Vault) {
        let c = try client(url: url, token: token)
        let h = try await c.health()
        let v = try await c.vault()
        return (h, v)
    }

    /// First device: choose the passphrase that encrypts everything.
    func create(url: String, token: String, passphrase: String) async throws {
        let c = try client(url: url, token: token)
        let salt = Passcode.randomBytes(16)
        let key = await Task.detached { SyncCrypto.deriveKey(passphrase, salt: salt, iterations: SyncCrypto.iterations) }.value
        let vault = SyncClient.Vault(initialized: true, salt: salt.base64EncodedString(), iterations: SyncCrypto.iterations,
                                     check: SyncCrypto.makeCheck(key).base64EncodedString())
        try await c.putVault(vault)
        save(url: url, token: token, key: key)
        await sync()
    }

    /// Another device (or this one again): enter the existing passphrase.
    func join(url: String, token: String, passphrase: String) async throws {
        let c = try client(url: url, token: token)
        let v = try await c.vault()
        guard v.initialized, let s = v.salt, let salt = Data(base64Encoded: s), let chk = v.check, let check = Data(base64Encoded: chk) else {
            throw SyncError.noPassphrase
        }
        let iterations = v.iterations ?? SyncCrypto.iterations
        let key = await Task.detached { SyncCrypto.deriveKey(passphrase, salt: salt, iterations: iterations) }.value
        guard SyncCrypto.verifyCheck(check, key: key) else { throw SyncError.wrongPassphrase }
        save(url: url, token: token, key: key)
        await sync()
    }

    private func save(url: String, token: String, key: SymmetricKey) {
        SyncSettings.serverURL = SyncSettings.normalizedURL(url)?.absoluteString ?? url
        SyncSettings.token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        SyncSettings.key = key
        SyncState.reset()
        SyncSettings.enabled = true
        lastError = nil
        appBecameActive()
    }

    /// Stops syncing. Everything stays on this iPhone; the server copy is left alone.
    func disconnect() {
        timer?.cancel()
        timer = nil
        SyncSettings.enabled = false
        SyncSettings.token = nil
        SyncSettings.key = nil
        SyncState.reset()
        UserDefaults.standard.removeObject(forKey: "sync.lastSync")
        lastSync = nil
        phase = .idle
        message = ""
        lastError = nil
    }

    /// Deletes everything on the server (records, attachments, passphrase), then disconnects.
    func eraseServer() async throws {
        try await client().erase()
        disconnect()
    }

    /// Re-download everything on next sync (used after turning the Vault option on).
    func resetPullPosition() {
        var s = SyncState.load()
        s.serverSeq = 0
        s.save()
    }

    // MARK: sync

    func sync() async {
        guard SyncSettings.isConfigured, let key = SyncSettings.key else { return }
        if running { again = true; return }
        running = true
        defer { running = false }
        phase = .syncing
        message = "Syncing…"
        do {
            let c = try client()
            var run = SyncRun(client: c, key: key, ctx: container.mainContext, state: SyncState.load())
            try await run.perform { [weak self] text in self?.message = text }
            lastPulled = run.pulled
            lastPushed = run.pushed
            lastSync = .now
            UserDefaults.standard.set(lastSync, forKey: "sync.lastSync")
            lastError = nil
            phase = .ok
            message = run.pulled + run.pushed == 0 ? "Up to date" : "Received \(run.pulled), sent \(run.pushed)"
            if run.pulled > 0 { WidgetCenter.shared.reloadAllTimelines() }
        } catch {
            lastError = error.localizedDescription
            phase = .failed
            message = error.localizedDescription
        }
        if again {
            again = false
            running = false
            await sync()
        }
    }
}

/// One sync pass. Kept separate from the engine so the steps read top to bottom.
@MainActor
struct SyncRun {
    let client: SyncClient
    let key: SymmetricKey
    let ctx: ModelContext
    var state: SyncState
    var pulled = 0
    var pushed = 0

    private struct Local {
        let model: any SyncModel
        let type: String
        var fields: [String: Any]
        var blobs: [String: (raw: Data, sealed: Bool)]
        var hash: String
    }

    private struct Envelope {
        var type: String
        var id: String
        var fields: [String: Any]
        var modifiedAt: Double
    }

    private var index: [String: Local] = [:]
    private var excluded: Set<String> { SyncSettings.includeVault ? [] : [VaultItem.syncType] }

    init(client: SyncClient, key: SymmetricKey, ctx: ModelContext, state: SyncState) {
        self.client = client
        self.key = key
        self.ctx = ctx
        self.state = state
    }

    mutating func perform(progress: (String) -> Void) async throws {
        progress("Reading this iPhone…")
        buildIndex()
        progress("Checking the server…")
        try await pull(progress: progress)
        try ctx.save()
        buildIndex()
        try await push(progress: progress)
        try ctx.save()
        try await collectGarbage()
        state.save()
    }

    // MARK: local records

    private mutating func encode(_ m: any SyncModel) -> Local {
        var st = state
        let key = self.key
        let e = SyncEncoder { raw, sealed in
            let rawHash = SyncCrypto.sha256(raw)
            var plainHash = rawHash
            if sealed {
                if let known = st.plainHashes[rawHash] {
                    plainHash = known
                } else {
                    guard let plain = DataCrypto.open(raw) else { return nil }
                    plainHash = SyncCrypto.sha256(plain)
                    st.plainHashes[rawHash] = plainHash
                }
            }
            return SyncCrypto.blobID(plainHash: plainHash, key: key)
        }
        m.syncEncode(e)
        state = st
        let type = Swift.type(of: m).syncType
        return Local(model: m, type: type, fields: e.fields, blobs: e.blobs,
                     hash: SyncCrypto.sha256(SyncCrypto.canonicalJSON(e.fields)))
    }

    private mutating func buildIndex() {
        index = [:]
        for t in SyncRegistry.models where !excluded.contains(t.syncType) {
            for m in t.syncFetchAll(ctx) {
                index[m.syncID.uuidString] = encode(m)
            }
        }
    }

    // MARK: envelopes

    private func seal(_ l: Local, id: String) -> String? {
        let modified = (l.fields["updatedAt"] as? Double) ?? Date().timeIntervalSince1970
        let obj: [String: Any] = ["v": 1, "type": l.type, "id": id, "fields": l.fields, "modifiedAt": modified]
        return SyncCrypto.seal(SyncCrypto.canonicalJSON(obj), key: key, context: "record:" + id)?.base64EncodedString()
    }

    private func open(_ r: SyncClient.Record) -> Envelope? {
        guard let s = r.data, let data = Data(base64Encoded: s),
              let plain = SyncCrypto.open(data, key: key, context: "record:" + r.id),
              let obj = try? JSONSerialization.jsonObject(with: plain) as? [String: Any],
              let type = obj["type"] as? String, let fields = obj["fields"] as? [String: Any] else { return nil }
        return Envelope(type: type, id: r.id, fields: fields, modifiedAt: (obj["modifiedAt"] as? NSNumber)?.doubleValue ?? 0)
    }

    /// Newest edit wins. Records without an edit time prefer the server copy.
    private func remoteWins(_ local: Local, _ remote: Envelope) -> Bool {
        if let lu = local.fields["updatedAt"] as? Double, let ru = (remote.fields["updatedAt"] as? NSNumber)?.doubleValue {
            return ru >= lu
        }
        return true
    }

    // MARK: pull

    private mutating func pull(progress: (String) -> Void) async throws {
        var more = true
        while more {
            let page = try await client.pull(since: state.serverSeq)
            for r in page.records {
                try await applyRemote(r)
            }
            state.serverSeq = max(state.serverSeq, page.seq)
            more = page.more && !page.records.isEmpty
            if more { progress("Receiving… \(pulled)") }
            state.save()
        }
    }

    /// Applies one server record here, unless this iPhone already has that exact version.
    private mutating func applyRemote(_ r: SyncClient.Record) async throws {
        let entry = state.entries[r.id]
        if let entry, entry.seq == r.seq { return }      // already have it (often our own push)
        let local = index[r.id]
        let localChanged = local.map { $0.hash != entry?.hash } ?? false

        if r.deleted {
            if let local {
                if localChanged && entry != nil {
                    // Edited here after it was deleted elsewhere: keep it, it will be pushed again.
                    state.entries[r.id]?.seq = r.seq
                    return
                }
                local.model.syncDelete(from: ctx)
                index[r.id] = nil
                pulled += 1
            }
            state.entries[r.id] = nil
            return
        }

        guard let env = open(r) else { return }          // not ours or damaged; leave it
        if excluded.contains(env.type) { return }
        guard let t = SyncRegistry.models.first(where: { $0.syncType == env.type }) else { return }  // newer app's type

        if let local, localChanged {
            let remoteHash = SyncCrypto.sha256(SyncCrypto.canonicalJSON(env.fields))
            if local.hash == remoteHash {
                state.entries[r.id] = .init(type: env.type, hash: local.hash, seq: r.seq)
                return
            }
            if !remoteWins(local, env) {
                // Ours is newer: remember the server version so the push replaces it.
                state.entries[r.id] = .init(type: env.type, hash: entry?.hash ?? "", seq: r.seq)
                return
            }
            // Server copy wins; keep this iPhone's text in the note's history.
            if let note = local.model as? Note, !note.isLocked {
                ctx.insert(NoteVersion(noteID: note.id, title: note.title, body: note.body))
            }
        }

        var blobs: [String: Data] = [:]
        var missing: [String] = []
        for id in SyncDecoder.blobIDs(in: env.fields) {
            if let b = local?.blobs[id], let plain = b.sealed ? DataCrypto.open(b.raw) : b.raw { blobs[id] = plain } else { missing.append(id) }
        }
        for (id, data) in try await download(missing) { blobs[id] = data }
        let model = local?.model ?? t.syncInsertNew(ctx)
        if local == nil, let u = UUID(uuidString: r.id) { model.syncSetID(u) }
        var plainHashes = state.plainHashes
        let d = SyncDecoder(fields: env.fields, blobData: blobs) { raw, plain in
            plainHashes[SyncCrypto.sha256(raw)] = SyncCrypto.sha256(plain)
        }
        model.syncDecode(d)
        state.plainHashes = plainHashes
        let now = encode(model)
        index[r.id] = now
        state.entries[r.id] = .init(type: env.type, hash: now.hash, seq: r.seq)
        for id in now.blobs.keys { state.uploadedBlobs.insert(id) }
        pulled += 1
    }

    private func download(_ ids: [String]) async throws -> [String: Data] {
        var out: [String: Data] = [:]
        for id in ids {
            let enc = try await client.getBlob(id)
            guard let plain = SyncCrypto.open(enc, key: key, context: "blob:" + id) else { continue }
            out[id] = plain
        }
        return out
    }

    // MARK: push

    private mutating func push(progress: (String) -> Void) async throws {
        var outgoing: [(id: String, local: Local?)] = []
        for (id, l) in index where state.entries[id]?.hash != l.hash { outgoing.append((id, l)) }
        for (id, e) in state.entries where index[id] == nil && !excluded.contains(e.type) { outgoing.append((id, nil)) }
        guard !outgoing.isEmpty else { return }

        var batch: [SyncClient.PushRecord] = []
        var batchLocals: [String: Local] = [:]
        var bytes = 0
        for item in outgoing {
            if let l = item.local {
                for (bid, b) in l.blobs where !state.uploadedBlobs.contains(bid) {
                    progress("Uploading attachments…")
                    guard let plain = b.sealed ? DataCrypto.open(b.raw) : b.raw,
                          let enc = SyncCrypto.seal(plain, key: key, context: "blob:" + bid) else { continue }
                    try await client.putBlob(bid, enc)
                    state.uploadedBlobs.insert(bid)
                }
                guard let data = seal(l, id: item.id) else { continue }
                batch.append(.init(id: item.id, base: state.entries[item.id]?.seq ?? 0, force: false, deleted: false, data: data))
                batchLocals[item.id] = l
                bytes += data.count
            } else {
                batch.append(.init(id: item.id, base: state.entries[item.id]?.seq ?? 0, force: false, deleted: true, data: nil))
            }
            if batch.count >= 100 || bytes > 8 << 20 {
                progress("Sending… \(pushed)/\(outgoing.count)")
                try await send(batch, batchLocals)
                batch = []
                batchLocals = [:]
                bytes = 0
                state.save()
            }
        }
        if !batch.isEmpty {
            progress("Sending… \(pushed)/\(outgoing.count)")
            try await send(batch, batchLocals)
        }
    }

    private mutating func send(_ batch: [SyncClient.PushRecord], _ locals: [String: Local]) async throws {
        let resp = try await client.push(batch)
        var retry: [SyncClient.PushRecord] = []
        for res in resp.results {
            if res.ok == true, let seq = res.seq {
                if let l = locals[res.id] {
                    state.entries[res.id] = .init(type: l.type, hash: l.hash, seq: seq)
                } else {
                    state.entries[res.id] = nil
                }
                pushed += 1
            } else if let cur = res.current {
                // Changed elsewhere since we last looked: merge it like a pull, then retry if ours wins.
                try await applyRemote(cur)
                if let l = index[res.id], state.entries[res.id]?.hash != l.hash, let data = seal(l, id: res.id) {
                    retry.append(.init(id: res.id, base: cur.seq, force: false, deleted: false, data: data))
                }
            }
        }
        if !retry.isEmpty {
            let again = try await client.push(retry)
            for res in again.results where res.ok == true {
                if let seq = res.seq, let l = index[res.id] {
                    state.entries[res.id] = .init(type: l.type, hash: l.hash, seq: seq)
                    pushed += 1
                }
            }
        }
    }

    // MARK: cleanup

    /// Removes attachments this iPhone uploaded that no record uses any more.
    private mutating func collectGarbage() async throws {
        let used = Set(index.values.flatMap { $0.blobs.keys })
        let unused = state.uploadedBlobs.subtracting(used)
        guard !unused.isEmpty, excluded.isEmpty else { return }
        for id in unused.prefix(50) {
            try? await client.deleteBlob(id)
            state.uploadedBlobs.remove(id)
        }
    }
}
