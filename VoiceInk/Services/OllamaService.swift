import Foundation
import LLMkit
import SwiftUI
import os

class OllamaService: ObservableObject {
    static let defaultBaseURL = "http://localhost:11434"
    static let serverListKey = "ollamaServerConfigurationsV1"
    static let prewarmEnabledKey = "PrewarmModelOnWake"
    static let localContextLength = 4096
    static let localKeepAlive = "30m"

    @Published private(set) var servers: [OllamaServerConfiguration]
    @Published private(set) var defaultServerID: UUID?
    @Published private(set) var serverStatuses: [UUID: OllamaServerStatus] = [:]
    @Published private(set) var fetchedModelsByServerID: [UUID: [OllamaModel]] = [:]

    private let userDefaults: UserDefaults
    private let transport: any OllamaTransport
    private let defaultTemperature: Double = 0.3
    private let logger = Logger(
        subsystem: "com.prakashjoshipax.voiceink",
        category: "Ollama"
    )

    init(
        userDefaults: UserDefaults = .standard,
        transport: any OllamaTransport = LiveOllamaTransport()
    ) {
        self.userDefaults = userDefaults
        self.transport = transport

        if let data = userDefaults.data(forKey: Self.serverListKey),
            let payload = try? JSONDecoder().decode(OllamaServerListPayload.self, from: data)
        {
            self.servers = payload.servers
            self.defaultServerID = payload.defaultServerID.flatMap { id in
                payload.servers.contains(where: { $0.id == id }) ? id : payload.servers.first?.id
            } ?? payload.servers.first?.id
        } else {
            let model = userDefaults.string(forKey: "ollamaSelectedModel") ?? "llama2"
            let migratedServer = OllamaServerConfiguration(
                name: "Local Ollama",
                baseURL: userDefaults.string(forKey: "ollamaBaseURL") ?? Self.defaultBaseURL,
                preferredModel: model,
                lastKnownModelNames: model.isEmpty ? [] : [model]
            )
            self.servers = [migratedServer]
            self.defaultServerID = migratedServer.id
            persistServers()
        }
    }

    var defaultServer: OllamaServerConfiguration? {
        guard let defaultServerID else { return nil }
        return servers.first { $0.id == defaultServerID }
    }

    var baseURL: String {
        get { defaultServer?.baseURL ?? Self.defaultBaseURL }
        set {
            if var server = defaultServer {
                server.baseURL = newValue
                updateServer(server)
            } else {
                _ = addServer(name: "Local Ollama", baseURL: newValue)
            }
            userDefaults.set(newValue, forKey: "ollamaBaseURL")
        }
    }

    var selectedModel: String {
        get {
            guard let defaultServer else { return "llama2" }
            if !defaultServer.preferredModel.isEmpty { return defaultServer.preferredModel }
            return defaultServer.lastKnownModelNames.first ?? "llama2"
        }
        set {
            guard var server = defaultServer else { return }
            server.preferredModel = newValue
            updateServer(server)
            userDefaults.set(newValue, forKey: "ollamaSelectedModel")
        }
    }

    var availableModels: [OllamaModel] {
        guard let defaultServerID else { return [] }
        return fetchedModelsByServerID[defaultServerID] ?? []
    }

    var isConnected: Bool {
        guard let defaultServerID else { return false }
        return serverStatuses[defaultServerID]?.isConnected == true
    }

    var isLoadingModels: Bool {
        serverStatuses.values.contains(where: \.isRefreshing)
    }

    var isPrewarmEnabled: Bool {
        userDefaults.object(forKey: Self.prewarmEnabledKey) as? Bool ?? true
    }

    static func isLoopback(baseURL: URL) -> Bool {
        guard let host = baseURL.host?.lowercased() else { return false }
        return ["localhost", "127.0.0.1", "::1", "[::1]"].contains(host)
    }

    func server(withID id: UUID?) -> OllamaServerConfiguration? {
        guard let id else { return defaultServer }
        return servers.first { $0.id == id }
    }

    func modelNames(forServerID id: UUID?) -> [String] {
        guard let server = server(withID: id) else { return [] }
        return fetchedModelsByServerID[server.id]?.map(\.name) ?? server.lastKnownModelNames
    }

    func status(forServerID id: UUID) -> OllamaServerStatus {
        serverStatuses[id] ?? .unknown
    }

    @discardableResult
    func addServer(
        name: String,
        baseURL: String,
        preferredModel: String = ""
    ) -> OllamaServerConfiguration {
        let server = OllamaServerConfiguration(
            name: name,
            baseURL: baseURL,
            preferredModel: preferredModel,
            lastKnownModelNames: preferredModel.isEmpty ? [] : [preferredModel]
        )
        servers.append(server)
        if defaultServerID == nil {
            defaultServerID = server.id
        }
        persistServers()
        if defaultServerID == server.id { syncLegacyKeys() }
        return server
    }

    func addServer(_ server: OllamaServerConfiguration) {
        guard !servers.contains(where: { $0.id == server.id }) else { return }
        servers.append(server)
        if defaultServerID == nil {
            defaultServerID = server.id
        }
        persistServers()
        if defaultServerID == server.id { syncLegacyKeys() }
    }

    func updateServer(_ server: OllamaServerConfiguration) {
        guard let index = servers.firstIndex(where: { $0.id == server.id }) else { return }
        servers[index] = server
        persistServers()
        if defaultServerID == server.id { syncLegacyKeys() }
    }

    func setPreferredModel(_ model: String, forServerID id: UUID) {
        guard var server = server(withID: id) else { return }
        server.preferredModel = model
        updateServer(server)
    }

    func removeServer(withID id: UUID) {
        servers.removeAll { $0.id == id }
        serverStatuses[id] = nil
        fetchedModelsByServerID[id] = nil
        if defaultServerID == id {
            defaultServerID = servers.first?.id
        }
        persistServers()
        syncLegacyKeys()
    }

    func setDefaultServer(withID id: UUID) {
        guard servers.contains(where: { $0.id == id }) else { return }
        defaultServerID = id
        persistServers()
        syncLegacyKeys()
    }

    func replaceServers(_ servers: [OllamaServerConfiguration], defaultServerID: UUID?) {
        self.servers = servers
        self.defaultServerID = defaultServerID.flatMap { id in
            servers.contains(where: { $0.id == id }) ? id : servers.first?.id
        } ?? servers.first?.id
        serverStatuses = serverStatuses.filter { id, _ in servers.contains(where: { $0.id == id }) }
        fetchedModelsByServerID = fetchedModelsByServerID.filter { id, _ in
            servers.contains(where: { $0.id == id })
        }
        persistServers()
        syncLegacyKeys()
    }

    private func persistServers() {
        let payload = OllamaServerListPayload(servers: servers, defaultServerID: defaultServerID)
        if let data = try? JSONEncoder().encode(payload) {
            userDefaults.set(data, forKey: Self.serverListKey)
        }
    }

    private func syncLegacyKeys() {
        guard let defaultServer else { return }
        userDefaults.set(defaultServer.baseURL, forKey: "ollamaBaseURL")
        userDefaults.set(defaultServer.preferredModel, forKey: "ollamaSelectedModel")
    }

    @MainActor
    func checkConnection() async {
        guard let defaultServerID else { return }
        await checkConnection(serverID: defaultServerID)
    }

    @MainActor
    func checkConnection(serverID: UUID) async {
        guard let server = server(withID: serverID), let url = URL(string: server.baseURL) else {
            serverStatuses[serverID] = OllamaServerStatus(
                isConnected: false, isRefreshing: false,
                errorMessage: LocalAIError.invalidURL.localizedDescription)
            return
        }

        let isConnected = await transport.checkConnection(baseURL: url)
        serverStatuses[serverID] = OllamaServerStatus(
            isConnected: isConnected,
            isRefreshing: false,
            errorMessage: isConnected ? nil : LocalAIError.serviceUnavailable.localizedDescription
        )
    }

    @MainActor
    func refreshModels() async {
        _ = await refreshConnectionAndModels()
    }

    @MainActor
    func refreshConnectionAndModels() async -> Result<[OllamaModel], Error> {
        guard let defaultServerID else { return .failure(LocalAIError.serviceUnavailable) }
        return await refresh(serverID: defaultServerID)
    }

    @MainActor
    func refresh(serverID: UUID) async -> Result<[OllamaModel], Error> {
        guard let server = server(withID: serverID), let url = URL(string: server.baseURL) else {
            let error = LocalAIError.invalidURL
            serverStatuses[serverID] = OllamaServerStatus(
                isConnected: false, isRefreshing: false, errorMessage: error.localizedDescription)
            return .failure(error)
        }

        let previousStatus = status(forServerID: serverID)
        serverStatuses[serverID] = OllamaServerStatus(
            isConnected: previousStatus.isConnected, isRefreshing: true, errorMessage: nil)

        do {
            let models = try await transport.fetchModels(baseURL: url)
            fetchedModelsByServerID[serverID] = models
            if let index = servers.firstIndex(where: { $0.id == serverID }) {
                servers[index].lastKnownModelNames = models.map(\.name)
                if servers[index].preferredModel.isEmpty, let firstModel = models.first?.name {
                    servers[index].preferredModel = firstModel
                }
                persistServers()
                if defaultServerID == serverID { syncLegacyKeys() }
            }
            serverStatuses[serverID] = OllamaServerStatus(
                isConnected: true, isRefreshing: false, errorMessage: nil)
            return .success(models)
        } catch {
            serverStatuses[serverID] = OllamaServerStatus(
                isConnected: false, isRefreshing: false, errorMessage: error.localizedDescription)
            return .failure(error)
        }
    }

    @MainActor
    func refreshAllServers() async {
        for serverID in servers.map(\.id) {
            _ = await refresh(serverID: serverID)
        }
    }

    func enhance(
        _ text: String,
        withSystemPrompt systemPrompt: String? = nil,
        model: String? = nil,
        baseURL: URL,
        timeout: TimeInterval = 30
    ) async throws -> String {
        guard let systemPrompt = systemPrompt else {
            throw LocalAIError.invalidRequest
        }

        let trimmedModel = model?.trimmingCharacters(in: .whitespacesAndNewlines)
        let requestModel = (trimmedModel?.isEmpty == false ? trimmedModel : nil) ?? selectedModel
        let isLocal = Self.isLoopback(baseURL: baseURL)
        do {
            let result = try await transport.generate(
                baseURL: baseURL,
                model: requestModel,
                prompt: text,
                systemPrompt: systemPrompt,
                temperature: defaultTemperature,
                contextLength: isLocal ? Self.localContextLength : nil,
                keepAlive: isLocal && isPrewarmEnabled ? Self.localKeepAlive : nil,
                timeout: timeout
            )
            logMetrics(result.metrics, model: requestModel)
            return result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch let error as LLMKitError {
            throw mapLLMKitError(error)
        }
    }

    func preload(model: String, baseURL: URL, timeout: TimeInterval = 60) async throws {
        guard isPrewarmEnabled, Self.isLoopback(baseURL: baseURL) else { return }

        do {
            try await transport.preload(
                baseURL: baseURL,
                model: model,
                contextLength: Self.localContextLength,
                keepAlive: Self.localKeepAlive,
                timeout: timeout
            )
        } catch let error as LLMKitError {
            throw mapLLMKitError(error)
        }
    }

    private func logMetrics(_ metrics: OllamaGenerationMetrics, model: String) {
        let totalMilliseconds = metrics.totalDuration.map { Double($0) / 1_000_000 } ?? 0
        let loadMilliseconds = metrics.loadDuration.map { Double($0) / 1_000_000 } ?? 0
        let promptMilliseconds = metrics.promptEvaluationDuration.map { Double($0) / 1_000_000 } ?? 0
        let evaluationMilliseconds = metrics.evaluationDuration.map { Double($0) / 1_000_000 } ?? 0
        logger.notice(
            "Generation model=\(model, privacy: .public) total=\(totalMilliseconds, format: .fixed(precision: 1), privacy: .public)ms load=\(loadMilliseconds, format: .fixed(precision: 1), privacy: .public)ms prompt=\(promptMilliseconds, format: .fixed(precision: 1), privacy: .public)ms eval=\(evaluationMilliseconds, format: .fixed(precision: 1), privacy: .public)ms"
        )
    }

    private func mapLLMKitError(_ error: LLMKitError) -> LocalAIError {
        switch error {
        case .invalidURL: return .invalidURL
        case .httpError(let statusCode, _):
            if statusCode == 404 { return .modelNotFound }
            if statusCode >= 500 { return .serverError }
            return .invalidResponse
        case .networkError: return .serviceUnavailable
        case .timeout: return .timeout
        default: return .invalidResponse
        }
    }
}

// MARK: - Error Types
enum LocalAIError: Error, LocalizedError {
    case invalidURL
    case serviceUnavailable
    case invalidResponse
    case modelNotFound
    case serverError
    case invalidRequest
    case timeout

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return String(localized: "Invalid Ollama server URL")
        case .serviceUnavailable:
            return String(localized: "Ollama service is not available")
        case .invalidResponse:
            return String(localized: "Invalid response from Ollama server")
        case .modelNotFound:
            return String(localized: "Selected model not found")
        case .serverError:
            return String(localized: "Ollama server error")
        case .invalidRequest:
            return String(localized: "System prompt is required")
        case .timeout:
            return String(localized: "Ollama request timed out")
        }
    }
}
