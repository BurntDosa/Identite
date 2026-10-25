import Foundation
import Testing
@testable import IDCore
#if os(macOS)
import AppKit

@Suite(.serialized) struct SecureClipboardTests {
@MainActor @Test func normalTerminationClearsOnlyOwnedCopy() {
  let pb = NSPasteboard(name: .init("test-\(UUID())"))
  SecureClipboard.copy("fake secret", to: pb, lifetime: 60)
  NotificationCenter.default.post(name: NSApplication.willTerminateNotification, object: nil)
  #expect(pb.string(forType: .string) == nil)
  SecureClipboard.copy("fake secret", to: pb, lifetime: 60)
  pb.clearContents(); pb.setString("later user copy", forType: .string)
  NotificationCenter.default.post(name: NSApplication.willTerminateNotification, object: nil)
  #expect(pb.string(forType: .string) == "later user copy")
}

@MainActor @Test func customLifetimeClearsAndPreservesPrivacyMarkers() async throws {
  let pb = NSPasteboard(name: .init("test-\(UUID())"))
  SecureClipboard.copy("123", to: pb, lifetime: 0.1)
  #expect(pb.string(forType: .string) == "123")
  #expect(pb.types?.contains(.init("org.nspasteboard.ConcealedType")) == true)
  #expect(pb.types?.contains(.init("org.nspasteboard.TransientType")) == true)
  try await Task.sleep(for: .milliseconds(400))
  #expect(pb.string(forType: .string) == nil)
}

@MainActor @Test func clearsAfterLifetime() async throws {
  let pb = NSPasteboard(name: .init("test-\(UUID())"))
  SecureClipboard.copy("ABCDE1234F", to: pb, clearAfter: .milliseconds(100))
  #expect(pb.string(forType: .string) == "ABCDE1234F")
  #expect(pb.types?.contains(.init("org.nspasteboard.ConcealedType")) == true)
  try await Task.sleep(for: .milliseconds(400))
  #expect(pb.string(forType: .string) == nil)
}
@MainActor @Test func doesNotWipeLaterCopy() async throws {
  let pb = NSPasteboard(name: .init("test-\(UUID())"))
  SecureClipboard.copy("ABCDE1234F", to: pb, clearAfter: .milliseconds(100))
  pb.clearContents(); pb.setString("user text", forType: .string)
  try await Task.sleep(for: .milliseconds(400))
  #expect(pb.string(forType: .string) == "user text")
}


}
#endif
