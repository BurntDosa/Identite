import Foundation
import Testing
@testable import IDCore
import SwiftData

struct ModelTests {
@MainActor @Test func recordRoundTrip() throws {
  let container = try IDStore.makeContainer(inMemory: true)
  let ctx = ModelContext(container)
  var p = IDPayload(); p[.panNumber] = "ABCDE1234F"
  let r = try IDRecord(kind: .pan, person: nil, payload: p); ctx.insert(r); try ctx.save()
  let fetched = try #require(ModelContext(container).fetch(FetchDescriptor<IDRecord>()).first)
  #expect(fetched.kind == .pan); #expect(try fetched.payload()[.panNumber] == "ABCDE1234F")
}
@MainActor @Test func personWithRecordsCannotBeDeleted() throws {
  let ctx = ModelContext(try IDStore.makeContainer(inMemory: true))
  let mom = Person(name: "Mom"); ctx.insert(mom)
  let r = try IDRecord(kind: .aadhaar, person: mom, payload: IDPayload()); ctx.insert(r); try ctx.save()
  #expect(!mom.canDelete); ctx.delete(r); try ctx.save(); #expect(mom.canDelete)
}
@MainActor @Test func corruptPayloadThrowsInsteadOfEmpty() throws {
  let r = try IDRecord(kind: .pan, person: nil, payload: IDPayload()); r.payloadData = Data("garbage".utf8)
  #expect(throws: (any Error).self) { try r.payload() }
}
@MainActor @Test func unknownKindIsNil() throws { let r = try IDRecord(kind: .pan, person: nil, payload: IDPayload()); r.kindRaw = "rationCard"; #expect(r.kind == nil) }

@MainActor @Test func updatingPayloadPreservesUnknownFieldsAndAdvancesTimestamp() throws {
  let container = try IDStore.makeContainer(inMemory: true)
  let ctx = ModelContext(container)
  let r = try IDRecord(kind: .pan, person: nil, payload: IDPayload(values: ["futureField": "fake value"]))
  ctx.insert(r)
  r.updatedAt = .distantPast
  let createdAt = r.createdAt
  var payload = try r.payload()
  payload[.panNumber] = "ABCDE1234F"
  try r.setPayload(payload)
  try ctx.save()
  let fetched = try #require(ModelContext(container).fetch(FetchDescriptor<IDRecord>()).first)
  #expect(try fetched.payload() == payload)
  #expect(try fetched.payload().values["futureField"] == "fake value")
  #expect(fetched.updatedAt > .distantPast)
  #expect(fetched.createdAt == createdAt)
  #expect(fetched.person == nil)
}

}
