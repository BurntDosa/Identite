import Foundation
import Observation

public protocol Authenticator: Sendable {
    func authenticate(reason: String) async -> Bool
}

@MainActor @Observable public final class SessionLock {
    public static let timeout: TimeInterval = 300
    public private(set) var isUnlocked = false
    private let authenticator: any Authenticator
    private let now: @MainActor () -> ContinuousClock.Instant
    private var awaySince: ContinuousClock.Instant?
    private var unlockGeneration = 0
    private var authenticationTask: Task<Bool, Never>?
    public var authorizationGeneration: Int { unlockGeneration }

    public init(authenticator: any Authenticator, now: @escaping @MainActor () -> ContinuousClock.Instant = { .now }) {
        self.authenticator = authenticator
        self.now = now
    }

    public func unlock() async -> Bool {
        authenticationTask?.cancel()
        unlockGeneration += 1
        let generation = unlockGeneration
        let attempt = Task { await authenticator.authenticate(reason: "Unlock your IDs") }
        authenticationTask = attempt
        let success = await withTaskCancellationHandler { await attempt.value } onCancel: { attempt.cancel() }
        evaluate()
        // A manual/system lock or newer attempt invalidates an in-flight authentication.
        guard generation == unlockGeneration else { return false }
        authenticationTask = nil
        guard !Task.isCancelled else { isUnlocked = false; awaySince = nil; return false }
        isUnlocked = success
        if !success { awaySince = nil }
        return success
    }

    public func lockNow() {
        unlockGeneration += 1
        authenticationTask?.cancel(); authenticationTask = nil
        isUnlocked = false
        awaySince = nil
    }

    public func markAway() {
        if (isUnlocked || authenticationTask != nil) && awaySince == nil { awaySince = now() }
    }

    public func markPresent() {
        evaluate()
        awaySince = nil
    }

    public func evaluate() {
        if let awaySince, awaySince.duration(to: now()) >= .seconds(Self.timeout) { lockNow() }
    }
}
