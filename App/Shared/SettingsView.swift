import SwiftUI
import CloudKit
import IDCore

struct SettingsView: View {
    @Environment(SessionLock.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var syncStatus = "Checking iCloud…"
    var body: some View {
        NavigationStack {
            Form {
                Button("Lock Now", systemImage: "lock") { session.lockNow(); dismiss() }
                Section("iCloud") {
                    Text(syncStatus).task { syncStatus = await Self.iCloudStatus() }
                }
                Section("About") {
                    LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                    Text("Card designs adapted from [Cardy](https://piqodesign.gumroad.com/l/cardy) by Piqo Design, [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/)")
                }
            }.formStyle(.grouped).navigationTitle("Settings")
                #if os(iOS)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
                #endif
        }
    }

    private static func iCloudStatus() async -> String {
        syncStatus(for: try? await CKContainer(identifier: "iCloud.com.gagan.IDHolder").accountStatus())
    }

    static func syncStatus(for status: CKAccountStatus?) -> String {
        switch status {
        case .available: "iCloud sync is available."
        case .noAccount: "Off. Sign in to iCloud to sync your IDs."
        case .restricted: "Off. iCloud is restricted on this device."
        default: "iCloud isn't reachable right now. IDs are saved on this device."
        }
    }
}
