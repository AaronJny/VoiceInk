import Foundation

/// Routes transcribe.cpp-backed models to their model-specific service.
final class TranscribeCppTranscriptionService: TranscriptionService, @unchecked Sendable {
    private let cohereService = CohereTranscriptionService()
    private let qwenService = CohereTranscriptionService()

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
    }

    private func service(for modelName: String) -> CohereTranscriptionService? {
        switch modelName {
        case TranscribeCppModelCatalog.cohereTranscribe.modelName:
            return cohereService
        case TranscribeCppModelCatalog.qwen3ASR1_7B.modelName:
            return qwenService
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
