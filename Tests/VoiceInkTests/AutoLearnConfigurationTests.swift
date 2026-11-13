import Foundation
import Testing

@testable import VoiceInk

@Suite("AutoLearn configuration", .serialized)
struct AutoLearnConfigurationTests {
    private func withDefaults(_ body: (UserDefaults) throws -> Void) rethrows {
        let suite = "AutoLearnConfigurationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(defaults)
    }

    private func save(_ servers: [OllamaServerConfiguration], defaultID: UUID?, to defaults: UserDefaults) throws {
        defaults.set(try JSONEncoder().encode(OllamaServerListPayload(servers: servers, defaultServerID: defaultID)),
            forKey: OllamaService.serverListKey)
    }

    private func selectOllama(in defaults: UserDefaults, serverID: String = "") {
        defaults.set(AIProvider.ollama.rawValue, forKey: AutoLearnSettings.reviewerProviderKey)
        defaults.set("review-model", forKey: AutoLearnSettings.reviewerModelKey)
        defaults.set(serverID, forKey: AutoLearnSettings.reviewerOllamaServerKey)
    }

    @Test func localReviewNeedsNoModelOrServer() throws {
        try withDefaults { defaults in
            #expect(AutoLearnSettings.reviewerSelection(defaults: defaults) == nil)
            defaults.set("", forKey: AutoLearnSettings.reviewerProviderKey)
            #expect(AutoLearnSettings.reviewerSelection(defaults: defaults) == nil)
        }
    }

    @Test func cloudConfigurationIDsRemainCompatible() throws {
        try withDefaults { defaults in
            defaults.set(AIProvider.openAI.rawValue, forKey: AutoLearnSettings.reviewerProviderKey)
            defaults.set(" review-model ", forKey: AutoLearnSettings.reviewerModelKey)
            let selection = try #require(AutoLearnSettings.reviewerSelection(defaults: defaults))
            #expect(selection.modelName == "review-model")
            #expect(selection.configurationID == "pairs-v3|\(AIProvider.openAI.rawValue)|review-model")
            #expect(selection.ollamaBaseURL == nil)
        }
    }

    @Test func explicitRemoteReviewDoesNotUseDefaultLocalOrItsModel() throws {
        try withDefaults { defaults in
            let local = OllamaServerConfiguration(name: "Local", baseURL: "http://localhost:11434", preferredModel: "local-model")
            let remote = OllamaServerConfiguration(name: "Remote", baseURL: "http://remote.example:11434", preferredModel: "enhancement-model")
            try save([local, remote], defaultID: local.id, to: defaults)
            selectOllama(in: defaults, serverID: remote.id.uuidString)
            let selection = try #require(AutoLearnSettings.reviewerSelection(defaults: defaults))
            #expect(selection.ollamaServerID == remote.id.uuidString)
            #expect(selection.ollamaBaseURL == remote.baseURL)
            #expect(selection.modelName == "review-model")
        }
    }

    @Test func missingOrMalformedExplicitServerNeverFallsBack() throws {
        try withDefaults { defaults in
            let local = OllamaServerConfiguration(name: "Local", baseURL: "http://localhost:11434")
            try save([local], defaultID: local.id, to: defaults)
            for serverID in [UUID().uuidString, "invalid-id"] {
                selectOllama(in: defaults, serverID: serverID)
                let selection = try #require(AutoLearnSettings.reviewerSelection(defaults: defaults))
                #expect(selection.ollamaServerID == serverID)
                #expect(selection.ollamaBaseURL == nil)
                #expect(selection.modelName == "review-model")
            }
        }
    }

    @Test func serverURLChangeInvalidatesEarlierApproval() throws {
        try withDefaults { defaults in
            var server = OllamaServerConfiguration(name: "Remote", baseURL: "http://first.example:11434")
            try save([server], defaultID: server.id, to: defaults)
            selectOllama(in: defaults, serverID: server.id.uuidString)
            let before = try #require(AutoLearnSettings.reviewerSelection(defaults: defaults))
            server.baseURL = "http://second.example:11434"
            try save([server], defaultID: server.id, to: defaults)
            let after = try #require(AutoLearnSettings.reviewerSelection(defaults: defaults))
            #expect(before != after)
            #expect(before.configurationID != after.configurationID)
            #expect(!AutoLearnReviewEligibility.accepts(source: "Acmee", destination: "Acme",
                aiReviewConfigurationID: before.configurationID, reviewerSelection: after))
        }
    }

    @Test func legacyDefaultSelectionReadsCurrentStoredEndpoint() throws {
        try withDefaults { defaults in
            let first = OllamaServerConfiguration(name: "First", baseURL: "http://first.example:11434")
            let second = OllamaServerConfiguration(name: "Second", baseURL: "http://second.example:11434")
            try save([first, second], defaultID: first.id, to: defaults)
            selectOllama(in: defaults)
            let before = try #require(AutoLearnSettings.reviewerSelection(defaults: defaults))
            try save([first, second], defaultID: second.id, to: defaults)
            let after = try #require(AutoLearnSettings.reviewerSelection(defaults: defaults))
            #expect(before.ollamaBaseURL == first.baseURL)
            #expect(after.ollamaBaseURL == second.baseURL)
            #expect(before.configurationID != after.configurationID)
        }
    }

    @Test func unchangedDeliveredEnhancementCannotBecomeACorrection() {
        let delivered = "Please contact Acme tomorrow."
        let snapshot = AutoLearnFieldSnapshot(baselineFieldText: delivered, finalFieldText: delivered,
            pastedRange: NSRange(location: 0, length: delivered.utf16.count), originalPastedText: delivered)
        #expect(FinalSnapshotDiffEngine.revision(from: snapshot) == nil)
    }

    @Test func retainedManualCorrectionProducesCandidateButClearedFieldDoesNot() throws {
        let delivered = "Please contact Acmee tomorrow."
        let corrected = "Please contact Acme tomorrow."
        let range = NSRange(location: 0, length: delivered.utf16.count)
        let retained = AutoLearnFieldSnapshot(baselineFieldText: delivered, finalFieldText: corrected,
            pastedRange: range, originalPastedText: delivered)
        let revision = try #require(FinalSnapshotDiffEngine.revision(from: retained))
        #expect(!CorrectionDiffEngine.candidates(from: revision, usesAIReviewer: false).isEmpty)
        let cleared = AutoLearnFieldSnapshot(baselineFieldText: delivered, finalFieldText: "",
            pastedRange: range, originalPastedText: delivered)
        let deletion = try #require(FinalSnapshotDiffEngine.revision(from: cleared))
        #expect(deletion.corrected.isEmpty)
        #expect(CorrectionDiffEngine.candidates(from: deletion, usesAIReviewer: false).isEmpty)
    }
}
