import SwiftUI
import SwiftData
import ActivityKit
import UserNotifications

/// Pomodoro-style focus timer. The countdown keeps running on the Lock Screen through a Live Activity,
/// and a local notification fires when each phase ends — even if Hush is closed.
@Observable
final class FocusTimer {
    static let shared = FocusTimer()

    var isRunning = false
    var isPaused = false
    var phase = "focus"
    var endsAt = Date()
    var remainingWhenPaused: TimeInterval = 0
    var round = 1
    var title = "Focus"
    var taskID: UUID?

    var focusMinutes: Int {
        get { UserDefaults.standard.object(forKey: "focusMinutes") as? Int ?? 25 }
        set { UserDefaults.standard.set(newValue, forKey: "focusMinutes") }
    }
    var breakMinutes: Int {
        get { UserDefaults.standard.object(forKey: "breakMinutes") as? Int ?? 5 }
        set { UserDefaults.standard.set(newValue, forKey: "breakMinutes") }
    }
    var rounds: Int {
        get { UserDefaults.standard.object(forKey: "focusRounds") as? Int ?? 4 }
        set { UserDefaults.standard.set(newValue, forKey: "focusRounds") }
    }

    @ObservationIgnored private var activity: Activity<FocusActivityAttributes>?
    @ObservationIgnored private var tick: Timer?
    @ObservationIgnored private var phaseStarted = Date()

    var remaining: TimeInterval { isPaused ? remainingWhenPaused : max(endsAt.timeIntervalSinceNow, 0) }
    var phaseLength: TimeInterval { Double((phase == "focus" ? focusMinutes : breakMinutes) * 60) }

    func start(title: String, taskID: UUID?, accentHex: String) {
        self.title = title.isEmpty ? "Focus" : title
        self.taskID = taskID
        round = 1
        begin(phase: "focus", accentHex: accentHex)
    }

    private func begin(phase: String, accentHex: String) {
        self.phase = phase
        isRunning = true
        isPaused = false
        phaseStarted = .now
        endsAt = Date().addingTimeInterval(Double((phase == "focus" ? focusMinutes : breakMinutes) * 60))
        scheduleEndNotification()
        startTicking()
        startOrUpdateActivity(accentHex: accentHex)
    }

    func pauseResume() {
        if isPaused {
            endsAt = Date().addingTimeInterval(remainingWhenPaused)
            isPaused = false
            scheduleEndNotification()
        } else {
            remainingWhenPaused = remaining
            isPaused = true
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["focus.end"])
        }
        updateActivity()
    }

    func skip(accentHex: String, context: ModelContext?) {
        advance(accentHex: accentHex, context: context)
    }

    func stop(context: ModelContext?) {
        logFocus(context: context)
        isRunning = false
        isPaused = false
        tick?.invalidate()
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["focus.end"])
        let a = activity
        activity = nil
        Task { await a?.end(nil, dismissalPolicy: .immediate) }
    }

    private func advance(accentHex: String, context: ModelContext?) {
        if phase == "focus" {
            logFocus(context: context)
            if round >= rounds { stop(context: nil); return }
            begin(phase: "break", accentHex: accentHex)
        } else {
            round += 1
            begin(phase: "focus", accentHex: accentHex)
        }
    }

    /// Adds the minutes actually focused to the task.
    private func logFocus(context: ModelContext?) {
        guard phase == "focus", let id = taskID, let ctx = context ?? lastContext else { return }
        let minutes = Int((Date().timeIntervalSince(phaseStarted) - (isPaused ? 0 : 0)) / 60)
        guard minutes > 0 else { return }
        if let t = (try? ctx.fetch(FetchDescriptor<TaskItem>()))?.first(where: { $0.id == id }) {
            t.focusMinutes += min(minutes, focusMinutes)
        }
        phaseStarted = .now
    }

    @ObservationIgnored var lastContext: ModelContext?
    @ObservationIgnored var accentHex = "4A8FE0"

    private func startTicking() {
        tick?.invalidate()
        tick = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, self.isRunning, !self.isPaused else { return }
            if self.endsAt <= Date() { self.advance(accentHex: self.accentHex, context: self.lastContext) }
        }
    }

    private func scheduleEndNotification() {
        let c = UNMutableNotificationContent()
        c.title = phase == "focus" ? "Focus done" : "Break over"
        c.body = phase == "focus" ? "Time for a \(breakMinutes)-minute break." : "Back to \(title)."
        c.sound = .default
        let req = UNNotificationRequest(identifier: "focus.end", content: c,
                                        trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(remaining, 1), repeats: false))
        Task {
            await Reminders.requestPermission()
            try? await UNUserNotificationCenter.current().add(req)
        }
    }

    private var state: FocusActivityAttributes.ContentState {
        .init(endsAt: endsAt, phase: phase, paused: isPaused, remainingWhenPaused: remainingWhenPaused, round: round, rounds: rounds)
    }

    private func startOrUpdateActivity(accentHex: String) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        if activity != nil { updateActivity(); return }
        let attrs = FocusActivityAttributes(title: title, accentHex: accentHex)
        activity = try? Activity.request(attributes: attrs, content: .init(state: state, staleDate: endsAt.addingTimeInterval(3600)))
    }

    private func updateActivity() {
        let s = state
        let a = activity
        Task { await a?.update(.init(state: s, staleDate: nil)) }
    }
}

/// Full-screen timer with a big ring.
struct FocusTimerView: View {
    var taskTitle: String = ""
    var taskID: UUID? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.palette) private var palette
    @Environment(AppSettings.self) private var settings
    @State private var timer = FocusTimer.shared

    var body: some View {
        @Bindable var t = timer
        NavigationStack {
            VStack(spacing: 26) {
                Spacer()
                if timer.isRunning {
                    Text(timer.phase == "focus" ? "Focus · round \(timer.round) of \(timer.rounds)" : "Break")
                        .font(.hush(.headline)).foregroundStyle(timer.phase == "focus" ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.green))
                    Text(timer.title).font(.hush(.title3)).multilineTextAlignment(.center)
                }
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    let total = timer.isRunning ? timer.phaseLength : Double(timer.focusMinutes * 60)
                    let rem = timer.isRunning ? timer.remaining : total
                    ZStack {
                        Circle().stroke(.quaternary, lineWidth: 14)
                        Circle()
                            .trim(from: 0, to: total > 0 ? rem / total : 0)
                            .stroke(timer.phase == "break" ? AnyShapeStyle(Color.green) : AnyShapeStyle(.tint), style: StrokeStyle(lineWidth: 14, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .animation(.linear(duration: 1), value: rem)
                        Text(format(rem)).font(.system(size: 60, weight: .light, design: .rounded)).monospacedDigit()
                    }
                    .frame(width: 260, height: 260)
                }
                if timer.isRunning {
                    HStack(spacing: 28) {
                        Button { timer.stop(context: context) } label: { Image(systemName: "stop.fill").frame(width: 60, height: 60).background(.quaternary, in: Circle()) }
                            .accessibilityLabel("Stop")
                        Button { timer.pauseResume() } label: {
                            Image(systemName: timer.isPaused ? "play.fill" : "pause.fill").font(.title).foregroundStyle(.white)
                                .frame(width: 80, height: 80).background(Circle().fill(.tint))
                        }
                        .accessibilityLabel(timer.isPaused ? "Resume" : "Pause")
                        Button { timer.skip(accentHex: settings.accentHex, context: context) } label: { Image(systemName: "forward.end.fill").frame(width: 60, height: 60).background(.quaternary, in: Circle()) }
                            .accessibilityLabel("Skip to next phase")
                    }
                    .font(.title3)
                    .buttonStyle(.plain)
                } else {
                    VStack(spacing: 12) {
                        Stepper("Focus: \(timer.focusMinutes) min", value: $t.focusMinutes, in: 5...120, step: 5)
                        Stepper("Break: \(timer.breakMinutes) min", value: $t.breakMinutes, in: 1...60)
                        Stepper("Rounds: \(timer.rounds)", value: $t.rounds, in: 1...12)
                    }
                    .padding()
                    .background(palette.surface, in: RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal)
                    Button {
                        timer.lastContext = context
                        timer.accentHex = settings.accentHex
                        timer.start(title: taskTitle, taskID: taskID, accentHex: settings.accentHex)
                    } label: {
                        Label("Start Focus", systemImage: "play.fill").font(.hush(.headline)).frame(maxWidth: 260, minHeight: 50)
                    }
                    .buttonStyle(.borderedProminent)
                }
                Spacer()
                Text("The timer keeps going on your Lock Screen and Dynamic Island.").font(.hush(.caption)).foregroundStyle(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(palette.background.ignoresSafeArea())
            .navigationTitle("Focus")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Close") { dismiss() } } }
        }
    }

    private func format(_ t: TimeInterval) -> String {
        let s = Int(t.rounded(.up))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
