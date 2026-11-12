import Foundation

enum SessionMetricWriteCoordinator {
    private static let lock = NSLock()

    static func withLock<Result>(_ body: () throws -> Result) rethrows -> Result {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }
}
