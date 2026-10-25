import IDCore
import SwiftData
import XCTest

@MainActor final class PeopleAuthorizationTests: XCTestCase {
    private struct Auth: Authenticator { func authenticate(reason: String) async -> Bool { true } }
    func testPendingAddAndRenameCannotMutateAfterRevocationOrReunlock() async throws {
        let store = try IDStore.makeContainer(inMemory: true)
        let context = store.mainContext
        context.autosaveEnabled = false
        let person = Person(name: "Audit Person")
        context.insert(person); try context.save()
        let session = SessionLock(authenticator: Auth())
        _ = await session.unlock()
        let generation = session.authorizationGeneration
        session.lockNow()
        for reunlock in [false, true] {
            if reunlock { _ = await session.unlock() }
            try PeopleView.saveName("Audit rename", editing: person, in: context, session: session, generation: generation)
            try PeopleView.saveName("Audit new", editing: nil, in: context, session: session, generation: generation)
            XCTAssertTrue(person.name == "Audit Person")
            XCTAssertEqual(try context.fetchCount(FetchDescriptor<Person>()), 1)
            XCTAssertFalse(context.hasChanges)
        }
    }

    func testLockedDeleteDoesNotMutateAndValidActionsStillWork() async throws {
        let store = try IDStore.makeContainer(inMemory: true), session = SessionLock(authenticator: Auth())
        let context = store.mainContext
        context.autosaveEnabled = false
        let person = Person(name: "Audit Person")
        context.insert(person); try context.save()
        try PeopleView.delete(person, in: context, session: session)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Person>()), 1)
        _ = await session.unlock()
        try PeopleView.saveName("Audit renamed", editing: person, in: context, session: session, generation: session.authorizationGeneration)
        XCTAssertTrue(person.name == "Audit renamed")
        try PeopleView.delete(person, in: context, session: session)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Person>()), 0)
    }
}
