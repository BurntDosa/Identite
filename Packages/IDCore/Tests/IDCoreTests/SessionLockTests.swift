import Foundation
import Testing
@testable import IDCore
struct FakeAuth: Authenticator { let ok: Bool; func authenticate(reason: String) async -> Bool { ok } }
@MainActor final class Clock { var t = ContinuousClock.now }

struct SessionLockTests {
@MainActor @Test func unlockSuccessAndFailure() async {
  #expect(await SessionLock(authenticator: FakeAuth(ok: true)).unlock())
  let s = SessionLock(authenticator: FakeAuth(ok: false)); #expect(!(await s.unlock())); #expect(!s.isUnlocked)
}
@MainActor @Test func returnsWithin299sStaysUnlocked() async {
  let c = Clock(); let s = SessionLock(authenticator: FakeAuth(ok: true), now: { c.t }); _ = await s.unlock()
  s.markAway(); c.t += .seconds(299); s.markPresent(); #expect(s.isUnlocked)
}
@MainActor @Test func awayExactly300sLocks() async {
  let c = Clock(); let s = SessionLock(authenticator: FakeAuth(ok: true), now: { c.t }); _ = await s.unlock()
  s.markAway(); c.t += .seconds(300); s.markPresent(); #expect(!s.isUnlocked)
}
@MainActor @Test func repeatedAwayDoesNotResetTimer() async {
  let c = Clock(); let s = SessionLock(authenticator: FakeAuth(ok: true), now: { c.t }); _ = await s.unlock()
  s.markAway(); c.t += .seconds(200); s.markAway(); c.t += .seconds(100); s.evaluate(); #expect(!s.isUnlocked)
}
@MainActor @Test func presenceResetsAwayClock() async {
  let c = Clock(); let s = SessionLock(authenticator: FakeAuth(ok: true), now: { c.t }); _ = await s.unlock()
  s.markAway(); c.t += .seconds(200); s.markPresent(); s.markAway(); c.t += .seconds(200); s.evaluate(); #expect(s.isUnlocked)
}
@MainActor @Test func lockNowLocks() async { let s = SessionLock(authenticator: FakeAuth(ok: true)); _ = await s.unlock(); s.lockNow(); #expect(!s.isUnlocked) }

}

actor PendingAuth: Authenticator {
    private var answers: [CheckedContinuation<Bool, Never>] = []
    func authenticate(reason: String) async -> Bool {
        await withCheckedContinuation { answers.append($0) }
    }
    func isPending() -> Bool { !answers.isEmpty }
    func count() -> Int { answers.count }
    func finish(_ success: Bool = true) { if !answers.isEmpty { answers.removeFirst().resume(returning: success) } }
}

@MainActor @Test func lockCancelsPendingUnlock() async {
    let auth = PendingAuth()
    let session = SessionLock(authenticator: auth)
    let attempt = Task { await session.unlock() }
    while !(await auth.isPending()) { await Task.yield() }
    session.lockNow()
    await auth.finish()
    #expect(!(await attempt.value))
    #expect(!session.isUnlocked)
}

@MainActor @Test func absenceInvalidatesPendingUnlockBeforeAndAfterReturn() async {
    for returnsFirst in [true, false] {
        let clock = Clock(), auth = PendingAuth()
        let session = SessionLock(authenticator: auth, now: { clock.t })
        let attempt = Task { await session.unlock() }
        while !(await auth.isPending()) { await Task.yield() }
        clock.t += .seconds(1); session.markAway(); clock.t += .seconds(301)
        if returnsFirst { session.markPresent() }
        await auth.finish()
        #expect(!(await attempt.value))
        session.markPresent()
        #expect(!session.isUnlocked)
    }
}

@MainActor @Test func backwardWallClockMustNotEraseElapsedAbsence() async {
    let clock = Clock()
    let session = SessionLock(authenticator: FakeAuth(ok: true), now: { clock.t })
    _ = await session.unlock(); session.markAway()
    var wallTime = Date(timeIntervalSince1970: 0)
    wallTime += 600; clock.t += .seconds(600)
    wallTime -= 360
    #expect(wallTime.timeIntervalSince1970 == 240)
    session.markPresent()
    #expect(!session.isUnlocked)
    clock.t += .seconds(360); session.evaluate()
    #expect(!session.isUnlocked)
}

@MainActor @Test func earlyAuthenticationCompletionKeepsOriginalAbsence() async {
    let clock = Clock(), auth = PendingAuth()
    let session = SessionLock(authenticator: auth, now: { clock.t })
    let attempt = Task { await session.unlock() }
    while !(await auth.isPending()) { await Task.yield() }
    session.markAway(); clock.t += .seconds(200)
    await auth.finish()
    #expect(await attempt.value)
    session.markAway(); clock.t += .seconds(100); session.markPresent()
    #expect(!session.isUnlocked)
}

@MainActor @Test func cancelledAndSupersededAuthenticationFailClosed() async {
    let auth = PendingAuth()
    let isolated = SessionLock(authenticator: auth)
    let cancelled = Task { await isolated.unlock() }
    while !(await auth.isPending()) { await Task.yield() }
    cancelled.cancel(); await auth.finish()
    #expect(!(await cancelled.value)); #expect(!isolated.isUnlocked)
    let old = Task { await isolated.unlock() }
    while !(await auth.isPending()) { await Task.yield() }
    let new = Task { await isolated.unlock() }
    while await auth.count() < 2 { await Task.yield() }
    await auth.finish(); #expect(!(await old.value))
    await auth.finish(); #expect(await new.value)
}
