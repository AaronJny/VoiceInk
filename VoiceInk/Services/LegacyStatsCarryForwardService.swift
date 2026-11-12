import Foundation
import OSLog
import SwiftData

struct LegacyStatsCarryForwardService {
    struct Totals: Codable, Equatable, Sendable {
        let sessions: Int
        let words: Int
        let duration: TimeInterval
    }

    struct PendingSnapshot: Codable, Equatable, Sendable {
        let version: Int
        let cutoverDate: Date
        let legacyTotals: Totals
    }

    struct Record: Codable, Equatable, Sendable {
        let version: Int
        let cutoverDate: Date
        let finalizedAt: Date
        let legacyTotals: Totals
        let representedAtCutover: Totals
    }

    enum State: Codable, Equatable, Sendable {
        case pending(PendingSnapshot)
        case completed(Record)
    }

    enum MigrationError: Error {
        case invalidRepresentedTotals
    }

    static let currentVersion = 1
    private static let logger = Logger(
        subsystem: "com.prakashjoshipax.voiceink",
        category: "LegacyStatsCarryForwardService"
    )

    private enum Key {
        static let legacySessions = "CumulativeTotalSessions"
        static let legacyWords = "CumulativeTotalWords"
        static let legacyDuration = "CumulativeTotalDuration"
        static let legacyInitialized = "CumulativeStatsInitialized"
        static let state = "LegacyStatsCarryForward.State.v1"
        static let stateBackup = "LegacyStatsCarryForward.StateBackup.v1"
    }

    private let userDefaults: UserDefaults
    private let now: () -> Date
    private let notificationCenter: NotificationCenter
    private let markDashboardStatsStale: () -> Void

    init(
        userDefaults: UserDefaults = .standard,
        now: @escaping () -> Date = Date.init,
        notificationCenter: NotificationCenter = .default,
        markDashboardStatsStale: @escaping () -> Void = { DashboardStatsCache.shared.markStale() }
    ) {
        self.userDefaults = userDefaults
        self.now = now
        self.notificationCenter = notificationCenter
        self.markDashboardStatsStale = markDashboardStatsStale
    }

    @discardableResult
    func prepareIfNeeded() -> Bool {
        guard Self.state(in: userDefaults) == nil else { return false }
        guard !Self.hasUndecodableState(in: userDefaults) else {
            Self.logger.error("Legacy stats state is corrupt; refusing to replace its cutover date.")
            return false
        }
        guard userDefaults.bool(forKey: Key.legacyInitialized) else { return false }
        guard let sessionsValue = userDefaults.object(forKey: Key.legacySessions) as? NSNumber else { return false }
        guard let wordsValue = userDefaults.object(forKey: Key.legacyWords) as? NSNumber else { return false }
        guard let durationValue = userDefaults.object(forKey: Key.legacyDuration) as? NSNumber else { return false }

        let legacyTotals = Totals(
            sessions: sessionsValue.intValue,
            words: wordsValue.intValue,
            duration: durationValue.doubleValue
        )
        guard Self.isValid(legacyTotals) else {
            Self.logger.error("Legacy stats contain invalid totals; carry-forward was not prepared.")
            return false
        }

        let snapshot = PendingSnapshot(
            version: Self.currentVersion,
            cutoverDate: now(),
            legacyTotals: legacyTotals
        )

        return persist(.pending(snapshot))
    }

    @discardableResult
    func finalizeIfNeeded(modelContainer: ModelContainer) throws -> Bool {
        guard case .pending(let pending) = Self.state(in: userDefaults) else { return false }

        let cutoverDate = pending.cutoverDate
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<SessionMetric>(
            predicate: #Predicate<SessionMetric> { metric in
                metric.timestamp <= cutoverDate
            }
        )
        let metrics = try context.fetch(descriptor)
        var words = 0
        var duration: TimeInterval = 0
        for metric in metrics {
            let (nextWords, overflowed) = words.addingReportingOverflow(metric.wordCount)
            guard !overflowed else { throw MigrationError.invalidRepresentedTotals }
            words = nextWords
            duration += metric.audioDuration
        }
        let represented = Totals(sessions: metrics.count, words: words, duration: duration)
        guard Self.isValid(represented) else { throw MigrationError.invalidRepresentedTotals }
        let record = Record(
            version: Self.currentVersion,
            cutoverDate: pending.cutoverDate,
            finalizedAt: now(),
            legacyTotals: pending.legacyTotals,
            representedAtCutover: represented
        )

        guard persist(.completed(record)) else { return false }
        markDashboardStatsStale()
        notificationCenter.post(name: .sessionMetricsDidChange, object: nil)
        return true
    }

    func pendingSnapshot() -> PendingSnapshot? {
        guard case .pending(let snapshot) = Self.state(in: userDefaults) else { return nil }
        return snapshot
    }

    func completedRecord() -> Record? {
        Self.completedRecord(in: userDefaults)
    }

    static func completedRecord(in userDefaults: UserDefaults) -> Record? {
        guard case .completed(let record) = state(in: userDefaults) else { return nil }
        return record
    }

    static func apply(_ record: Record, to summary: DashboardStatsSummary) -> DashboardStatsSummary {
        guard let totalCount = adjusted(
            legacy: record.legacyTotals.sessions,
            current: summary.totalCount,
            represented: record.representedAtCutover.sessions
        ), let totalWords = adjusted(
            legacy: record.legacyTotals.words,
            current: summary.totalWords,
            represented: record.representedAtCutover.words
        ) else {
            logger.error("Legacy stats adjustment overflowed; leaving dashboard totals unchanged.")
            return summary
        }

        let totalDuration = record.legacyTotals.duration + summary.totalDuration
            - record.representedAtCutover.duration
        guard totalDuration.isFinite else {
            logger.error("Legacy duration adjustment is not finite; leaving dashboard totals unchanged.")
            return summary
        }

        var adjustedSummary = summary
        adjustedSummary.totalCount = totalCount
        adjustedSummary.totalWords = totalWords
        adjustedSummary.totalDuration = totalDuration
        return adjustedSummary
    }

    private func persist(_ state: State) -> Bool {
        guard let data = try? JSONEncoder().encode(state) else { return false }
        userDefaults.set(data, forKey: Key.stateBackup)
        guard userDefaults.synchronize() else { return false }
        userDefaults.set(data, forKey: Key.state)
        guard userDefaults.synchronize() else { return false }
        return userDefaults.data(forKey: Key.state) == data
            && userDefaults.data(forKey: Key.stateBackup) == data
    }

    private static func state(in userDefaults: UserDefaults) -> State? {
        for key in [Key.state, Key.stateBackup] {
            guard let data = userDefaults.data(forKey: key),
                let state = try? JSONDecoder().decode(State.self, from: data)
            else { continue }

            switch state {
            case .pending(let snapshot)
                where snapshot.version == currentVersion && isValid(snapshot.legacyTotals):
                return state
            case .completed(let record)
                where record.version == currentVersion && isValid(record.legacyTotals)
                    && isValid(record.representedAtCutover):
                return state
            default:
                continue
            }
        }
        return nil
    }

    private static func hasUndecodableState(in userDefaults: UserDefaults) -> Bool {
        (userDefaults.object(forKey: Key.state) != nil || userDefaults.object(forKey: Key.stateBackup) != nil)
            && state(in: userDefaults) == nil
    }

    private static func isValid(_ totals: Totals) -> Bool {
        totals.sessions >= 0 && totals.words >= 0 && totals.duration.isFinite && totals.duration >= 0
    }

    private static func adjusted(legacy: Int, current: Int, represented: Int) -> Int? {
        let (withCurrent, additionOverflowed) = legacy.addingReportingOverflow(current)
        let (result, subtractionOverflowed) = withCurrent.subtractingReportingOverflow(represented)
        return additionOverflowed || subtractionOverflowed ? nil : result
    }
}
