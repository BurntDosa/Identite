import CloudKit
import XCTest

final class PrivacyCopyTests: XCTestCase {
    @MainActor func testAvailableAccountDoesNotClaimAllIDsAreEndToEndEncrypted() {
        let status = SettingsView.syncStatus(for: .available)
        XCTAssertFalse(status.contains("end-to-end"), "Account availability cannot establish encryption of metadata or backups")
        XCTAssertTrue(status.contains("iCloud"))
    }
}
