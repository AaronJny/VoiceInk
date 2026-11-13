import AppKit
import SwiftUI
import Foundation
import LLMkit
import SwiftData
import Testing

@testable import VoiceInk

private enum OllamaTransportTestError: Error {
    case unavailable
}

private final class OllamaTransportSpy: OllamaTransport, @unchecked Sendable {
    var onFetch: (() -> Void)?
    private let shouldFailFetch: Bool
    private var failures: [LLMKitError]
    private(set) var generationCount = 0
    private(set) var capturedPrompt: String?
    private var request: (
        baseURL: URL, model: String, temperature: Double, contextLength: Int?, keepAlive: String?
    )?
    private var preloadRequest: (baseURL: URL, model: String, contextLength: Int?, keepAlive: String)?

    init(shouldFailFetch: Bool = false, failures: [LLMKitError] = []) {
        self.shouldFailFetch = shouldFailFetch
        self.failures = failures
    }

    func checkConnection(baseURL: URL) async -> Bool {
        !shouldFailFetch
    }

    func fetchModels(baseURL: URL) async throws -> [OllamaModel] {
        onFetch?()
        if shouldFailFetch { throw OllamaTransportTestError.unavailable }
        return []
    }

    func generate(
        baseURL: URL,
        model: String,
        prompt: String,
        systemPrompt: String,
        temperature: Double,
        contextLength: Int?,
        keepAlive: String?,
        timeout: TimeInterval
    ) async throws -> OllamaGenerationResult {
        generationCount += 1
        capturedPrompt = prompt
        request = (baseURL, model, temperature, contextLength, keepAlive)
        if !failures.isEmpty { throw failures.removeFirst() }
        return OllamaGenerationResult(
            text: " routed ",
            metrics: OllamaGenerationMetrics(
                totalDuration: nil,
                loadDuration: nil,
                promptEvaluationDuration: nil,
                evaluationDuration: nil
            )
        )
    }

    func preload(
        baseURL: URL,
        model: String,
        contextLength: Int?,
        keepAlive: String,
        timeout: TimeInterval
    ) async throws {
        preloadRequest = (baseURL, model, contextLength, keepAlive)
    }

    func capturedRequest() -> (
        baseURL: URL, model: String, temperature: Double, contextLength: Int?, keepAlive: String?
    )? {
        request
    }

    func capturedPreloadRequest() -> (
        baseURL: URL, model: String, contextLength: Int?, keepAlive: String
    )? {
        preloadRequest
    }
}

@Suite(.serialized)
struct OllamaServerConfigurationTests {
    @MainActor
    @Test func nativeModelDropdownSelectionPersistsAcrossReopeningAndServerSwitch() throws {
        let defaults = makeDefaults()
        let service = OllamaService(userDefaults: defaults, transport: OllamaTransportSpy())
        let ai = AIService(userDefaults: defaults, ollamaService: service)
        let local = try #require(ai.ollamaServers.first)
        let remote = ai.addOllamaServer(name: "Remote", baseURL: "http://remote:11434")
        let binding = OllamaModelComboBox.savedModelBinding(aiService: ai, serverID: remote.id)
        let coordinator = OllamaModelComboBox.Coordinator(model: binding)
        let control = OllamaModelComboBox.makeControl(coordinator: coordinator)
        OllamaModelComboBox.updateControl(control, model: binding.wrappedValue,
            modelNames: ["qwen3.5:9b", "ornith-1.5:9b"], coordinator: coordinator)
        control.selectItem(at: 1)
        // Exercise the actual native control delegate, not the service setter.
        coordinator.comboBoxSelectionDidChange(Notification(name: NSComboBox.selectionDidChangeNotification,
                                                           object: control))
        #expect(binding.wrappedValue == "ornith-1.5:9b")
        #expect(ai.ollamaServerConfiguration(id: local.id)?.preferredModel == local.preferredModel)
        ai.setPreferredOllamaModel("qwen3.5:9b", serverID: local.id)
        coordinator.model = OllamaModelComboBox.savedModelBinding(aiService: ai, serverID: local.id)
        // Same list, different server: selected index must follow the persisted value too.
        OllamaModelComboBox.updateControl(control, model: "qwen3.5:9b",
            modelNames: ["qwen3.5:9b", "ornith-1.5:9b"], coordinator: coordinator)
        #expect(control.indexOfSelectedItem == 0)
        #expect(control.stringValue == "qwen3.5:9b")
        #expect(ai.ollamaServerConfiguration(id: remote.id)?.preferredModel == "ornith-1.5:9b")
        let reopened = AIService(userDefaults: defaults,
            ollamaService: OllamaService(userDefaults: defaults, transport: OllamaTransportSpy()))
        let reopenedBinding = OllamaModelComboBox.savedModelBinding(aiService: reopened, serverID: remote.id)
        let reopenedCoordinator = OllamaModelComboBox.Coordinator(model: reopenedBinding)
        let reopenedControl = OllamaModelComboBox.makeControl(coordinator: reopenedCoordinator)
        OllamaModelComboBox.updateControl(reopenedControl, model: reopenedBinding.wrappedValue,
            modelNames: reopened.availableOllamaModels(serverID: remote.id), coordinator: reopenedCoordinator)
        #expect(reopenedControl.stringValue == "ornith-1.5:9b")
        #expect(reopened.defaultOllamaServerID == local.id)
    }

    @MainActor
    @Test func nativeModelDropdownTypingAndProgrammaticRefreshDoNotLoseSelection() async throws {
        let defaults = makeDefaults()
        let service = OllamaService(userDefaults: defaults, transport: OllamaTransportSpy())
        let ai = AIService(userDefaults: defaults, ollamaService: service)
        let remote = ai.addOllamaServer(name: "Remote", baseURL: "http://remote:11434")
        let binding = OllamaModelComboBox.savedModelBinding(aiService: ai, serverID: remote.id)
        let coordinator = OllamaModelComboBox.Coordinator(model: binding)
        let control = OllamaModelComboBox.makeControl(coordinator: coordinator)
        control.stringValue = "custom-model:latest"
        coordinator.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: control))
        _ = await ai.refreshOllamaServer(id: remote.id)
        OllamaModelComboBox.updateControl(control, model: binding.wrappedValue,
            modelNames: ai.availableOllamaModels(serverID: remote.id), coordinator: coordinator)
        #expect(control.stringValue == "custom-model:latest")
        #expect(control.objectValueOfSelectedItem as? String == "custom-model:latest")
        let restored = OllamaService(userDefaults: defaults, transport: OllamaTransportSpy())
        #expect(restored.server(withID: remote.id)?.preferredModel == "custom-model:latest")
        // Clearing is a real user edit, unlike loading an empty control for a different server.
        control.stringValue = ""
        coordinator.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: control))
        #expect(binding.wrappedValue.isEmpty)
    }

    @MainActor
    @Test func refreshCannotApplyTagsFromPreviousEndpoint() async throws {
        let defaults = makeDefaults()
        let transport = OllamaTransportSpy()
        let refreshing = OllamaService(userDefaults: defaults, transport: transport)
        let remote = refreshing.addServer(name: "Remote", baseURL: "http://old:11434")
        let editor = OllamaService(userDefaults: defaults, transport: OllamaTransportSpy())
        transport.onFetch = {
            var changed = remote
            changed.baseURL = "http://new:11434"
            changed.preferredModel = "ornith-1.5:9b"
            editor.updateServer(changed)
        }
        _ = await refreshing.refresh(serverID: remote.id)
        let restored = OllamaService(userDefaults: defaults, transport: OllamaTransportSpy())
        #expect(restored.server(withID: remote.id)?.baseURL == "http://new:11434")
        #expect(restored.server(withID: remote.id)?.preferredModel == "ornith-1.5:9b")
        #expect(refreshing.fetchedModelsByServerID[remote.id] == nil)
        #expect(refreshing.status(forServerID: remote.id) == .unknown)
    }

    @MainActor
    @Test func editingEndpointImmediatelyInvalidatesConnectionAndFetchedTags() async throws {
        let service = OllamaService(userDefaults: makeDefaults(), transport: OllamaTransportSpy())
        var remote = service.addServer(
            name: "Remote", baseURL: "http://old:11434", preferredModel: "ornith-1.5:9b")
        _ = await service.refresh(serverID: remote.id)
        #expect(service.status(forServerID: remote.id).isConnected)
        #expect(service.fetchedModelsByServerID[remote.id] != nil)
        remote.baseURL = "http://new:11434"
        service.updateServer(remote)
        #expect(service.status(forServerID: remote.id) == .unknown)
        #expect(service.fetchedModelsByServerID[remote.id] == nil)
        #expect(service.server(withID: remote.id)?.preferredModel == "ornith-1.5:9b")
    }

    @Test func editorRestoresRemoteSelectionWithoutChangingDefault() {
        let local = OllamaServerConfiguration(name: "Local", baseURL: "http://localhost:11434")
        let remote = OllamaServerConfiguration(name: "Remote", baseURL: "http://remote:11434")
        #expect(OllamaServerConfiguration.editorSelection(
            savedID: remote.id, defaultID: local.id, servers: [local, remote]) == remote.id)
        #expect(OllamaServerConfiguration.editorSelection(
            savedID: remote.id, defaultID: local.id, servers: [local]) == local.id)
    }

    @MainActor
    @Test func manualRemoteModelSurvivesEmptyTagsAndReload() async throws {
        let defaults = makeDefaults()
        let service = OllamaService(userDefaults: defaults, transport: OllamaTransportSpy())
        let remote = service.addServer(name: "Remote", baseURL: "http://remote:11434")
        service.setPreferredModel("ornith-1.5:9b", forServerID: remote.id)
        _ = await service.refresh(serverID: remote.id)
        #expect(service.modelNames(forServerID: remote.id).contains("ornith-1.5:9b"))
        let restored = OllamaService(userDefaults: defaults, transport: OllamaTransportSpy())
        #expect(restored.server(withID: remote.id)?.preferredModel == "ornith-1.5:9b")
        #expect(restored.modelNames(forServerID: remote.id).contains("ornith-1.5:9b"))
    }

    @Test func staleInstanceEditsPreserveOtherInstancesDefaultAndModel() throws {
        let defaults = makeDefaults()
        let first = OllamaService(userDefaults: defaults, transport: OllamaTransportSpy())
        let remote = first.addServer(name: "Remote", baseURL: "http://remote:11434")
        let stale = OllamaService(userDefaults: defaults, transport: OllamaTransportSpy())
        first.setPreferredModel("ornith-1.5:9b", forServerID: remote.id)
        first.setDefaultServer(withID: remote.id)
        var renamed = remote
        renamed.name = "Renamed Remote"
        stale.updateServer(renamed)
        let restored = OllamaService(userDefaults: defaults, transport: OllamaTransportSpy())
        #expect(restored.defaultServerID == remote.id)
        #expect(restored.server(withID: remote.id)?.preferredModel == "ornith-1.5:9b")
        #expect(restored.server(withID: remote.id)?.name == "Renamed Remote")
    }

    @MainActor
    @Test func refreshDoesNotOverwriteConcurrentPreferenceChanges() async throws {
        let defaults = makeDefaults()
        let transport = OllamaTransportSpy()
        let refreshing = OllamaService(userDefaults: defaults, transport: transport)
        let remote = refreshing.addServer(name: "Remote", baseURL: "http://remote:11434")
        let editor = OllamaService(userDefaults: defaults, transport: OllamaTransportSpy())
        transport.onFetch = {
            editor.setPreferredModel("ornith-1.5:9b", forServerID: remote.id)
            editor.setDefaultServer(withID: remote.id)
        }
        _ = await refreshing.refresh(serverID: remote.id)
        let restored = OllamaService(userDefaults: defaults, transport: OllamaTransportSpy())
        #expect(restored.defaultServerID == remote.id)
        #expect(restored.server(withID: remote.id)?.preferredModel == "ornith-1.5:9b")
    }

    @MainActor
    @Test func refreshCannotResurrectServerDeletedWhileAwaitingTags() async throws {
        let defaults = makeDefaults()
        let transport = OllamaTransportSpy()
        let refreshing = OllamaService(userDefaults: defaults, transport: transport)
        let remote = refreshing.addServer(name: "Remote", baseURL: "http://remote:11434")
        let editor = OllamaService(userDefaults: defaults, transport: OllamaTransportSpy())
        transport.onFetch = { editor.removeServer(withID: remote.id) }
        _ = await refreshing.refresh(serverID: remote.id)
        let restored = OllamaService(userDefaults: defaults, transport: OllamaTransportSpy())
        #expect(restored.server(withID: remote.id) == nil)
        #expect(refreshing.fetchedModelsByServerID[remote.id] == nil)
    }

    @Test func migratesLegacySettingsOnceWithoutDeletingThem() throws {
        let defaults = makeDefaults()
        defaults.set("http://legacy-host:11434", forKey: "ollamaBaseURL")
        defaults.set("legacy-model", forKey: "ollamaSelectedModel")

        let firstService = OllamaService(userDefaults: defaults)
        let firstServer = try #require(firstService.defaultServer)
        let secondService = OllamaService(userDefaults: defaults)
        let payloadData = try #require(defaults.data(forKey: OllamaService.serverListKey))
        let payload = try JSONDecoder().decode(OllamaServerListPayload.self, from: payloadData)

        #expect(payload.version == OllamaServerListPayload.currentVersion)
        #expect(firstServer.baseURL == "http://legacy-host:11434")
        #expect(firstServer.preferredModel == "legacy-model")
        #expect(firstServer.lastKnownModelNames == ["legacy-model"])
        #expect(secondService.defaultServerID == firstServer.id)
        #expect(defaults.string(forKey: "ollamaBaseURL") == "http://legacy-host:11434")
        #expect(defaults.string(forKey: "ollamaSelectedModel") == "legacy-model")
    }

    @MainActor
    @Test func failedRefreshRetainsCachedModelsAndSelection() async throws {
        let defaults = makeDefaults()
        defaults.set("cached-model", forKey: "ollamaSelectedModel")
        let transport = OllamaTransportSpy(shouldFailFetch: true)
        let service = OllamaService(userDefaults: defaults, transport: transport)
        let serverID = try #require(service.defaultServerID)

        _ = await service.refresh(serverID: serverID)

        #expect(service.modelNames(forServerID: serverID) == ["cached-model"])
        #expect(service.server(withID: serverID)?.preferredModel == "cached-model")
        #expect(service.server(withID: serverID)?.lastKnownModelNames == ["cached-model"])
        #expect(service.status(forServerID: serverID).isConnected == false)
        #expect(service.status(forServerID: serverID).errorMessage != nil)
    }

    @Test func routesRequestToExactResolvedEndpointAndModel() async throws {
        let transport = OllamaTransportSpy()
        let service = OllamaService(userDefaults: makeDefaults(), transport: transport)
        let result = try await service.enhance(
            "transcript",
            withSystemPrompt: "system",
            model: "server-specific-model",
            baseURL: URL(string: "http://second-host:22000/root")!
        )
        let capturedRequest = transport.capturedRequest()
        let request = try #require(capturedRequest)

        #expect(result == "routed")
        #expect(request.baseURL.absoluteString == "http://second-host:22000/root")
        #expect(request.model == "server-specific-model")
        #expect(request.temperature == 0.3)
        #expect(request.contextLength == nil)
        #expect(request.keepAlive == nil)
    }

    @Test func localRequestUsesBoundedContextAndExtendedResidencyByDefault() async throws {
        let transport = OllamaTransportSpy()
        let service = OllamaService(userDefaults: makeDefaults(), transport: transport)

        _ = try await service.enhance(
            "transcript",
            withSystemPrompt: "system",
            model: "qwen3.5:4b",
            baseURL: URL(string: "http://127.0.0.1:11434")!
        )
        let request = try #require(transport.capturedRequest())

        #expect(request.contextLength == 4096)
        #expect(request.keepAlive == "30m")
    }

    @Test func disablingPrewarmRestoresServerDefaultResidency() async throws {
        let defaults = makeDefaults()
        defaults.set(false, forKey: OllamaService.prewarmEnabledKey)
        let transport = OllamaTransportSpy()
        let service = OllamaService(userDefaults: defaults, transport: transport)

        _ = try await service.enhance(
            "transcript",
            withSystemPrompt: "system",
            model: "qwen3.5:4b",
            baseURL: URL(string: "http://localhost:11434")!
        )
        let request = try #require(transport.capturedRequest())

        #expect(request.contextLength == 4096)
        #expect(request.keepAlive == nil)
    }

    @Test func preloadsOnlyLoopbackOllamaServers() async throws {
        let localTransport = OllamaTransportSpy()
        let localService = OllamaService(userDefaults: makeDefaults(), transport: localTransport)
        try await localService.preload(
            model: "qwen3.5:4b",
            baseURL: URL(string: "http://[::1]:11434")!
        )
        let preload = try #require(localTransport.capturedPreloadRequest())

        #expect(preload.model == "qwen3.5:4b")
        #expect(preload.contextLength == 4096)
        #expect(preload.keepAlive == "30m")

        let remoteTransport = OllamaTransportSpy()
        let remoteService = OllamaService(userDefaults: makeDefaults(), transport: remoteTransport)
        try await remoteService.preload(
            model: "qwen3.6:27b",
            baseURL: URL(string: "http://192.168.200.66:11434")!
        )

        #expect(remoteTransport.capturedPreloadRequest() == nil)
    }

    @Test func generateRequestEncodesOllamaOptionsAtTheDocumentedLevel() throws {
        let request = OllamaGenerateRequest(
            model: "qwen3.5:4b",
            prompt: "transcript",
            system: "system",
            stream: false,
            think: false,
            keepAlive: "30m",
            options: OllamaRequestOptions(temperature: 0.3, contextLength: 4096)
        )
        let data = try JSONEncoder().encode(request)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let options = try #require(object["options"] as? [String: Any])

        #expect(object["temperature"] == nil)
        #expect(object["keep_alive"] as? String == "30m")
        #expect(object["think"] as? Bool == false)
        #expect(options["temperature"] as? Double == 0.3)
        #expect(options["num_ctx"] as? Int == 4096)
    }

    @MainActor
    @Test func unifiedCompletionPreservesExplicitModeEndpoint() async throws {
        let defaults = makeDefaults()
        let transport = OllamaTransportSpy()
        let service = OllamaService(userDefaults: defaults, transport: transport)
        let aiService = AIService(userDefaults: defaults, ollamaService: service)
        let endpoint = URL(string: "http://second-host:22000/root")!

        let result = try await aiService.performChatCompletion(
            provider: .ollama,
            modelName: "mode-specific-model",
            messages: [.user("transcript")],
            systemPrompt: "unchanged system context",
            localUserPrompt: "transcript",
            ollamaBaseURL: endpoint
        )

        let request = try #require(transport.capturedRequest())
        #expect(result.text == "routed")
        #expect(request.baseURL == endpoint)
        #expect(request.model == "mode-specific-model")
    }

    @MainActor
    @Test func assistantFollowUpKeepsInitialModeEndpointAfterDefaultChanges() async throws {
        let defaults = makeDefaults()
        let transport = OllamaTransportSpy()
        let service = OllamaService(userDefaults: defaults, transport: transport)
        service.baseURL = "http://default-a:11434"
        let aiService = AIService(userDefaults: defaults, ollamaService: service)
        let endpoint = URL(string: "http://mode-b:22000/root")!
        let session = AssistantSession()
        session.beginInitialResponse(
            transcript: "initial private question", provider: .ollama,
            modelName: "mode-b-model", ollamaBaseURL: endpoint,
            modeName: "Respond", modeEmoji: nil, promptName: "Locked prompt"
        )
        session.finishInitialResponse("initial reply", systemPrompt: "system context")
        service.baseURL = "http://new-default-c:11434"
        session.beginFollowUp("follow-up question")
        let container = try ModelContainer(
            for: Transcription.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let chat = AssistantChatService(modelContext: container.mainContext, aiService: aiService)

        let reply = try await chat.requestAssistantReply(
            provider: .ollama, modelName: session.modelName,
            ollamaBaseURL: session.ollamaBaseURL,
            systemPrompt: session.systemPrompt, messages: session.messages
        )

        #expect(reply.text == "routed")
        #expect(transport.capturedRequest()?.baseURL == endpoint)
        #expect(transport.capturedRequest()?.model == "mode-b-model")
        #expect(transport.capturedPrompt?.contains("initial private question") == true)
        #expect(transport.capturedPrompt?.contains("initial reply") == true)
        #expect(transport.capturedPrompt?.contains("follow-up question") == true)
        session.reset()
        #expect(session.ollamaBaseURL == nil)
    }

    @MainActor
    @Test func assistantWithoutSnapshotEndpointDoesNotContactDefaultServer() async throws {
        let defaults = makeDefaults()
        let transport = OllamaTransportSpy()
        let service = OllamaService(userDefaults: defaults, transport: transport)
        service.baseURL = "http://default-a:11434"
        let aiService = AIService(userDefaults: defaults, ollamaService: service)
        let container = try ModelContainer(
            for: Transcription.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let chat = AssistantChatService(modelContext: container.mainContext, aiService: aiService)
        do {
            _ = try await chat.requestAssistantReply(
                provider: .ollama, modelName: "mode-b-model", ollamaBaseURL: nil,
                systemPrompt: "system context", messages: []
            )
            Issue.record("Expected a missing endpoint error")
        } catch let error as EnhancementError {
            guard case .notConfigured = error else {
                Issue.record("Expected notConfigured, got \(error)")
                return
            }
        }
        #expect(transport.generationCount == 0)
    }

    @Test func timeoutRetryStaysOnSameEndpointAndIsBounded() async throws {
        let transport = OllamaTransportSpy(failures: [.timeout, .timeout])
        let service = OllamaService(userDefaults: makeDefaults(), transport: transport)
        let endpoint = URL(string: "http://second-host:22000/root")!
        do {
            _ = try await service.enhance(
                "transcript", withSystemPrompt: "system", model: "mode-model",
                baseURL: endpoint, retryOnTimeout: true
            )
            Issue.record("Expected timeout after one retry")
        } catch let error as LocalAIError {
            guard case .timeout = error else {
                Issue.record("Expected timeout, got \(error)")
                return
            }
        }
        #expect(transport.generationCount == 2)
        #expect(transport.capturedRequest()?.baseURL == endpoint)
        #expect(transport.capturedRequest()?.model == "mode-model")
    }

    @Test func nonTimeoutFailureIsNotRetried() async throws {
        let transport = OllamaTransportSpy(failures: [.httpError(statusCode: 500, message: "failure")])
        let service = OllamaService(userDefaults: makeDefaults(), transport: transport)
        do {
            _ = try await service.enhance(
                "transcript", withSystemPrompt: "system", model: "mode-model",
                baseURL: URL(string: "http://second-host:22000")!, retryOnTimeout: true
            )
            Issue.record("Expected server error")
        } catch let error as LocalAIError {
            guard case .serverError = error else {
                Issue.record("Expected server error, got \(error)")
                return
            }
        }
        #expect(transport.generationCount == 1)
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "OllamaServerConfigurationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
