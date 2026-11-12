import Foundation

struct TranscribeCppModelArtifact: Sendable {
    let modelName: String
    let fileName: String
    let repository: String
    let repositoryRevision: String
    let expectedFileSize: Int64
    let expectedSHA256: String
    let architectureHint: String?
    let maximumChunkSeconds: Int
    let boundarySearchSeconds: Int
    let boundaryEnergyWindowSamples: Int

    var downloadURL: URL {
        URL(
            string: "https://huggingface.co/\(repository)/resolve/\(repositoryRevision)/\(fileName)"
        )!
    }

    var modelDirectory: URL {
        Self.applicationSupportDirectory
            .appendingPathComponent("TranscribeCpp", isDirectory: true)
            .appendingPathComponent(modelName, isDirectory: true)
    }

    var modelFileURL: URL {
        modelDirectory.appendingPathComponent(fileName, isDirectory: false)
    }

    var checksumFileURL: URL {
        modelDirectory.appendingPathComponent(".\(fileName).sha256", isDirectory: false)
    }

    var installedModelFileURL: URL? {
        modelFileIsValid(in: modelDirectory) ? modelFileURL : nil
    }

    func modelFileIsValid(in directory: URL) -> Bool {
        let fileURL = directory.appendingPathComponent(fileName, isDirectory: false)
        let checksumURL = directory.appendingPathComponent(".\(fileName).sha256", isDirectory: false)

        guard
            let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
            values.isRegularFile == true,
            let size = values.fileSize,
            Int64(size) == expectedFileSize
        else {
            return false
        }

        let installedChecksum = try? String(contentsOf: checksumURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return installedChecksum == expectedSHA256
    }

    func removeInstalledFiles() {
        try? FileManager.default.removeItem(at: modelDirectory)
    }

    private static var applicationSupportDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.prakashjoshipax.VoiceInk", isDirectory: true)
    }
}

enum TranscribeCppModelCatalog {
    static let cohereTranscribe = TranscribeCppModelArtifact(
        modelName: "cohere-transcribe",
        fileName: "cohere-transcribe-03-2026-Q4_K_M.gguf",
        repository: "handy-computer/cohere-transcribe-03-2026-gguf",
        repositoryRevision: "dfa4adebb64f3076b7b6b90b721275cc069cb421",
        expectedFileSize: 1_558_162_944,
        expectedSHA256: "0ea56826d8bd5d74b7143a4a04e022dc1bb75452cfae49d98b6acb0c1d16a1fb",
        architectureHint: "cohere",
        maximumChunkSeconds: 35,
        boundarySearchSeconds: 5,
        boundaryEnergyWindowSamples: 1_600
    )

    static let qwen3ASR1_7B = TranscribeCppModelArtifact(
        modelName: "qwen3-asr-1.7b-q5-k-m",
        fileName: "Qwen3-ASR-1.7B-Q5_K_M.gguf",
        repository: "handy-computer/Qwen3-ASR-1.7B-gguf",
        repositoryRevision: "92282af1610a2db19d66f2bef1e260f5deca782d",
        expectedFileSize: 1_517_290_464,
        expectedSHA256: "034c557fe92ff8fcd9a9c041cbdaad347be0a86a58d3a348f63cf3f0180879d0",
        architectureHint: "qwen3_asr",
        maximumChunkSeconds: 35,
        boundarySearchSeconds: 5,
        boundaryEnergyWindowSamples: 1_600
    )

    private static let artifactsByModelName = [
        cohereTranscribe.modelName: cohereTranscribe,
        qwen3ASR1_7B.modelName: qwen3ASR1_7B,
    ]

    static func artifact(for modelName: String) -> TranscribeCppModelArtifact? {
        artifactsByModelName[modelName]
    }
}
