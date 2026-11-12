import Combine
import Foundation
import SwiftData
import os

@MainActor
final class ModelPrewarmService: ObservableObject {
    private let transcriptionModelManager: TranscriptionModelManager
    private let whisperModelManager: WhisperModelManager
    private let aiService: AIService
    private let enhancementService: AIEnhancementService
    private let modelContext: ModelContext
    private let userDefaults: UserDefaults
    private let fluidAudioService: FluidAudioTranscriptionService
    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "ModelPrewarm")
    private lazy var serviceRegistry = TranscriptionServiceRegistry(
        modelProvider: whisperModelManager,
        modelsDirectory: whisperModelManager.modelsDirectory,
        modelContext: modelContext
    )
    private let prewarmAudioURL = Bundle.main.url(forResource: "sound7", withExtension: "wav")
    private var lifecycleCancellable: AnyCancellable?

    init(
        transcriptionModelManager: TranscriptionModelManager,
        whisperModelManager: WhisperModelManager,
        aiService: AIService,
        enhancementService: AIEnhancementService,
        modelContext: ModelContext,
        fluidAudioService: FluidAudioTranscriptionService,
        userDefaults: UserDefaults = .standard
    ) {
        self.transcriptionModelManager = transcriptionModelManager
        self.whisperModelManager = whisperModelManager
        self.aiService = aiService
        self.enhancementService = enhancementService
        self.modelContext = modelContext
        self.userDefaults = userDefaults
        self.fluidAudioService = fluidAudioService
        lifecycleCancellable = LifecycleObserver.shared.publisher(for: .systemDidWake).sink {
            [weak self] _ in
            Task { @MainActor in
                self?.schedulePrewarm()
            }
        }
        schedulePrewarmOnAppLaunch()
    }

    // MARK: - Trigger Handlers

    /// Trigger on app launch (cold start)
    private func schedulePrewarmOnAppLaunch() {
        logger.notice("App launched, scheduling prewarm")
        Task {
            try? await Task.sleep(for: .seconds(3))
            await performPrewarm()
        }
    }

    /// Trigger on wake from sleep
    private func schedulePrewarm() {
        logger.notice("Mac woke from sleep, scheduling prewarm")
        Task {
            try? await Task.sleep(for: .seconds(3))
            await performPrewarm()
        }
    }

    // MARK: - Core Prewarming Logic

    private func performPrewarm() async {
        guard isPrewarmEnabled else {
            logger.notice("Prewarm disabled by user")
            return
        }

        await prewarmTranscriptionModel()
        await prewarmOllamaEnhancementModel()
    }

    private func prewarmTranscriptionModel() async {
        guard shouldPrewarmTranscriptionModel() else { return }

        guard
            let transcriptionConfiguration = ModeRuntimeResolver.transcriptionConfiguration(
                transcriptionModelManager: transcriptionModelManager
            )
        else {
            logger.notice("No model selected, skipping prewarm")
            return
        }
        let currentModel = transcriptionConfiguration.model

        logger.notice("Prewarming \(currentModel.displayName, privacy: .public)")
        let startTime = Date()

        do {
            if currentModel.provider == .fluidAudio,
                FluidAudioModelManager.isParakeetUnifiedModel(named: currentModel.name)
            {
                try await fluidAudioService.prewarmUnifiedModel(
                    isRealtime: transcriptionConfiguration.isRealtimeEnabled
                )
            } else {
                guard let audioURL = prewarmAudioURL else {
                    logger.error("❌ Prewarm audio file (sound7.wav) not found")
                    return
                }
                let _ = try await serviceRegistry.transcribe(
                    audioURL: audioURL,
                    model: currentModel,
                    context: transcriptionConfiguration.requestContext
                )
            }
            let duration = Date().timeIntervalSince(startTime)

            logger.notice("Prewarm completed in \(String(format: "%.2f", duration), privacy: .public)s")

        } catch {
            logger.error("❌ Prewarm failed: \(error, privacy: .public)")
        }
    }

    private func prewarmOllamaEnhancementModel() async {
        let configuration = ModeRuntimeResolver.currentEnhancementConfiguration(
            enhancementService: enhancementService,
            aiService: aiService
        )
        guard configuration.isEnabled,
            configuration.provider == .ollama,
            let model = configuration.modelName,
            let baseURL = configuration.ollamaBaseURL,
            OllamaService.isLoopback(baseURL: baseURL)
        else {
            return
        }

        logger.notice("Prewarming Ollama model \(model, privacy: .public)")
        let startTime = Date()
        do {
            try await aiService.prewarmOllama(model: model, baseURL: baseURL)
            let duration = Date().timeIntervalSince(startTime)
            logger.notice(
                "Ollama prewarm completed in \(duration, format: .fixed(precision: 2), privacy: .public)s"
            )
        } catch {
            logger.error("❌ Ollama prewarm failed: \(error, privacy: .public)")
        }
    }

    // MARK: - Validation

    var isPrewarmEnabled: Bool {
        userDefaults.object(forKey: OllamaService.prewarmEnabledKey) as? Bool ?? true
    }

    private func shouldPrewarmTranscriptionModel() -> Bool {
        // Prewarm only local runtimes that benefit from retained preparation.
        guard
            let model = ModeRuntimeResolver.transcriptionConfiguration(
                transcriptionModelManager: transcriptionModelManager
            )?.model
        else {
            return false
        }

        switch model.provider {
        case .whisper, .fluidAudio:
            return true
        default:
            logger.notice("Skipping prewarm - cloud models don't need it")
            return false
        }
    }

}
