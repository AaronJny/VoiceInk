import Foundation
import Testing
@testable import VoiceInk

@Suite("Qwen3-ASR integration")
struct Qwen3ASRIntegrationTests {
    @Test func artifactIsPinnedAndChecksummed() throws {
        let artifact = TranscribeCppModelCatalog.qwen3ASR1_7B

        #expect(artifact.modelName == "qwen3-asr-1.7b-q5-k-m")
        #expect(artifact.repositoryRevision == "92282af1610a2db19d66f2bef1e260f5deca782d")
        #expect(artifact.expectedFileSize == 1_517_290_464)
        #expect(artifact.expectedSHA256 == "034c557fe92ff8fcd9a9c041cbdaad347be0a86a58d3a348f63cf3f0180879d0")
        #expect(artifact.architectureHint == "qwen3_asr")
        #expect(artifact.maximumChunkSeconds == 35)
        #expect(artifact.enablesInverseTextNormalization == false)
        #expect(TranscribeCppModelCatalog.artifact(for: artifact.modelName)?.fileName == artifact.fileName)
    }

    @Test func modelIsExperimentalAndDoesNotReplaceWhisper() throws {
        let qwen = try #require(
            TranscriptionModelRegistry.models
                .compactMap { $0 as? TranscribeCppModel }
                .first { $0.name == TranscribeCppModelCatalog.qwen3ASR1_7B.modelName }
        )

        #expect(qwen.provider == .transcribeCpp)
        #expect(qwen.supportsStreaming == false)
        #expect(qwen.supportedLanguages["auto"] == "Auto-detect")
        #expect(qwen.supportedLanguages["zh"] == "Chinese")
        #expect(TranscriptionModelRegistry.models.contains { $0.name == "ggml-large-v3" })
    }

    @Test func retainsUpstreamSenseVoiceAlongsideQwenAndCohere() {
        let senseVoice = TranscribeCppModelCatalog.senseVoiceSmall
        #expect(TranscribeCppModelCatalog.artifact(for: senseVoice.modelName) != nil)
        #expect(senseVoice.enablesInverseTextNormalization)
        #expect(TranscriptionModelRegistry.models.contains { $0.name == senseVoice.modelName })
        #expect(TranscribeCppModelCatalog.artifact(for: "cohere-transcribe") != nil)
    }

    @Test func automaticLanguageUsesNativeDetection() throws {
        let qwen = try #require(
            TranscriptionModelRegistry.models
                .compactMap { $0 as? TranscribeCppModel }
                .first { $0.name == TranscribeCppModelCatalog.qwen3ASR1_7B.modelName }
        )

        #expect(OfflineTranscribeCppService.selectedLanguage("auto", for: qwen) == nil)
        #expect(OfflineTranscribeCppService.selectedLanguage("zh", for: qwen) == "zh")
        #expect(OfflineTranscribeCppService.selectedLanguage("zh-CN", for: qwen) == nil)
        #expect(OfflineTranscribeCppService.languageUsesSpaces("zh") == false)
        #expect(OfflineTranscribeCppService.languageUsesSpaces("en") == true)
        #expect(OfflineTranscribeCppService.languageUsesSpaces("th") == false)
    }

    @Test func joinsChunksUsingTheirDetectedLanguages() {
        #expect(
            OfflineTranscribeCppService.joinTexts([
                ("hello", "en"), ("world", "en"),
            ]) == "hello world"
        )
        #expect(
            OfflineTranscribeCppService.joinTexts([
                ("你好", "zh"), ("世界", "zh"),
            ]) == "你好世界"
        )
        #expect(
            OfflineTranscribeCppService.joinTexts([
                ("你好", "zh"), ("VoiceInk", "en"),
            ]) == "你好VoiceInk"
        )
    }
}
