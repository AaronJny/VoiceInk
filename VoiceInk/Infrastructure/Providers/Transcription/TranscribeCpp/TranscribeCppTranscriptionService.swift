import Foundation

/// Routes catalog-backed models through the shared transcribe.cpp runtime.
final class TranscribeCppTranscriptionService: TranscriptionService, @unchecked Sendable {
    private let cohereService = OfflineTranscribeCppService()
    private let qwenService = OfflineTranscribeCppService()
    private let senseVoiceService = OfflineTranscribeCppService()

    func loadModel(for model: TranscribeCppModel) async throws {
        guard let service = service(for: model.name) else {
            throw unsupportedModelError(model.name)
        }
        try await service.loadModel(for: model)
    }

    func transcribe(
        audioURL: URL,
        model: any TranscriptionModel,
        context: TranscriptionRequestContext
    ) async throws -> String {
        guard let transcribeCppModel = model as? TranscribeCppModel else {
            throw NSError(
                domain: "TranscribeCppTranscriptionService",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Unsupported transcription model"]
            )
        }

        guard let service = service(for: transcribeCppModel.name) else {
            throw unsupportedModelError(transcribeCppModel.name)
        }
        return try await service.transcribe(
            audioURL: audioURL,
            model: transcribeCppModel,
            context: context
        )
    }

    func cleanup() {
        cohereService.cleanup()
        qwenService.cleanup()
        senseVoiceService.cleanup()
    }

    private func service(for modelName: String) -> OfflineTranscribeCppService? {
        switch modelName {
        case TranscribeCppModelCatalog.cohereTranscribe.modelName:
            return cohereService
        case TranscribeCppModelCatalog.qwen3ASR1_7B.modelName:
            return qwenService
        case TranscribeCppModelCatalog.senseVoiceSmall.modelName:
            return senseVoiceService
        default:
            return nil
        }
    }

    private func unsupportedModelError(_ modelName: String) -> NSError {
        NSError(
            domain: "TranscribeCppTranscriptionService",
            code: -2,
            userInfo: [NSLocalizedDescriptionKey: "No transcribe.cpp service is registered for \(modelName)"]
        )
    }
}
