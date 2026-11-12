import Foundation
import SwiftData
import Testing
@testable import VoiceInk

@Suite("Session metric write coordination", .serialized)
@MainActor
struct SessionMetricWriteCoordinatorTests {
    @Test func concurrentWritersInsertOneMetric() async throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Transcription.self,
            SessionMetric.self,
            configurations: configuration
        )
        let transcription = Transcription(
            text: "coordinated metric",
            duration: 2,
            transcriptionStatus: .completed
        )
        container.mainContext.insert(transcription)
        try container.mainContext.save()
        let transcriptionId = transcription.id

        let results = try await withThrowingTaskGroup(of: Bool.self) { group in
            for _ in 0..<2 {
                group.addTask {
                    let context = ModelContext(container)
                    let descriptor = FetchDescriptor<Transcription>(
                        predicate: #Predicate<Transcription> { item in
                            item.id == transcriptionId
                        }
                    )
                    let fetched = try #require(context.fetch(descriptor).first)
                    return try SessionMetricWriteCoordinator.withLock {
                        let inserted = try SessionMetricRecorder.recordRecorderSession(
                            transcription: fetched,
                            model: nil,
                            in: context
                        )
                        try context.save()
                        return inserted
                    }
                }
            }

            var inserted: [Bool] = []
            for try await result in group {
                inserted.append(result)
            }
            return inserted
        }

        #expect(results.filter { $0 }.count == 1)
        let metricCount = try container.mainContext.fetchCount(FetchDescriptor<SessionMetric>())
        #expect(metricCount == 1)
    }
}
