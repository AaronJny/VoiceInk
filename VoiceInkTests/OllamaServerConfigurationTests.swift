import Foundation
import LLMkit
import Testing

@testable import VoiceInk

private enum OllamaTransportTestError: Error {
    case unavailable
}

private final class OllamaTransportSpy: OllamaTransport, @unchecked Sendable {
    private let shouldFailFetch: Bool
    private var request: (
        baseURL: URL, model: String, temperature: Double, contextLength: Int?, keepAlive: String?
    )?
    private var preloadRequest: (baseURL: URL, model: String, contextLength: Int?, keepAlive: String)?

    init(shouldFailFetch: Bool = false) {
        self.shouldFailFetch = shouldFailFetch
    }

    func checkConnection(baseURL: URL) async -> Bool {
        !shouldFailFetch
    }

    func fetchModels(baseURL: URL) async throws -> [OllamaModel] {
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
        request = (baseURL, model, temperature, contextLength, keepAlive)
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
            options: OllamaGenerationOptions(temperature: 0.3, contextLength: 4096)
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

    private func makeDefaults() -> UserDefaults {
        let suiteName = "OllamaServerConfigurationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
