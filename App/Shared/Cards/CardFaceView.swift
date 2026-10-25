import SwiftUI
import IDCore

struct CardFaceView: View, Equatable {
    let kind: IDKind
    let payload: IDPayload
    let personName: String?
    private var unavailable = false

    init(kind: IDKind, payload: IDPayload, personName: String? = nil) {
        self.kind = kind
        self.payload = payload
        self.personName = personName
    }

    init(record: IDRecord) {
        kind = record.kind ?? .aadhaar
        personName = record.person?.name
        do {
            payload = try record.payload()
            unavailable = record.kind == nil
        } catch {
            payload = IDPayload()
            unavailable = true
        }
    }

    private var isBank: Bool { kind == .creditCard || kind == .debitCard }
    private var design: CardDesign {
        (payload[.cardDesign].flatMap(CardDesign.init(rawValue:)) ?? .defaultGeneric(forBank: payload[.bank] ?? ""))
            .faceDesign(forBank: payload[.bank] ?? "")
    }
    private var isLight: Bool {
        if isBank {
            if case .face(let face) = design { return face.ink(for: .bank) == "#000000" }
            return false
        }
        return CardPalette.isLight(kind)
    }
    private var holder: String {
        if kind == .passport {
            return [payload[.givenNames], payload[.surname]].compactMap { $0 }.joined(separator: " ")
        }
        return payload[isBank ? .cardholderName : kind == .bankAccount ? .accountHolder : .name] ?? personName ?? ""
    }
    private var numberKey: FieldKey {
        switch kind {
        case .aadhaar: .aadhaarNumber
        case .pan: .panNumber
        case .passport: .passportNumber
        case .voterID: .epicNumber
        case .drivingLicence: .dlNumber
        case .bankAccount: .accountNumber
        case .uan: .uanNumber
        case .creditCard, .debitCard: .cardNumber
        }
    }
    private var masked: Bool { isBank || kind == .aadhaar || kind == .bankAccount }
    var identifier: String {
        let value = payload[numberKey] ?? ""
        if masked { return value.count > 4 ? "•••• " + value.suffix(4) : "••••" }
        if kind == .uan { return FieldFormatter.grouped(value, for: .aadhaarNumber) }
        if kind == .drivingLicence {
            let compact = value.filter { !$0.isWhitespace && $0 != "-" }
            if compact.count == 15 { return String(compact.prefix(4)) + " " + compact.dropFirst(4).prefix(4) + " " + compact.dropFirst(8) }
        }
        return value
    }
    var spokenLabel: String {
        if unavailable { return "This ID can't be opened in this version" }
        let value = payload[numberKey] ?? ""
        let spoken = masked ? (value.count > 4 ? "hidden, ending \(value.suffix(4))" : "hidden") : identifier
        return [kind.displayName, isBank ? (payload[.bank] ?? "") : "", holder, spoken]
            .filter { !$0.isEmpty }.joined(separator: ", ")
    }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            Group {
                if unavailable {
                    ZStack { Color.secondary.opacity(0.12); Text("This ID can't be opened in this version").padding() }
                } else if isBank {
                    BankCardFace(design: design, kind: kind, bank: payload[.bank] ?? "Bank",
                                 network: CardNetwork(cardNumber: payload[.cardNumber] ?? ""), identifier: identifier, width: width)
                } else {
                    IDCardFace(kind: kind, bank: payload[.bank] ?? "", holder: holder, identifier: identifier, width: width)
                }
            }
            .frame(width: width, height: geometry.size.height)
            .modifier(CardStyle(width: width, isLight: isLight, preservesColors: isBank))
        }
        .aspectRatio(kind == .passport ? 1.42 : 1.586, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenLabel)
    }
}
