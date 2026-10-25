import SwiftUI
import SwiftData
import IDCore

struct RecordEditorView: View {
    let kind: IDKind
    let record: IDRecord?
    var onSaved: (() -> Void)?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(SessionLock.self) private var session
    @Query(sort: \Person.createdAt) private var people: [Person]
    @State private var payload: IDPayload
    @State private var nickname: String
    @State private var notes: String
    @State private var personID: UUID?
    @State private var decodeFailed: Bool
    @State private var cvvRevealed = false
    @State private var cvvRevealTask: Task<Void, Never>?
    @State private var confirmSave = false
    @State private var saveFailed = false
    @State private var confirmDiscard = false
    @State private var initialPayload: IDPayload
    @State private var initialNickname: String
    @State private var initialNotes: String
    @State private var initialPersonID: UUID?
    #if DEBUG
    var onDirtyStateChange: ((Bool) -> Void)?
    #endif
    #if os(iOS)
    @State private var scanning: ScanAttempt?
    @State private var scanningField: CameraField?
    @State private var scanError: String?
    #endif

    init(kind: IDKind, record: IDRecord?, prefill: [FieldKey: String] = [:], onSaved: (() -> Void)? = nil) {
        self.kind = kind; self.record = record; self.onSaved = onSaved
        var initial = IDPayload()
        var failed = false
        if let record {
            do { initial = try record.payload() } catch { failed = true }
        }
        for (key, value) in prefill where initial[key] == nil { initial[key] = value }
        if record == nil, [.creditCard, .debitCard].contains(kind), initial[.cardDesign] == nil {
            initial[.cardDesign] = CardDesign.face(Self.newBankFace()).rawValue
        }
        _initialPayload = State(initialValue: initial)
        _initialNickname = State(initialValue: record?.nickname ?? "")
        _initialNotes = State(initialValue: record?.notes ?? "")
        _initialPersonID = State(initialValue: record?.person?.id)
        _payload = State(initialValue: initial)
        _decodeFailed = State(initialValue: failed)
        _nickname = State(initialValue: record?.nickname ?? "")
        _notes = State(initialValue: record?.notes ?? "")
        _personID = State(initialValue: record?.person?.id)
    }

    static func newBankFace() -> CardFace {
        var generator = SystemRandomNumberGenerator()
        let preset = CardFaceCatalog.presets.randomElement(using: &generator)!
        return CardFaceCatalog.random(colors: preset.colors, colorway: .preset, presetID: preset.id, using: &generator)
    }

    static func applyScannedColors(_ colors: CardColors, to payload: inout IDPayload) {
        var face: CardFace
        if let raw = payload[.cardDesign], case .face(let current) = CardDesign(rawValue: raw) { face = current }
        else { var generator = SystemRandomNumberGenerator(); face = CardFaceCatalog.random(colors: colors, using: &generator) }
        face.colors = colors; face.cardColors = colors; face.colorway = .card; face.presetID = nil
        payload[.cardDesign] = CardDesign.face(face).rawValue
    }

    var body: some View {
        Form {
            if decodeFailed {
                Text("This ID can't be opened in this version").foregroundStyle(.red)
            } else {
                if kind != .creditCard && kind != .debitCard {
                    Section {
                        CardFaceView(kind: kind, payload: normalizedPayload).frame(maxWidth: 440)
                            .frame(maxWidth: .infinity).listRowBackground(Color.clear)
                    }
                }
                Section {
                    Picker("Person", selection: $personID) {
                        Text("Me").tag(nil as UUID?)
                        ForEach(people) { Text($0.name).tag(Optional($0.id)) }
                    }
                    HStack {
                        SensitiveTextField(title: "Nickname", text: $nickname, input: .text, canCopy: { session.isUnlocked })
                            .accessibilityIdentifier("editor-nickname")
                        #if os(iOS)
                        cameraButton("Nickname", text: $nickname)
                        #endif
                    }
                }
                Section {
                    ForEach(kind.fields) { spec in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .top) {
                                field(spec)
                                #if os(iOS)
                                if spec.input == .text || spec.input == .multiline || spec.input == .digits || spec.input == .monthYear {
                                    cameraButton(spec.label, text: binding(spec.key), key: spec.key)
                                }
                                #endif
                            }
                            if let warning = Validator.warning(for: spec.key, value: Validator.normalized(payload[spec.key] ?? "", for: spec.key)) {
                                Text(warning).font(.caption).foregroundStyle(.red)
                            }
                        }
                    }
                }
                if kind == .creditCard || kind == .debitCard {
                    CardCustomizeView(kind: kind, payload: $payload)
                }
                if kind.hasPFAccounts {
                    Section("PF accounts") {
                        ForEach($payload.pfAccounts) { $account in
                            VStack {
                                HStack {
                                    SensitiveTextField(title: "Member ID", text: $account.memberID, input: .text, canCopy: { session.isUnlocked })
                                    #if os(iOS)
                                    cameraButton("Member ID", text: $account.memberID)
                                    #endif
                                }
                                HStack {
                                    SensitiveTextField(title: "Employer", text: $account.employer, input: .text, canCopy: { session.isUnlocked })
                                    #if os(iOS)
                                    cameraButton("Employer", text: $account.employer)
                                    #endif
                                }
                                Button("Remove account", role: .destructive) { payload.pfAccounts.removeAll { $0.id == account.id } }
                            }
                        }
                        Button("Add PF account") { payload.pfAccounts.append(PFAccount(memberID: "", employer: "")) }
                    }
                }
                Section("Notes") {
                    HStack(alignment: .top) {
                        SensitiveTextField(title: "Notes", text: $notes, input: .multiline, canCopy: { session.isUnlocked })
                        #if os(iOS)
                        cameraButton("Notes", text: $notes)
                        #endif
                    }
                }
            }
        }
        .formStyle(.grouped)
        #if os(iOS)
        .scrollDismissesKeyboard(.immediately)
        #endif
        .navigationTitle(record == nil ? "Add \(kind.displayName)" : "Edit \(kind.displayName)")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(record == nil)
        .sheet(item: $scanning) { attempt in
            DocumentScanner(kind: kind) { result in
                guard session.isUnlocked, attempt.generation == session.authorizationGeneration,
                      scanning?.id == attempt.id else { return }
                scanning = nil
                switch result {
                case .success(let outcome):
                    for (key, value) in outcome.fields where (payload[key] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        payload[key] = value
                    }
                    if let colors = outcome.colors {
                        Self.applyScannedColors(colors, to: &payload)
                    }
                case .failure: scanError = "Couldn't read this scan. Try again or enter the details."
                }
            }
        }
        .sheet(item: $scanningField) { target in
            FieldTextScanner(label: target.label) { text in
                guard session.isUnlocked, target.generation == session.authorizationGeneration,
                      scanningField?.id == target.id else { return }
                target.text.wrappedValue = target.key.map { Validator.normalized(text, for: $0) }
                    ?? text.trimmingCharacters(in: .whitespacesAndNewlines)
                scanningField = nil
            }
        }
        .alert("Scan unavailable", isPresented: Binding(get: { scanError != nil }, set: { if !$0 { scanError = nil } })) {
            Button("OK") { scanError = nil }
        } message: { Text(scanError ?? "") }
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", role: .cancel) { if hasChanges { confirmDiscard = true } else { dismiss() } }
            }
            #if os(iOS)
            ToolbarItem(placement: .primaryAction) {
                if kind.isScannable {
                    Button("Scan", systemImage: "doc.viewfinder") {
                        if DocumentScanner.isSupported { scanning = ScanAttempt(generation: session.authorizationGeneration) }
                        else { scanError = "The document camera isn't available on this device. You can enter the details manually." }
                    }.disabled(decodeFailed)
                }
            }
            #endif
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { if hasWarnings { confirmSave = true } else { save() } }
                    .disabled(decodeFailed || !session.isUnlocked).accessibilityIdentifier("editor-save")
                    #if DEBUG
                    .accessibilityValue(ProcessInfo.processInfo.arguments.contains("-uiTestingInMemoryStore") ? payload[.cardDesign] ?? "" : "")
                    #endif
            }
        }
        .confirmationDialog("Save anyway?", isPresented: $confirmSave, titleVisibility: .visible) {
            Button("Save anyway") { save() }
            Button("Cancel", role: .cancel) { }
        } message: { Text("Some required fields are missing or don't look valid. Check the details before saving.") }
        .alert("Couldn't save this ID. Please try again.", isPresented: $saveFailed) { Button("OK") { } }
        .confirmationDialog("Discard Changes?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Discard Changes", role: .destructive) { dismiss() }
            Button("Keep Editing", role: .cancel) { }
        } message: { Text("Your changes to this ID will not be saved.") }
        .interactiveDismissDisabled(hasChanges)
        #if os(iOS)
        .background(DismissAttemptObserver(hasChanges: hasChanges) { confirmDiscard = true })
        #endif
        #if DEBUG
        .onChange(of: hasChanges, initial: true) { _, dirty in onDirtyStateChange?(dirty) }
        #endif
        .onDisappear { resetSensitiveWork() }
        .onChange(of: session.isUnlocked) { _, unlocked in
            if !unlocked { resetSensitiveWork() }
        }
    }

    #if os(iOS)
    private struct ScanAttempt: Identifiable {
        let id = UUID()
        let generation: Int
    }
    private struct CameraField: Identifiable {
        let id = UUID()
        let label: String
        let text: Binding<String>
        let key: FieldKey?
        let generation: Int
    }
    private func cameraButton(_ label: String, text: Binding<String>, key: FieldKey? = nil) -> some View {
        Button {
            if FieldTextScanner.isSupported { scanningField = CameraField(label: label, text: text, key: key, generation: session.authorizationGeneration) }
            else { scanError = "Live text capture isn't available. You can enter this field manually." }
        } label: { Image(systemName: "text.viewfinder").frame(minWidth: 44, minHeight: 44) }
            .buttonStyle(.borderless).accessibilityLabel("Scan \(label) from camera")
    }
    #endif

    private func resetSensitiveWork() {
        cvvRevealTask?.cancel(); cvvRevealTask = nil; cvvRevealed = false
        #if os(iOS)
        scanning = nil; scanningField = nil; scanError = nil
        #endif
    }

    private let uppercaseFields: Set<FieldKey> = [.panNumber, .ifsc, .epicNumber, .passportNumber, .dlNumber]
    private var normalizedPayload: IDPayload {
        var result = payload
        for spec in kind.fields { result[spec.key] = Validator.normalized(payload[spec.key] ?? "", for: spec.key) }
        return result
    }
    private func binding(_ key: FieldKey) -> Binding<String> {
        Binding(get: { payload[key] ?? "" }, set: { payload[key] = $0 })
    }
    @ViewBuilder private func field(_ spec: FieldSpec) -> some View {
        switch spec.input {
        case .date:
            VStack(alignment: .leading) {
                if payload[spec.key] == nil {
                    Button("Set \(spec.label)") { payload[spec.key] = Self.dateString(.now) }
                } else {
                    DatePicker(spec.label, selection: Binding(get: {
                        Self.dateFormatter.date(from: payload[spec.key] ?? "") ?? .now
                    }, set: { payload[spec.key] = Self.dateString($0) }), displayedComponents: .date)
                    Button("Clear \(spec.label)") { payload[spec.key] = nil }.font(.caption)
                }
            }
        case .choice(let choices):
            Picker(spec.label, selection: binding(spec.key)) {
                Text("Choose…").tag("")
                ForEach(choices, id: \.self) { Text($0).tag($0) }
                if let value = payload[spec.key], !choices.contains(value) { Text(value).tag(value) }
            }
        default:
            VStack(alignment: .leading, spacing: 5) {
                Text(spec.label).font(.caption).foregroundStyle(.secondary)
                Group {
                    if spec.requiresFreshAuthentication {
                        HStack {
                            if cvvRevealed { SensitiveTextField(title: spec.label, text: binding(spec.key)) }
                            else { SecureField(spec.label, text: binding(spec.key)) }
                            Button(cvvRevealed ? "Hide" : "Show") {
                                if cvvRevealed { cvvRevealed = false }
                                else {
                                    cvvRevealTask?.cancel()
                                    cvvRevealTask = Task { @MainActor in
                                        let success: Bool
                                        #if DEBUG
                                        if ProcessInfo.processInfo.arguments.contains("-uiTestingInMemoryStore") &&
                                           ProcessInfo.processInfo.arguments.contains("-uiTestingCVVReveal") { success = true }
                                        else { success = await LocalAuthenticator().authenticate(reason: "Show CVV") }
                                        #else
                                        success = await LocalAuthenticator().authenticate(reason: "Show CVV")
                                        #endif
                                        guard !Task.isCancelled, session.isUnlocked else { return }
                                        cvvRevealed = success
                                    }
                                }
                            }.buttonStyle(.borderless).accessibilityLabel(cvvRevealed ? "Hide CVV" : "Show CVV")
                        }.privacySensitive()
                    } else {
                        SensitiveTextField(title: spec.label, text: binding(spec.key), input: spec.input,
                            uppercase: uppercaseFields.contains(spec.key), canCopy: { session.isUnlocked })
                    }
                }
                    .accessibilityIdentifier("editor-" + spec.key.rawValue)
                    #if os(macOS)
                    .labelsHidden().accessibilityLabel(spec.label)
                    #endif
                    .autocorrectionDisabled()
                    .onChange(of: payload[spec.key]) { _, value in
                        if uppercaseFields.contains(spec.key), let value {
                            let normalized = Validator.normalized(value, for: spec.key)
                            if value != normalized { payload[spec.key] = normalized }
                        }
                    }
                    #if os(iOS)
                    .keyboardType(spec.input == .digits ? .numberPad : .default)
                    .textInputAutocapitalization(uppercaseFields.contains(spec.key) ? .characters : .never)
                    #endif
            }
        }
    }
    private static var dateFormatter: DateFormatter {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian); formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }
    private static func dateString(_ date: Date) -> String { dateFormatter.string(from: date) }
    private var hasChanges: Bool {
        payload != initialPayload || nickname != initialNickname || notes != initialNotes || personID != initialPersonID
    }
    private var hasWarnings: Bool {
        kind.fields.contains {
            let value = Validator.normalized(payload[$0.key] ?? "", for: $0.key)
            return (!$0.isOptional && value.isEmpty) || Validator.warning(for: $0.key, value: value) != nil
        }
    }
    private func save() {
        guard session.isUnlocked, !decodeFailed else { return }
        do {
            var normalized = normalizedPayload
            if [.creditCard, .debitCard].contains(kind),
               normalized[.cardDesign]?.hasPrefix("design1:") != true,
               let design = normalized[.cardDesign].flatMap(CardDesign.init(rawValue:)) {
                normalized[.cardDesign] = design.rawValue
            }
            for index in normalized.pfAccounts.indices {
                normalized.pfAccounts[index].memberID = normalized.pfAccounts[index].memberID.trimmingCharacters(in: .whitespacesAndNewlines)
                normalized.pfAccounts[index].employer = normalized.pfAccounts[index].employer.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            let target = try record ?? IDRecord(kind: kind, person: nil, payload: normalized)
            if record == nil { context.insert(target) }
            try target.setPayload(normalized)
            target.nickname = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
            target.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
            target.person = people.first { $0.id == personID }
            try context.save()
            if let onSaved { onSaved() } else { dismiss() }
        } catch { context.rollback(); saveFailed = true }
    }
}

#if os(iOS)
private struct DismissAttemptObserver: UIViewControllerRepresentable {
    let hasChanges: Bool
    let onAttempt: () -> Void

    func makeUIViewController(context: Context) -> Controller { Controller() }
    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.hasChanges = hasChanges
        controller.onAttempt = onAttempt
        // SwiftUI attaches and updates the hosting presentation after this representable.
        DispatchQueue.main.async { [weak controller] in controller?.attach() }
    }
    static func dismantleUIViewController(_ controller: Controller, coordinator: ()) { controller.detach() }

    final class Controller: UIViewController, UIAdaptivePresentationControllerDelegate {
        var hasChanges = false
        var onAttempt: (() -> Void)?
        private weak var presentation: UIPresentationController?
        private weak var previous: (any UIAdaptivePresentationControllerDelegate)?

        override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); attach() }
        override func viewDidLayoutSubviews() { super.viewDidLayoutSubviews(); attach() }
        override func didMove(toParent parent: UIViewController?) { super.didMove(toParent: parent); attach() }
        func attach() {
            var host = parent
            while let candidate = host {
                if candidate.presentingViewController?.presentedViewController === candidate,
                   let presentation = candidate.presentationController {
                    if presentation.delegate !== self {
                        detach()
                        self.presentation = presentation
                        previous = presentation.delegate
                        presentation.delegate = self
                    }
                    return
                }
                host = candidate.parent
            }
        }
        func detach() {
            if presentation?.delegate === self { presentation?.delegate = previous }
            presentation = nil; previous = nil
        }
        func presentationControllerShouldDismiss(_ presentationController: UIPresentationController) -> Bool {
            !hasChanges && (previous?.presentationControllerShouldDismiss?(presentationController) ?? true)
        }
        func presentationControllerDidAttemptToDismiss(_ presentationController: UIPresentationController) {
            if hasChanges { onAttempt?() }
            else { previous?.presentationControllerDidAttemptToDismiss?(presentationController) }
        }
        func presentationControllerWillDismiss(_ presentationController: UIPresentationController) {
            previous?.presentationControllerWillDismiss?(presentationController)
        }
        func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
            previous?.presentationControllerDidDismiss?(presentationController)
        }
    }
}
#endif
