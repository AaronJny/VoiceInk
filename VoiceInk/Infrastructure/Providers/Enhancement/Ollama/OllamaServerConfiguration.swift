import Foundation
import LLMkit

struct OllamaServerConfiguration: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var baseURL: String
    var preferredModel: String
    var lastKnownModelNames: [String]

    static func editorSelection(
        savedID: UUID?, defaultID: UUID?, servers: [OllamaServerConfiguration]
    ) -> UUID? {
        if let savedID, servers.contains(where: { $0.id == savedID }) { return savedID }
        if let defaultID, servers.contains(where: { $0.id == defaultID }) { return defaultID }
        return servers.first?.id
    }

    init(
        id: UUID = UUID(),
        name: String,
        baseURL: String,
        preferredModel: String = "",
        lastKnownModelNames: [String] = []
    ) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.preferredModel = preferredModel
        self.lastKnownModelNames = lastKnownModelNames
    }
}

struct OllamaServerStatus: Equatable {
    var isConnected = false
    var isRefreshing = false
    var errorMessage: String?

    static let unknown = OllamaServerStatus()
}

struct OllamaRequestOptions: Codable, Equatable, Sendable {
    let temperature: Double?
    let contextLength: Int?

    enum CodingKeys: String, CodingKey {
        case temperature
        case contextLength = "num_ctx"
    }
}

struct OllamaGenerateRequest: Encodable, Equatable, Sendable {
    let model: String
    let prompt: String?
    let system: String?
    let stream: Bool
    let think: Bool?
    let keepAlive: String?
    let options: OllamaRequestOptions?

    enum CodingKeys: String, CodingKey {
        case model, prompt, system, stream, think, options
        case keepAlive = "keep_alive"
    }
}

struct OllamaGenerationMetrics: Equatable, Sendable {
    let totalDuration: UInt64?
    let loadDuration: UInt64?
    let promptEvaluationDuration: UInt64?
    let evaluationDuration: UInt64?
}

struct OllamaGenerationResult: Equatable, Sendable {
    let text: String
    let metrics: OllamaGenerationMetrics
}

private struct OllamaGenerateResponse: Decodable {
    let response: String
    let totalDuration: UInt64?
    let loadDuration: UInt64?
    let promptEvaluationDuration: UInt64?
    let evaluationDuration: UInt64?

    enum CodingKeys: String, CodingKey {
        case response
        case totalDuration = "total_duration"
        case loadDuration = "load_duration"
        case promptEvaluationDuration = "prompt_eval_duration"
        case evaluationDuration = "eval_duration"
    }
}

private struct OllamaErrorResponse: Decodable {
    let error: String
}

protocol OllamaTransport {
    func checkConnection(baseURL: URL) async -> Bool
    func fetchModels(baseURL: URL) async throws -> [OllamaModel]
    func generate(
        baseURL: URL,
        model: String,
        prompt: String,
        systemPrompt: String,
        temperature: Double,
        contextLength: Int?,
        keepAlive: String?,
        timeout: TimeInterval
    ) async throws -> OllamaGenerationResult
    func preload(
        baseURL: URL,
        model: String,
        contextLength: Int?,
        keepAlive: String,
        timeout: TimeInterval
    ) async throws
}

struct LiveOllamaTransport: OllamaTransport {
    func checkConnection(baseURL: URL) async -> Bool {
        await OllamaClient.checkConnection(baseURL: baseURL)
    }

    func fetchModels(baseURL: URL) async throws -> [OllamaModel] {
        try await OllamaClient.fetchModels(baseURL: baseURL)
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
        try await performGenerate(
            baseURL: baseURL,
            requestBody: OllamaGenerateRequest(
                model: model,
                prompt: prompt,
                system: systemPrompt,
                stream: false,
                think: false,
                keepAlive: keepAlive,
                options: OllamaRequestOptions(
                    temperature: temperature,
                    contextLength: contextLength
                )
            ),
            timeout: timeout
        )
    }

    func preload(
        baseURL: URL,
        model: String,
        contextLength: Int?,
        keepAlive: String,
        timeout: TimeInterval
    ) async throws {
        _ = try await performGenerate(
            baseURL: baseURL,
            requestBody: OllamaGenerateRequest(
                model: model,
                prompt: nil,
                system: nil,
                stream: false,
                think: nil,
                keepAlive: keepAlive,
                options: OllamaRequestOptions(
                    temperature: nil,
                    contextLength: contextLength
                )
            ),
            timeout: timeout
        )
    }

    private func performGenerate(
        baseURL: URL,
        requestBody: OllamaGenerateRequest,
        timeout: TimeInterval
    ) async throws -> OllamaGenerationResult {
        let url = baseURL.appendingPathComponent("api/generate")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            request.httpBody = try JSONEncoder().encode(requestBody)
        } catch {
            throw LLMKitError.encodingError
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw LLMKitError.networkError("Ollama returned a non-HTTP response.")
            }
            guard (200..<300).contains(httpResponse.statusCode) else {
                let message = (try? JSONDecoder().decode(OllamaErrorResponse.self, from: data).error)
                    ?? String(data: data, encoding: .utf8)
                    ?? "Unknown Ollama error"
                throw LLMKitError.httpError(statusCode: httpResponse.statusCode, message: message)
            }

            let decoded: OllamaGenerateResponse
            do {
                decoded = try JSONDecoder().decode(OllamaGenerateResponse.self, from: data)
            } catch {
                throw LLMKitError.decodingError(error.localizedDescription)
            }
            return OllamaGenerationResult(
                text: decoded.response,
                metrics: OllamaGenerationMetrics(
                    totalDuration: decoded.totalDuration,
                    loadDuration: decoded.loadDuration,
                    promptEvaluationDuration: decoded.promptEvaluationDuration,
                    evaluationDuration: decoded.evaluationDuration
                )
            )
        } catch let error as LLMKitError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch let error as URLError where error.code == .timedOut {
            throw LLMKitError.timeout
        } catch {
            throw LLMKitError.networkError(error.localizedDescription)
        }
    }
}

struct OllamaServerListPayload: Codable, Equatable {
    static let currentVersion = 1

    var version: Int
    var servers: [OllamaServerConfiguration]
    var defaultServerID: UUID?

    init(
        version: Int = currentVersion,
        servers: [OllamaServerConfiguration],
        defaultServerID: UUID?
    ) {
        self.version = version
        self.servers = servers
        self.defaultServerID = defaultServerID
    }
}
