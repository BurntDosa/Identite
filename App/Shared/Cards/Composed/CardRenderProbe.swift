#if DEBUG
import Foundation

/// Counts only; never retains a composition, payload or image.
final class CardRenderProbe: @unchecked Sendable {
    static let shared = CardRenderProbe()
    private let lock = NSLock()
    private var counts: [String: Int] = [:]
    private var enabled = false

    func start() { lock.withLock { counts = [:]; enabled = true } }
    func take() -> [String: Int] { lock.withLock { defer { counts = [:] }; return counts } }
    func stop() { lock.withLock { enabled = false; counts = [:] } }
    func hit(_ name: String) { lock.withLock { if enabled { counts[name, default: 0] += 1 } } }
}
#endif
