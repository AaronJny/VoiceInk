import Foundation
import Testing
@testable import VoiceInk

@Suite("ASR benchmark")
@MainActor
struct ASRBenchmarkTests {
    private struct Result: Codable {
        let file: String
        let engine: String
        let loadSeconds: Double?
        let loadMemoryDeltaMB: Double?
        let transcriptionSeconds: Double
        let text: String
    }

    @Test func compareRealRecordingsWhenConfigured() async throws {
        let environment = ProcessInfo.processInfo.environment
        let configuredFiles = environment["VOICEINK_ASR_BENCHMARK_FILES"]
            .map { $0.split(separator: "\n").map(String.init) }
            ?? UserDefaults.standard.stringArray(forKey: "ASRBenchmarkFiles")
            ?? []
        let audioURLs = configuredFiles
            .map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !audioURLs.isEmpty else { return }

        let models = TranscriptionModelRegistry.models
        let whisperModel = try #require(models.first { $0.name == "ggml-large-v3" })
        let qwenModel = try #require(
            models.compactMap { $0 as? TranscribeCppModel }
                .first { $0.name == TranscribeCppModelCatalog.qwen3ASR1_7B.modelName }
        )
        guard TranscribeCppModelCatalog.qwen3ASR1_7B.installedModelFileURL != nil else {
            Issue.record("Qwen3-ASR model is not installed and verified")
            return
        }

        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.prakashjoshipax.VoiceInk")
        let whisperDirectory = appSupport.appendingPathComponent("WhisperModels")
        let whisperManager = WhisperModelManager(modelsDirectory: whisperDirectory)
        whisperManager.loadAvailableModels()
        let whisperFile = try #require(
            whisperManager.availableModels.first { $0.name == whisperModel.name },
            "Whisper Large v3 is not installed"
        )

        let whisperMemoryBeforeLoad = residentMemoryMB()
        let whisperLoadStart = ContinuousClock.now
        try await whisperManager.loadModel(whisperFile)
        let whisperLoadSeconds = seconds(since: whisperLoadStart)
        let whisperMemoryDelta = memoryDelta(from: whisperMemoryBeforeLoad)
        let whisperService = WhisperTranscriptionService(
            modelsDirectory: whisperDirectory,
            modelProvider: whisperManager
        )
        let currentPrompt = UserDefaults.standard.string(forKey: "TranscriptionPrompt") ?? ""
        let candidatePrompt = "以下是日常口述内容，可能包含中文、英文、数字、产品名和技术术语。"
        var results: [Result] = []

        for audioURL in audioURLs {
            results.append(
                try await benchmark(
                    service: whisperService,
                    audioURL: audioURL,
                    model: whisperModel,
                    engine: "whisper-current-prompt",
                    loadSeconds: whisperLoadSeconds,
                    loadMemoryDeltaMB: whisperMemoryDelta,
                    context: TranscriptionRequestContext(language: "zh", prompt: currentPrompt)
                )
            )
            results.append(
                try await benchmark(
                    service: whisperService,
                    audioURL: audioURL,
                    model: whisperModel,
                    engine: "whisper-general-prompt",
                    loadSeconds: nil,
                    loadMemoryDeltaMB: nil,
                    context: TranscriptionRequestContext(language: "zh", prompt: candidatePrompt)
                )
            )
        }
        await whisperManager.cleanupResources()

        let qwenService = TranscribeCppTranscriptionService()
        defer { qwenService.cleanup() }
        for audioURL in audioURLs {
            let memoryBeforeLoad = residentMemoryMB()
            let loadStart = ContinuousClock.now
            try await qwenService.loadModel(for: qwenModel)
            let loadSeconds = seconds(since: loadStart)
            let loadMemoryDelta = memoryDelta(from: memoryBeforeLoad)
            results.append(
                try await benchmark(
                    service: qwenService,
                    audioURL: audioURL,
                    model: qwenModel,
                    engine: "qwen-auto",
                    loadSeconds: loadSeconds,
                    loadMemoryDeltaMB: loadMemoryDelta,
                    context: TranscriptionRequestContext(language: "auto", prompt: nil)
                )
            )

            let chineseMemoryBeforeLoad = residentMemoryMB()
            let chineseLoadStart = ContinuousClock.now
            try await qwenService.loadModel(for: qwenModel)
            let chineseLoadSeconds = seconds(since: chineseLoadStart)
            let chineseLoadMemoryDelta = memoryDelta(from: chineseMemoryBeforeLoad)
            results.append(
                try await benchmark(
                    service: qwenService,
                    audioURL: audioURL,
                    model: qwenModel,
                    engine: "qwen-zh",
                    loadSeconds: chineseLoadSeconds,
                    loadMemoryDeltaMB: chineseLoadMemoryDelta,
                    context: TranscriptionRequestContext(language: "zh", prompt: nil)
                )
            )
        }

        let data = try JSONEncoder.pretty.encode(results)
        let outputPath = environment["VOICEINK_ASR_BENCHMARK_OUTPUT"]
            ?? UserDefaults.standard.string(forKey: "ASRBenchmarkOutput")
        if let outputPath {
            try data.write(to: URL(fileURLWithPath: outputPath), options: .atomic)
        }
        print(String(decoding: data, as: UTF8.self))
    }

    private func benchmark(
        service: TranscriptionService,
        audioURL: URL,
        model: any TranscriptionModel,
        engine: String,
        loadSeconds: Double?,
        loadMemoryDeltaMB: Double?,
        context: TranscriptionRequestContext
    ) async throws -> Result {
        let start = ContinuousClock.now
        let text = try await service.transcribe(audioURL: audioURL, model: model, context: context)
        return Result(
            file: audioURL.lastPathComponent,
            engine: engine,
            loadSeconds: loadSeconds,
            loadMemoryDeltaMB: loadMemoryDeltaMB,
            transcriptionSeconds: seconds(since: start),
            text: text
        )
    }

    private func seconds(since start: ContinuousClock.Instant) -> Double {
        let duration = start.duration(to: .now)
        return Double(duration.components.seconds)
            + Double(duration.components.attoseconds) / 1_000_000_000_000_000_000
    }

    private func memoryDelta(from baselineMB: Double?) -> Double? {
        guard let baselineMB, let currentMB = residentMemoryMB() else { return nil }
        return currentMB - baselineMB
    }

    private func residentMemoryMB() -> Double? {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-o", "rss=", "-p", String(ProcessInfo.processInfo.processIdentifier)]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }
        let value = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let kilobytes = Double(value) else { return nil }
        return kilobytes / 1_024
    }
}

private extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
