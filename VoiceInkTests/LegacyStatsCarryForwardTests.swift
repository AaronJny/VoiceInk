import Foundation
import SwiftData
import Testing
@testable import VoiceInk

@Suite("Legacy stats carry-forward", .serialized)
@MainActor
struct LegacyStatsCarryForwardTests {
    @Test func absentLegacyKeysDoNothing() {
        let defaults = makeDefaults()
        let service = makeService(defaults: defaults, now: Date(timeIntervalSince1970: 100))

        #expect(!service.prepareIfNeeded())
        #expect(service.pendingSnapshot() == nil)
        #expect(service.completedRecord() == nil)
        #expect(defaults.object(forKey: "CumulativeTotalSessions") == nil)
        #expect(defaults.object(forKey: "CumulativeTotalWords") == nil)
        #expect(defaults.object(forKey: "CumulativeTotalDuration") == nil)
        #expect(defaults.object(forKey: "CumulativeStatsInitialized") == nil)
    }

    @Test func incompleteLegacyTotalsDoNothing() {
        let defaults = makeDefaults()
        defaults.set(true, forKey: "CumulativeStatsInitialized")
        defaults.set(12, forKey: "CumulativeTotalSessions")
        defaults.set(3_456, forKey: "CumulativeTotalWords")
        let service = makeService(defaults: defaults, now: Date(timeIntervalSince1970: 100))

        #expect(!service.prepareIfNeeded())
        #expect(service.pendingSnapshot() == nil)
        #expect(service.completedRecord() == nil)
        #expect(defaults.object(forKey: "CumulativeTotalDuration") == nil)
    }

    @Test func invalidLegacyTotalsDoNothing() {
        let defaults = makeDefaults()
        setLegacyTotals(sessions: 12, words: 3_456, duration: .nan, in: defaults)
        let service = makeService(defaults: defaults, now: Date(timeIntervalSince1970: 100))

        #expect(!service.prepareIfNeeded())
        #expect(service.pendingSnapshot() == nil)
    }

    @Test func prepareIsImmutableAndIdempotent() {
        let defaults = makeDefaults()
        setLegacyTotals(sessions: 12, words: 3_456, duration: 78.5, in: defaults)
        let cutover = Date(timeIntervalSince1970: 1_000)
        let firstService = makeService(defaults: defaults, now: cutover)

        #expect(firstService.prepareIfNeeded())
        let firstSnapshot = firstService.pendingSnapshot()
        #expect(
            firstSnapshot == LegacyStatsCarryForwardService.PendingSnapshot(
                version: 1,
                cutoverDate: cutover,
                legacyTotals: .init(sessions: 12, words: 3_456, duration: 78.5)
            )
        )
        #expect(defaults.integer(forKey: "CumulativeTotalSessions") == 12)
        #expect(defaults.integer(forKey: "CumulativeTotalWords") == 3_456)
        #expect(defaults.double(forKey: "CumulativeTotalDuration") == 78.5)
        #expect(defaults.bool(forKey: "CumulativeStatsInitialized"))

        let restartedService = makeService(
            defaults: defaults,
            now: Date(timeIntervalSince1970: 9_999)
        )
        #expect(!restartedService.prepareIfNeeded())
        #expect(restartedService.pendingSnapshot() == firstSnapshot)
    }

    @Test func crashResumeUsesOriginalCutoverAndAggregatesOnlyRepresentedMetrics() throws {
        let defaults = makeDefaults()
        setLegacyTotals(sessions: 8, words: 800, duration: 80, in: defaults)
        let cutover = Date(timeIntervalSince1970: 2_000)
        #expect(makeService(defaults: defaults, now: cutover).prepareIfNeeded())

        let container = try makeContainer()
        try insertMetric(timestamp: cutover.addingTimeInterval(-1), words: 10, duration: 1, into: container)
        try insertMetric(timestamp: cutover, words: 20, duration: 2, into: container)
        try insertMetric(timestamp: cutover.addingTimeInterval(1), words: 30, duration: 3, into: container)

        let finalizedAt = Date(timeIntervalSince1970: 3_000)
        let restartedService = makeService(defaults: defaults, now: finalizedAt)
        #expect(try restartedService.finalizeIfNeeded(modelContainer: container))
        #expect(restartedService.pendingSnapshot() == nil)
        #expect(
            restartedService.completedRecord()
                == LegacyStatsCarryForwardService.Record(
                    version: 1,
                    cutoverDate: cutover,
                    finalizedAt: finalizedAt,
                    legacyTotals: .init(sessions: 8, words: 800, duration: 80),
                    representedAtCutover: .init(sessions: 2, words: 30, duration: 3)
                )
        )
        #expect(defaults.integer(forKey: "CumulativeTotalSessions") == 8)
        #expect(defaults.integer(forKey: "CumulativeTotalWords") == 800)
        #expect(defaults.double(forKey: "CumulativeTotalDuration") == 80)
        #expect(defaults.bool(forKey: "CumulativeStatsInitialized"))
    }

    @Test func pendingStateSurvivesDefaultsReloadAndCorruptPrimary() throws {
        let suiteName = "LegacyStatsCarryForwardTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        setLegacyTotals(sessions: 6, words: 60, duration: 6, in: defaults)
        let cutover = Date(timeIntervalSince1970: 2_500)
        #expect(makeService(defaults: defaults, now: cutover).prepareIfNeeded())

        let reloadedDefaults = UserDefaults(suiteName: suiteName)!
        let reloadedService = makeService(defaults: reloadedDefaults, now: cutover.addingTimeInterval(1))
        #expect(reloadedService.pendingSnapshot()?.cutoverDate == cutover)

        reloadedDefaults.set(Data("corrupt".utf8), forKey: "LegacyStatsCarryForward.State.v1")
        #expect(reloadedDefaults.synchronize())
        #expect(reloadedService.pendingSnapshot()?.cutoverDate == cutover)

        let container = try makeContainer()
        #expect(try reloadedService.finalizeIfNeeded(modelContainer: container))
        #expect(reloadedService.completedRecord()?.legacyTotals.sessions == 6)
    }

    @Test func repeatedFinalizeIsANoOp() throws {
        let defaults = makeDefaults()
        setLegacyTotals(sessions: 4, words: 40, duration: 4, in: defaults)
        let cutover = Date(timeIntervalSince1970: 4_000)
        let service = makeService(defaults: defaults, now: cutover)
        #expect(service.prepareIfNeeded())

        let container = try makeContainer()
        try insertMetric(timestamp: cutover, words: 5, duration: 0.5, into: container)
        #expect(try service.finalizeIfNeeded(modelContainer: container))
        let completed = service.completedRecord()

        try insertMetric(timestamp: cutover.addingTimeInterval(-1), words: 99, duration: 9, into: container)
        #expect(try !service.finalizeIfNeeded(modelContainer: container))
        #expect(service.completedRecord() == completed)
    }

    @Test func dashboardUsesExactFormulaAndLeavesNonLifetimeFieldsUnchanged() async throws {
        let defaults = makeDefaults()
        setLegacyTotals(sessions: 1, words: 20, duration: 2, in: defaults)
        let cutover = Date(timeIntervalSince1970: 1_768_478_400)
        let service = makeService(defaults: defaults, now: cutover)
        #expect(service.prepareIfNeeded())

        let container = try makeContainer()
        try insertMetric(timestamp: cutover.addingTimeInterval(-60), words: 10, duration: 1, into: container)
        try insertMetric(timestamp: cutover, words: 20, duration: 2, into: container)
        #expect(try service.finalizeIfNeeded(modelContainer: container))
        try insertMetric(timestamp: cutover.addingTimeInterval(60), words: 7, duration: 0.7, into: container)

        let dashboardNow = cutover.addingTimeInterval(86_400)
        let raw = try await DashboardStatsLoader.load(
            from: container,
            userDefaults: makeDefaults(),
            now: dashboardNow
        )
        let adjusted = try await DashboardStatsLoader.load(
            from: container,
            userDefaults: defaults,
            now: dashboardNow
        )
        let record = try #require(service.completedRecord())
        var expected = raw
        expected.totalCount = record.legacyTotals.sessions + raw.totalCount
            - record.representedAtCutover.sessions
        expected.totalWords = record.legacyTotals.words + raw.totalWords
            - record.representedAtCutover.words
        expected.totalDuration = record.legacyTotals.duration + raw.totalDuration
            - record.representedAtCutover.duration

        #expect(adjusted == expected)
        #expect(adjusted.totalCount == 2)
        #expect(adjusted.totalWords == 27)
        #expect(abs(adjusted.totalDuration - 2.7) < 0.000_001)
        #expect(adjusted.storedSessionMetricCount == 3)

        try insertMetric(timestamp: cutover.addingTimeInterval(120), words: 11, duration: 1.5, into: container)
        let afterFutureMetric = try await DashboardStatsLoader.load(
            from: container,
            userDefaults: defaults,
            now: dashboardNow
        )
        #expect(afterFutureMetric.totalCount == adjusted.totalCount + 1)
        #expect(afterFutureMetric.totalWords == adjusted.totalWords + 11)
        #expect(abs(afterFutureMetric.totalDuration - adjusted.totalDuration - 1.5) < 0.000_001)
    }

    private func makeDefaults() -> UserDefaults {
        let name = "LegacyStatsCarryForwardTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func makeService(defaults: UserDefaults, now: Date) -> LegacyStatsCarryForwardService {
        LegacyStatsCarryForwardService(
            userDefaults: defaults,
            now: { now },
            notificationCenter: NotificationCenter(),
            markDashboardStatsStale: {}
        )
    }

    private func setLegacyTotals(
        sessions: Int,
        words: Int,
        duration: TimeInterval,
        in defaults: UserDefaults
    ) {
        defaults.set(sessions, forKey: "CumulativeTotalSessions")
        defaults.set(words, forKey: "CumulativeTotalWords")
        defaults.set(duration, forKey: "CumulativeTotalDuration")
        defaults.set(true, forKey: "CumulativeStatsInitialized")
    }

    private func makeContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: SessionMetric.self, configurations: configuration)
    }

    private func insertMetric(
        timestamp: Date,
        words: Int,
        duration: TimeInterval,
        into container: ModelContainer
    ) throws {
        container.mainContext.insert(
            SessionMetric(
                transcriptionId: UUID(),
                timestamp: timestamp,
                wordCount: words,
                audioDuration: duration,
                transcriptionModelName: "Test Transcriber",
                transcriptionDuration: 0.5,
                speedFactor: 2,
                modeName: "Test Mode",
                aiEnhancementModelName: "Test Enhancer",
                enhancementDuration: 0.25,
                enhancementEstimatedTokenCount: 9
            )
        )
        try container.mainContext.save()
    }
}
