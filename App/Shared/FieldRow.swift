import SwiftUI
import IDCore
import LocalAuthentication

struct FieldRow: View {
    @Environment(SessionLock.self) private var session
    let spec: FieldSpec
    let value: String
    var isActive = true
    #if os(macOS)
    @Environment(MacCopySelection.self) private var copySelection
    @State private var copyOwner = UUID()
    @FocusState private var focused: Bool
    #endif
    @State private var authentication: LAContext?
    @State private var authenticationTask: Task<Void, Never>?
    @State private var authenticationFailed = false
    @State private var revealed = false
    @State private var copied = false
    @State private var copyGeneration = 0

    private var displayValue: String { FieldFormatter.display(value, for: spec.input) }

    var body: some View {
        HStack(spacing: 12) {
            Button { copy(grouped: false) } label: {
                VStack(alignment: .leading, spacing: 5) {
                    Text(spec.label).font(.caption).foregroundStyle(.secondary)
                    Text(copied ? "✓ Copied" : spec.isMasked && !revealed ? FieldFormatter.masked(value, for: spec.key) : displayValue)
                        .font(.body).foregroundStyle(copied ? Color.accentColor : .primary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }.padding(.vertical, 7).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            #if os(macOS)
            .focusable().focused($focused)
            .onChange(of: focused) { _, value in
                if value { copySelection.select(copyOwner) { copy(grouped: false) } }
                else { copySelection.clear(copyOwner) }
            }
            .onDisappear { copySelection.clear(copyOwner) }
            #endif
            .accessibilityLabel(spec.label)
            .accessibilityValue(copied ? "Copied" : spec.isMasked && !revealed ? "hidden" : displayValue)
            .accessibilityHint("Copies to clipboard")
            .accessibilityIdentifier("copy-" + spec.key.rawValue)
            .contextMenu {
                Button("Copy") { copy(grouped: false) }
                if spec.hasGroupedCopy { Button("Copy with Spaces") { copy(grouped: true) } }
            }
            if spec.isMasked {
                Button(revealed ? "Hide" : "Show") {
                    if revealed { revealed = false }
                    else { authorize(reason: "Show \(spec.label)") { revealed = true } }
                }
                    .buttonStyle(.plain).foregroundStyle(Color.accentColor)
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityLabel("\(revealed ? "Hide" : "Show") \(spec.label)")
                    .accessibilityIdentifier("reveal-" + spec.key.rawValue)
            }
        }
        .privacySensitive()
        .onDisappear { reset() }
        .onChange(of: isActive) { _, active in if !active { reset() } }
        .alert("Authentication required", isPresented: $authenticationFailed) {
            Button("OK") { }
        } message: { Text("Couldn't authenticate. Try again to access this field.") }
        #if os(iOS)
        .sensoryFeedback(.success, trigger: copyGeneration)
        #endif
        .task(id: copyGeneration) {
            guard copied else { return }
            do { try await Task.sleep(for: .seconds(1.5)) } catch { return }
            copied = false
        }
        .onChange(of: session.isUnlocked) { _, unlocked in
            if !unlocked { reset() }
        }
    }

    private func copy(grouped: Bool) {
        authorize(reason: "Copy \(spec.label)") { performCopy(grouped: grouped) }
    }

    private func performCopy(grouped: Bool) {
        guard session.isUnlocked, isActive else { return }
        let normalized = Validator.normalized(value, for: spec.key)
        SecureClipboard.copy(grouped ? FieldFormatter.grouped(normalized, for: spec.key) : FieldFormatter.display(normalized, for: spec.input),
                             lifetime: spec.requiresFreshAuthentication ? 30 : SecureClipboard.lifetime)
        #if os(macOS)
        focused = true
        copySelection.select(copyOwner) { copy(grouped: false) }
        #endif
        copied = true
        copyGeneration += 1
        AccessibilityNotification.Announcement("Copied").post()
    }
    private func authorize(reason: String, action: @escaping @MainActor () -> Void) {
        guard session.isUnlocked, isActive else { return }
        guard spec.requiresFreshAuthentication else { action(); return }
        guard authenticationTask == nil else { return }
        let context = LAContext()
        authentication = context
        authenticationTask = Task { @MainActor in
            let success = (try? await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)) == true
            guard !Task.isCancelled, session.isUnlocked, isActive else { return }
            authenticationTask = nil
            authentication = nil
            if success { action() } else { authenticationFailed = true }
        }
    }
    private func reset() {
        authenticationTask?.cancel()
        authentication?.invalidate()
        authenticationTask = nil
        authentication = nil
        revealed = false
        copied = false
        authenticationFailed = false
    }

}
