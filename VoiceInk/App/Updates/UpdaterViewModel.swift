import Combine
import Foundation
import Sparkle
import SwiftUI
import os

@MainActor
final class UpdaterViewModel: NSObject, ObservableObject, SPUUpdaterDelegate {
    private enum DefaultsKey {
        static let legacyAutomaticChecks = "VoiceInkChecksForUpdatesOnLaunch"
        static let legacyInteractedVersions = "VoiceInkInteractedUpdateVersions"
        static let legacyAvailableUpdate = "VoiceInkAvailableUpdate"
    }

    private let defaults = UserDefaults.standard
    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "updates")
    private var subscriptions = Set<AnyCancellable>()
    #if !LOCAL_BUILD
    private lazy var updaterController = SPUStandardUpdaterController(
        startingUpdater: false,
        updaterDelegate: self,
        userDriverDelegate: nil
    )
    #endif

    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var automaticallyChecksForUpdates = false

    override init() {
        super.init()

        #if !LOCAL_BUILD
        let updater = updaterController.updater

        // The Dashboard-only implementation kept its own preference and forced
        // Sparkle's preference off. Migrate the user's actual choice before
        // starting Sparkle, then let Sparkle own the preference and schedule.
        if let legacyPreference = defaults.object(forKey: DefaultsKey.legacyAutomaticChecks) as? Bool {
            updater.automaticallyChecksForUpdates = legacyPreference
            defaults.removeObject(forKey: DefaultsKey.legacyAutomaticChecks)
        }
        // Remove state left by the previous custom update reminders.
        defaults.removeObject(forKey: DefaultsKey.legacyInteractedVersions)
        defaults.removeObject(forKey: DefaultsKey.legacyAvailableUpdate)

        automaticallyChecksForUpdates = updater.automaticallyChecksForUpdates

        updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
        updater.publisher(for: \.automaticallyChecksForUpdates)
            .sink { [weak self] enabled in
                guard let self else { return }
                self.automaticallyChecksForUpdates = enabled
                self.logger.notice("Automatic update checks enabled=\(enabled, privacy: .public)")
            }
            .store(in: &subscriptions)

        updaterController.startUpdater()
        #endif
        // Custom LOCAL_BUILD releases are updated from our GitHub build artifacts.
        // Do not instantiate Sparkle or migrate/change the official update preferences.
    }

    func setAutomaticallyChecksForUpdates(_ value: Bool) {
        #if !LOCAL_BUILD
        guard automaticallyChecksForUpdates != value else { return }
        updaterController.updater.automaticallyChecksForUpdates = value
        #endif
    }

    func checkForUpdates() {
        #if !LOCAL_BUILD
        guard canCheckForUpdates else { return }

        // This action also brings an existing update/progress window into focus.
        // Manual checks remain available when automatic checks are off.
        logger.notice("Update check requested source=manual")
        updaterController.checkForUpdates(nil)
        #endif
    }

    func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
        #if LOCAL_BUILD
        throw NSError(
            domain: "com.prakashjoshipax.voiceink.updates",
            code: 2,
            userInfo: [NSLocalizedDescriptionKey: "This custom build is updated through its GitHub build artifacts."]
        )
        #else
        // Protect every non-manual entry point, including a scheduled check
        // queued just before the user disabled automatic checks.
        guard updateCheck == .updates || updater.automaticallyChecksForUpdates else {
            logger.notice("Update check blocked reason=automatic-checks-disabled")
            throw NSError(
                domain: "com.prakashjoshipax.voiceink.updates",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Automatic update checks are disabled."]
            )
        }
        logger.notice("Update check started kind=\(updateCheck.rawValue, privacy: .public)")
        #endif
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        logger.notice("Update found build=\(item.versionString, privacy: .public) version=\(item.displayVersionString, privacy: .public)")
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        logger.notice("Update check result=no-update")
    }

    func updater(
        _ updater: SPUUpdater,
        userDidMake choice: SPUUserUpdateChoice,
        forUpdate updateItem: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        logger.notice("Update choice=\(choice.rawValue, privacy: .public) build=\(updateItem.versionString, privacy: .public)")
    }

    func updater(_ updater: SPUUpdater, willScheduleUpdateCheckAfterDelay delay: TimeInterval) {
        logger.notice("Update check scheduled delaySeconds=\(Int(delay), privacy: .public)")
    }

    func updaterWillNotScheduleUpdateCheck(_ updater: SPUUpdater) {
        logger.notice("Update scheduler inactive automaticChecks=\(self.automaticallyChecksForUpdates, privacy: .public)")
    }

    func updater(
        _ updater: SPUUpdater,
        didFinishUpdateCycleFor updateCheck: SPUUpdateCheck,
        error: Error?
    ) {
        if let error {
            let error = error as NSError
            logger.notice("Update cycle finished kind=\(updateCheck.rawValue, privacy: .public) errorDomain=\(error.domain, privacy: .public) errorCode=\(error.code, privacy: .public)")
        } else {
            logger.notice("Update cycle finished kind=\(updateCheck.rawValue, privacy: .public) result=completed")
        }
    }
}

struct CheckForUpdatesView: View {
    @ObservedObject var updaterViewModel: UpdaterViewModel

    var body: some View {
        Button("Check for Updates…", action: updaterViewModel.checkForUpdates)
            .disabled(!updaterViewModel.canCheckForUpdates)
    }
}
