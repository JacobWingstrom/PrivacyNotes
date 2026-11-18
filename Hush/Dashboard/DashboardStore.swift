import Foundation
import SwiftData

/// Live data for the online Home widgets, refreshed on each widget's own schedule while Home is open,
/// plus a rolling history (kept on this device) for the charts in each widget's detail view.
@MainActor
@Observable
final class DashboardStore {
    static let shared = DashboardStore()

    private(set) var payloads: [UUID: WidgetPayload] = [:]
    private(set) var errors: [UUID: String] = [:]
    private(set) var loading: Set<UUID> = []
    private(set) var updated: [UUID: Date] = [:]
    private(set) var history: [UUID: [HistorySample]] = [:]

    @ObservationIgnored private var lastCounters: [UUID: (Date, Double, Double)] = [:]
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    private init() { loadHistory() }

    func isDue(_ w: HomeWidget) -> Bool {
        guard let last = updated[w.id] else { return true }
        return Date().timeIntervalSince(last) >= Double(max(w.refreshMinutes, 1) * 60) - 5
    }

    func refreshDue(_ widgets: [HomeWidget]) async {
        await withTaskGroup(of: Void.self) { group in
            for w in widgets where w.isOnline && isDue(w) && !loading.contains(w.id) {
                group.addTask { await self.refresh(w) }
            }
        }
    }

    /// Pull to refresh: everything online, now.
    func refreshAll(_ widgets: [HomeWidget]) async {
        await withTaskGroup(of: Void.self) { group in
            for w in widgets where w.isOnline { group.addTask { await self.refresh(w) } }
        }
    }

    func refresh(_ w: HomeWidget) async {
        guard w.isOnline, !loading.contains(w.id) else { return }
        loading.insert(w.id)
        defer { loading.remove(w.id) }
        do {
            var payload = try await DashboardSources.fetch(w, homelabURLs: homelabURLs())
            if case .server(var s) = payload {
                fillRates(&s, id: w.id)
                payload = .server(s)
            }
            payloads[w.id] = payload
            errors[w.id] = nil
            record(payload, for: w.id)
        } catch {
            errors[w.id] = error.localizedDescription
        }
        updated[w.id] = Date()
    }

    func forget(_ id: UUID) {
        payloads[id] = nil
        history[id] = nil
        updated[id] = nil
        scheduleSave()
    }

    private func homelabURLs() -> [(String, String)] {
        let services = (try? Storage.shared.mainContext.fetch(FetchDescriptor<LabService>())) ?? []
        return services.filter { $0.deletedAt == nil && !$0.url.trimmed.isEmpty }.map { ($0.name.isEmpty ? $0.url : $0.name, $0.url) }
    }

    /// Network counters → bytes per second, using the previous reading.
    private func fillRates(_ s: inout ServerSnapshot, id: UUID) {
        guard s.netRx == nil, let rx = s.netRxTotal, let tx = s.netTxTotal else { return }
        let now = Date()
        if let last = lastCounters[id], now.timeIntervalSince(last.0) > 1, rx >= last.1, tx >= last.2 {
            let (t, prx, ptx) = last
            let dt = now.timeIntervalSince(t)
            s.netRx = (rx - prx) / dt
            s.netTx = (tx - ptx) / dt
        }
        lastCounters[id] = (now, rx, tx)
    }

    // MARK: History

    private func record(_ p: WidgetPayload, for id: UUID) {
        var v: [String: Double] = [:]
        switch p {
        case .server(let s):
            v["cpu"] = s.cpu
            v["mem"] = s.memPercent
            if let l = s.load.first { v["load"] = l }
            if let t = s.hottest { v["temp"] = t }
            if let d = s.fullestDisk, d.total > 0 { v["disk"] = d.used / d.total * 100 }
            if let r = s.netRx { v["rx"] = r }
            if let t = s.netTx { v["tx"] = t }
        case .containers(let list):
            v["running"] = Double(list.filter(\.running).count)
            v["cpu"] = list.compactMap(\.cpu).reduce(0, +)
            v["mem"] = list.compactMap(\.memory).reduce(0, +)
        case .monitor(let list):
            for m in list {
                v["ms:" + m.name] = m.up ? m.ms : -1
                v["up:" + m.name] = m.up ? 1 : 0
            }
        case .dns(let d):
            v["total"] = d.total
            v["blocked"] = d.blocked
            v["percent"] = d.percent
        case .markets(let q):
            for x in q { v[x.symbol] = x.price }
        case .weather(let w):
            v["temp"] = w.temperature
        case .custom(let fields, _):
            for f in fields { if let n = f.number { v[f.label] = n } }
        case .news, .releases:
            return
        }
        guard !v.isEmpty else { return }
        var list = history[id] ?? []
        if let last = list.last, Date().timeIntervalSince(last.t) < 30 { list.removeLast() }
        list.append(HistorySample(t: Date(), v: v))
        // About a week at one reading a minute.
        let cutoff = Date().addingTimeInterval(-8 * 86400)
        list.removeAll { $0.t < cutoff }
        if list.count > 10_000 { list.removeFirst(list.count - 10_000) }
        history[id] = list
        scheduleSave()
    }

    private static var historyURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("dashboard-history.json")
    }

    private func loadHistory() {
        guard let data = try? Data(contentsOf: Self.historyURL),
              let decoded = try? JSONDecoder().decode([String: [HistorySample]].self, from: data) else { return }
        for (k, v) in decoded { if let id = UUID(uuidString: k) { history[id] = v } }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            let snapshot = Dictionary(uniqueKeysWithValues: history.map { ($0.key.uuidString, $0.value) })
            if let data = try? JSONEncoder().encode(snapshot) {
                try? data.write(to: Self.historyURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            }
        }
    }

    /// Samples since `since` for one value.
    func series(_ id: UUID, _ key: String, since: Date) -> [(Date, Double)] {
        (history[id] ?? []).filter { $0.t >= since }.compactMap { s in s.v[key].map { (s.t, $0) } }
    }
}
