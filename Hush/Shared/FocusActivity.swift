import Foundation
import ActivityKit

/// Shared between the app (which starts the timer) and the widget extension (which draws it
/// on the Lock Screen and Dynamic Island).
struct FocusActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var endsAt: Date
        var phase: String          // focus, break
        var paused: Bool
        var remainingWhenPaused: Double
        var round: Int
        var rounds: Int
    }

    var title: String
    var accentHex: String
}
