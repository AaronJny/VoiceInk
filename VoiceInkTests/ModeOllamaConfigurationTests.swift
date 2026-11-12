import Foundation
import Testing

@testable import VoiceInk

@Suite(.serialized)
struct ModeOllamaConfigurationTests {
    @Test func oldModeConfigDecodesWithoutServerID() throws {
        let original = ModeConfig(
            name: "Legacy Ollama",
            isAIEnhancementEnabled: true,
            selectedAIProvider: AIProvider.ollama.rawValue,
            selectedAIModel: "legacy-model"
        )
        var object = try #require(
            try JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        object.removeValue(forKey: "selectedOllamaServerID")

        let decoded = try JSONDecoder().decode(
            ModeConfig.self,
            from: JSONSerialization.data(withJSONObject: object)
        )

        #expect(decoded.selectedOllamaServerID == nil)
        #expect(decoded.selectedAIProvider == AIProvider.ollama.rawValue)
        #expect(decoded.selectedAIModel == "legacy-model")
    }

    @Test func newModeConfigRoundTripsServerID() throws {
        let serverID = UUID()
        let original = ModeConfig(
            name: "Remote Ollama",
            isAIEnhancementEnabled: true,
            selectedAIProvider: AIProvider.ollama.rawValue,
            selectedAIModel: "remote-model",
            selectedOllamaServerID: serverID
        )

        let decoded = try JSONDecoder().decode(
            ModeConfig.self,
            from: JSONEncoder().encode(original)
        )

        #expect(decoded.selectedOllamaServerID == serverID)
    }

    @Test func oldBackupDecodesWithoutOllamaServers() throws {
        let backup = try JSONDecoder().decode(
            BackupFile.self,
            from: Data(#"{"version":"legacy"}"#.utf8)
        )

        #expect(backup.ollamaServers == nil)
        #expect(backup.defaultOllamaServerID == nil)
    }

    @MainActor
    @Test func explicitOfflineOllamaRemainsResolvedProvider() {
        let suiteName = "ModeOllamaConfigurationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let ollamaService = OllamaService(userDefaults: defaults)
        let aiService = AIService(userDefaults: defaults, ollamaService: ollamaService)

        #expect(aiService.configuredProviders.contains(.ollama))
        #expect(!aiService.connectedProviders.contains(.ollama))
        #expect(aiService.ollamaServerConfiguration(id: nil)?.id == ollamaService.defaultServerID)
        #expect(aiService.ollamaServerConfiguration(id: UUID()) == nil)
        #expect(
            ModeRuntimeResolver.resolvedProvider(
                providerName: AIProvider.ollama.rawValue,
                aiService: aiService
            ) == .ollama
        )
    }
}
