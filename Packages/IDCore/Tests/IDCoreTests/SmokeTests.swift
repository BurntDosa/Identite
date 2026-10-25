import Testing
@testable import IDCore
@Test func packageBuilds() { #expect(IDCore.version == "1") }
