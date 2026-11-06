import AppIntents
import SwiftData
import WidgetKit

/// Marks a habit once for today. Used by the Habits widget's buttons.
struct ToggleHabitIntent: AppIntent {
    static var title: LocalizedStringResource = "Check Off Habit"
    static var isDiscoverable: Bool = false

    @Parameter(title: "Habit ID") var habitID: String

    init() {}
    init(habitID: String) { self.habitID = habitID }

    @MainActor
    func perform() async throws -> some IntentResult {
        let ctx = Storage.shared.mainContext
        if let habit = try ctx.fetch(FetchDescriptor<Habit>()).first(where: { $0.id.uuidString == habitID }) {
            habit.tap(on: .now)
            try ctx.save()
        }
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
