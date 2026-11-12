import AppKit
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
    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "ModelPrewarm")
    private lazy var serviceRegistry = TranscriptionServiceRegistry(
        modelProvider: whisperModelManager,
        modelsDirectory: whisperModelManager.modelsDirectory,
        modelContext: modelContext
    )
    private let prewarmAudioURL = Bundle.main.url(forResource: "sound7", withExtension: "wav")

    init(
        transcriptionModelManager: TranscriptionModelManager,
        whisperModelManager: WhisperModelManager,
        aiService: AIService,
        enhancementService: AIEnhancementService,
        modelContext: ModelContext,
        userDefaults: UserDefaults = .standard
    ) {
        self.transcriptionModelManager = transcriptionModelManager
        self.whisperModelManager = whisperModelManager
        self.aiService = aiService
        self.enhancementService = enhancementService
        self.modelContext = modelContext
        self.userDefaults = userDefaults
        setupNotifications()
        schedulePrewarmOnAppLaunch()
    }

    // MARK: - Notification Setup

    private func setupNotifications() {
        let center = NSWorkspace.shared.notificationCenter

        // Trigger on wake from sleep
        center.addObserver(
            self,
            selector: #selector(schedulePrewarm),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )

        logger.notice("ModelPrewarmService initialized - listening for wake and app launch")
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

    /// Trigger on wake from sleep or screen unlock
    @objc private func schedulePrewarm() {
        logger.notice("Mac activity detected (wake/unlock), scheduling prewarm")
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

        guard let audioURL = prewarmAudioURL else {
            logger.error("❌ Prewarm audio file (sound7.wav) not found")
            return
        }

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
            let _ = try await serviceRegistry.transcribe(
                audioURL: audioURL,
                model: currentModel,
                context: transcriptionConfiguration.requestContext
            )
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

    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        logger.notice("ModelPrewarmService deinitialized")
    }
}
