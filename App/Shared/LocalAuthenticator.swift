import IDCore
import LocalAuthentication

struct LocalAuthenticator: Authenticator {
    static var unlockLabel: String {
        #if os(macOS)
        return "Open"
        #else
        return "Unlock with Face ID"
        #endif
    }

    @MainActor func authenticate(reason: String) async -> Bool {
        let context = LAContext()
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) else { return false }
        let cancel: @MainActor @Sendable () -> Void = { context.invalidate() }
        return await withTaskCancellationHandler {
            guard !Task.isCancelled else { return false }
            do { return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) }
            catch { return false }
        } onCancel: { Task { await cancel() } }
    }
}
