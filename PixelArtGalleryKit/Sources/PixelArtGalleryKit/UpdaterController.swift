// UpdaterController.swift

#if os(macOS) && canImport(Sparkle)
import AppKit
import Sparkle

/// Wraps Sparkle's `SPUStandardUpdaterController` for the direct-download macOS
/// build so the app menu can offer "Check for Updates…" (#0038).
///
/// The Sparkle feed (`SUFeedURL`) and EdDSA public key (`SUPublicEDKey`) are
/// wired in a separate issue (#0039), so this controller must be safe to ship
/// before either exists: `isConfigured` reports whether the feed URL is
/// present, the updater is only started when it is (starting an unconfigured
/// updater would surface Sparkle's automatic-check permission prompt and,
/// eventually, feed errors), and `checkForUpdates()` is a logged no-op until
/// then. The menu item disables itself off `isConfigured`.
///
/// The package's default `@MainActor` isolation applies here, which matches
/// Sparkle's expectation that the standard updater controller is driven from
/// the main thread.
public final class UpdaterController {
    /// The single app-wide updater. Created lazily on first use (the app menu
    /// touches it when building commands).
    public static let shared = UpdaterController()

    private let controller: SPUStandardUpdaterController

    /// Whether Sparkle has a feed to check: `SUFeedURL` in the app's
    /// Info.plist is a non-empty string. False until #0039 lands.
    public var isConfigured: Bool {
        guard let feedURL = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String else {
            return false
        }
        return !feedURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Whether a user-initiated update check can begin right now: the feed is
    /// configured and Sparkle isn't already mid-session. Suitable for menu
    /// enable/disable.
    public var canCheckForUpdates: Bool {
        isConfigured && controller.updater.canCheckForUpdates
    }

    private init() {
        // Defer starting until we know the feed is configured; an unconfigured
        // updater has nothing to check and would still schedule sessions and
        // prompt for automatic-check permission.
        controller = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )

        if isConfigured {
            controller.startUpdater()
            AppLog.updates.info("Sparkle updater started")
        } else {
            AppLog.updates.info("Sparkle updater not started: SUFeedURL is not configured (#0039)")
        }
    }

    /// Runs a user-initiated update check, or logs and returns if the feed URL
    /// isn't configured yet (#0039).
    public func checkForUpdates() {
        guard isConfigured else {
            AppLog.updates.info("Check for Updates requested but SUFeedURL is not configured; ignoring (#0039)")
            return
        }
        controller.checkForUpdates(nil)
    }
}
#endif
