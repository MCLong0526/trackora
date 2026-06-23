import AppIntents
import Foundation

/// App Intent + App Shortcut that opens Trackora's in-app
/// "Quick Add Expense" dialog.
///
/// **Why this exists**
/// iOS does not let third-party apps subscribe to the Back Tap
/// accessibility gesture directly — Apple reserves it. We expose an App
/// Shortcut so the action is reachable from Siri, the Shortcuts app, the
/// Action Button (iPhone 15 Pro+) and Spotlight.
///
/// **Back Tap visibility caveat**
/// Settings → Accessibility → Touch → Back Tap → Double Tap → Shortcut
/// only lists shortcuts saved into the user's *Shortcuts library* — it
/// does **not** list raw `AppShortcut`s automatically. To bind this to
/// Back Tap the user must:
///
///   1. Open the Shortcuts app.
///   2. Tap "+" → "Add Action".
///   3. Search "Quick Add Expense" and pick the Trackora action.
///   4. Tap the title to rename to e.g. "Quick Add Expense".
///   5. Save. The shortcut now appears in My Shortcuts.
///   6. Settings → Accessibility → Touch → Back Tap → Double Tap →
///      Shortcuts → "Quick Add Expense".
///
/// Once wired, a double-tap on the back of the phone runs this intent
/// and Trackora opens straight into the QuickAddSheet.
///
/// **How it works**
/// `openAppWhenRun = true` foregrounds Trackora. The intent writes a
/// transient flag to the App Group UserDefaults so the Flutter side
/// (see `lib/services/widget_intent_service.dart` →
/// `pendingQuickAdd*`) can drain it on resume and present the
/// `QuickAddSheet`. We avoid using the existing `trackora://quickadd`
/// URL deep-link because launching from an App Intent doesn't always
/// route a custom-scheme URL through the SceneDelegate reliably.
@available(iOS 16.0, *)
struct OpenQuickAddIntent: AppIntent {
    static var title: LocalizedStringResource = "Quick Add Expense"
    static var description = IntentDescription("Open Trackora and start a quick expense entry.")
    static var openAppWhenRun: Bool = true

    static let appGroup = "group.com.michaelchia.trackora"
    static let pendingKey = "pending_open_quickadd"

    init() {}

    func perform() async throws -> some IntentResult {
        if let defaults = UserDefaults(suiteName: Self.appGroup) {
            defaults.set(true, forKey: Self.pendingKey)
            defaults.set(Date().timeIntervalSince1970, forKey: "\(Self.pendingKey)_ts")
        }
        return .result()
    }
}

/// App Intent that captures a spoken expense phrase via Siri (Siri does the
/// speech-to-text natively) and hands it to the Flutter app for parsing and
/// confirmation. The phrase is written to the App Group UserDefaults under
/// `pending_voice_phrase`; the Flutter side drains it on resume (see
/// `lib/services/widget_intent_service.dart` → `consumePendingVoicePhrase`)
/// and opens a pre-filled entry. Nothing is saved without the user confirming.
@available(iOS 16.0, *)
struct VoiceAddExpenseIntent: AppIntent {
    static var title: LocalizedStringResource = "Add Expense by Voice"
    static var description = IntentDescription(
        "Say an expense like \u{201C}RM18 for lunch at Starbucks\u{201D} and Trackora opens a pre-filled entry to confirm."
    )
    static var openAppWhenRun: Bool = true

    static let appGroup = "group.com.michaelchia.trackora"
    static let pendingKey = "pending_voice_phrase"

    @Parameter(
        title: "Expense",
        description: "What you spent, e.g. RM18 for lunch at Starbucks",
        requestValueDialog: IntentDialog("What did you spend?")
    )
    var phrase: String

    init() {}
    init(phrase: String) { self.phrase = phrase }

    func perform() async throws -> some IntentResult {
        if let defaults = UserDefaults(suiteName: Self.appGroup) {
            defaults.set(phrase, forKey: Self.pendingKey)
            defaults.set(Date().timeIntervalSince1970, forKey: "\(Self.pendingKey)_ts")
        }
        return .result()
    }
}

/// Registers the App Shortcuts so they show up in:
///   - Siri ("Hey Siri, quick add expense")
///   - Shortcuts app (suggested)
///   - Spotlight
///   - Settings → Accessibility → Touch → Back Tap (as a Shortcut)
///   - Action Button (iPhone 15 Pro+)
///
/// Localized phrases give Siri a few natural-sounding triggers. Keep
/// the list short — Apple's matcher prefers concise phrases.
@available(iOS 16.0, *)
struct TrackoraAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenQuickAddIntent(),
            phrases: [
                "Quick add expense in \(.applicationName)",
                "Add expense in \(.applicationName)",
                "Log expense in \(.applicationName)",
            ],
            shortTitle: "Quick Add Expense",
            systemImageName: "plus.circle.fill"
        )
        AppShortcut(
            intent: VoiceAddExpenseIntent(),
            phrases: [
                "Add expense by voice in \(.applicationName)",
                "Voice add expense in \(.applicationName)",
                "Dictate expense in \(.applicationName)",
            ],
            shortTitle: "Add Expense by Voice",
            systemImageName: "mic.fill"
        )
    }
}
