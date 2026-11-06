import SwiftUI
import AVFoundation

@Observable
final class MemoRecorder: NSObject, AVAudioRecorderDelegate {
    var isRecording = false
    var elapsed: TimeInterval = 0
    var level: Float = 0
    var levels: [Float] = Array(repeating: 0, count: 40)
    var errorMessage: String?
    @ObservationIgnored private var recorder: AVAudioRecorder?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var url: URL?

    func start() async {
        guard await AVAudioApplication.requestRecordPermission() else {
            errorMessage = "Hush needs microphone access. You can allow it in iPhone Settings → Apps → Hush."
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)
            let file = FileManager.default.temporaryDirectory.appendingPathComponent("memo-\(UUID().uuidString).m4a")
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
            ]
            let r = try AVAudioRecorder(url: file, settings: settings)
            r.isMeteringEnabled = true
            r.delegate = self
            guard r.record() else { errorMessage = "Recording couldn't start."; return }
            recorder = r
            url = file
            isRecording = true
            elapsed = 0
            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                guard let self, let r = self.recorder else { return }
                r.updateMeters()
                self.elapsed = r.currentTime
                let db = r.averagePower(forChannel: 0)
                let normalized = max(0, min(1, (db + 50) / 50))
                self.level = normalized
                self.levels.removeFirst()
                self.levels.append(normalized)
            }
        } catch {
            errorMessage = "Recording couldn't start: \(error.localizedDescription)"
        }
    }

    /// Stops and returns the audio data; the temporary file is deleted.
    func stop() -> Data? {
        timer?.invalidate()
        timer = nil
        recorder?.stop()
        recorder = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        guard let url else { return nil }
        defer { try? FileManager.default.removeItem(at: url); self.url = nil }
        return try? Data(contentsOf: url)
    }

    func cancel() { _ = stop() }
}

struct MemoRecorderView: View {
    var onSave: (Data, TimeInterval) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette
    @State private var recorder = MemoRecorder()

    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                Spacer()
                Text(format(recorder.elapsed))
                    .font(.system(size: 54, weight: .light, design: .rounded))
                    .monospacedDigit()
                HStack(alignment: .center, spacing: 3) {
                    ForEach(recorder.levels.indices, id: \.self) { i in
                        Capsule()
                            .fill(recorder.isRecording ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary))
                            .frame(width: 4, height: max(4, CGFloat(recorder.levels[i]) * 70))
                    }
                }
                .frame(height: 74)
                .animation(.linear(duration: 0.1), value: recorder.levels)
                Button {
                    if recorder.isRecording {
                        let time = recorder.elapsed
                        if let data = recorder.stop() { onSave(data, time) }
                        dismiss()
                    } else {
                        Task { await recorder.start() }
                    }
                } label: {
                    ZStack {
                        Circle().stroke(.secondary.opacity(0.4), lineWidth: 4).frame(width: 84, height: 84)
                        if recorder.isRecording {
                            RoundedRectangle(cornerRadius: 8).fill(.red).frame(width: 32, height: 32)
                        } else {
                            Circle().fill(.red).frame(width: 66, height: 66)
                        }
                    }
                }
                .accessibilityLabel(recorder.isRecording ? "Stop and save" : "Start recording")
                Text(recorder.isRecording ? "Tap to stop and save" : "Tap to record")
                    .font(.hush(.footnote)).foregroundStyle(.secondary)
                if let e = recorder.errorMessage {
                    Text(e).font(.hush(.footnote)).foregroundStyle(.red).multilineTextAlignment(.center).padding(.horizontal)
                }
                Spacer()
                Text("Memos are encrypted and stay on this iPhone.")
                    .font(.hush(.caption)).foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(palette.background)
            .navigationTitle("Voice Memo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { recorder.cancel(); dismiss() }
                }
            }
            .interactiveDismissDisabled(recorder.isRecording)
        }
    }

    private func format(_ t: TimeInterval) -> String {
        let s = Int(t)
        return String(format: "%d:%02d.%d", s / 60, s % 60, Int((t - Double(s)) * 10))
    }
}
