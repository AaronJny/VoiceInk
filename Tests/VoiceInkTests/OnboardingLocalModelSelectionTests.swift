import Foundation
import Testing
@testable import VoiceInk

@Suite("Onboarding local model selection")
@MainActor
struct OnboardingLocalModelSelectionTests {
    @Test func preservesPreviouslySelectedWhisperModel() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("ggml-large-v3", forKey: "CurrentTranscriptionModel")

        let coordinator = OnboardingCoordinator(defaults: defaults)

        #expect(coordinator.selectedLocalTranscriptionModel?.name == "ggml-large-v3")
        #expect(coordinator.selectedOnboardingTranscriptionModelName == "ggml-large-v3")
    }

    @Test func preservesPreviouslySelectedExperimentalQwenModel() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(TranscribeCppModelCatalog.qwen3ASR1_7B.modelName, forKey: "CurrentTranscriptionModel")

        let coordinator = OnboardingCoordinator(defaults: defaults)

        #expect(coordinator.selectedLocalTranscriptionModel?.name == TranscribeCppModelCatalog.qwen3ASR1_7B.modelName)
    }

    @Test func freshInstallDefaultsToParakeetV3() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let coordinator = OnboardingCoordinator(defaults: defaults)

        #expect(coordinator.selectedLocalTranscriptionModel?.name == "parakeet-tdt-0.6b-v3")
    }

    #if LOCAL_BUILD
    @Test func customBuildDisablesOfficialUpdaterWithoutChangingPreferences() {
        let keys = [
            "SUEnableAutomaticChecks", "SUAutomaticallyUpdate",
            "VoiceInkChecksForUpdatesOnLaunch", "VoiceInkInteractedUpdateVersions",
            "VoiceInkAvailableUpdate"
        ]
        func savedPreferences() -> NSDictionary {
            var values: [String: Any] = [:]
            for key in keys {
                if let value = UserDefaults.standard.object(forKey: key) { values[key] = value }
            }
            return values as NSDictionary
        }
        let before = savedPreferences()
        let updater = UpdaterViewModel()
        updater.setAutomaticallyChecksForUpdates(true)
        updater.checkForUpdates()

        #expect(!updater.canCheckForUpdates)
        #expect(!updater.automaticallyChecksForUpdates)
        #expect(before.isEqual(savedPreferences()))
    }
    #endif

    private func makeDefaults() -> (UserDefaults, String) {
        let suiteName = "OnboardingLocalModelSelectionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, suiteName)
    }
}
