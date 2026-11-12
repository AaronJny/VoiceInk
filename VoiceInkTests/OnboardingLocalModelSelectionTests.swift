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

    @Test func freshInstallDefaultsToParakeetV3() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let coordinator = OnboardingCoordinator(defaults: defaults)

        #expect(coordinator.selectedLocalTranscriptionModel?.name == "parakeet-tdt-0.6b-v3")
    }

    private func makeDefaults() -> (UserDefaults, String) {
        let suiteName = "OnboardingLocalModelSelectionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, suiteName)
    }
}
