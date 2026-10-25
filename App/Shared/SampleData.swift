#if DEBUG
import Foundation
import SwiftData
import IDCore

@MainActor enum SampleData {
    static func seed(_ context: ModelContext) throws {
        let arguments = ProcessInfo.processInfo.arguments
        if let flag = arguments.firstIndex(of: "-uiTestingReviewDesign"), flag + 1 < arguments.count,
           ["cardy.12", "cardy.15", "cardy.22", "cardy.26"].contains(arguments[flag + 1]) {
            let face = CardFace(design: arguments[flag + 1],
                colors: CardColors(primary: "#F5B635", secondary: "#0DB774", accent: "#0DB774"))
            let payload = IDPayload(values: ["bank": "Test Bank", "cardholderName": "Test Person", "cardExpiry": "08/29",
                "cardNumber": "4111111111111111", "cardDesign": CardDesign.face(face).rawValue])
            let record = try IDRecord(kind: .debitCard, person: nil, payload: payload)
            record.nickname = "Review Card"
            context.insert(record)
            try context.save()
            return
        }
        if let flag = arguments.firstIndex(of: "-uiTestingStressCase"), flag + 1 < arguments.count,
           let index = Int(arguments[flag + 1]), CardStressFixtures.cases.indices.contains(index) {
            let fixture = CardStressFixtures.cases[index]
            var payload = IDPayload(values: ["bank": "Test Bank", "cardholderName": "Test Person", "cardExpiry": "08/29"])
            payload[.cardNumber] = fixture.number
            payload[.cardDesign] = CardDesign.face(fixture.face).rawValue
            let record = try IDRecord(kind: .debitCard, person: nil, payload: payload)
            record.nickname = "Stress Card"
            context.insert(record)
            try context.save()
            return
        }
        if ProcessInfo.processInfo.arguments.contains("-uiTestingFixedDesignsWallet") {
            let designs = ["astra.horizonTicket", "astra.counterform", "astra.postageGarden", "astra.swissSignal",
                            "cardy.2", "cardy.6", "cardy.8", "cardy.12",
                            "cardy.24", "astra.celestialMechanism"]
            for (index, design) in designs.enumerated() {
                let preset = CardFaceCatalog.presets[(index + 6) % CardFaceCatalog.presets.count]
                let face = CardFace(design: design,
                    colors: preset.colors, colorway: .preset, presetID: preset.id, cardColors: preset.colors)
                var payload = IDPayload(values: ["bank": String(format: "Sample Bank %02d", index + 1),
                    "cardholderName": "Test Person", "cardExpiry": "08/29"])
                payload[.cardNumber] = ["4111111111111111", "5555555555554444", "6073840000000000"][index % 3]
                payload[.cardDesign] = CardDesign.face(face).rawValue
                let record = try IDRecord(kind: .creditCard, person: nil, payload: payload)
                record.nickname = String(format: "Design %02d", index + 1)
                record.createdAt = Date(timeIntervalSince1970: Double(index))
                context.insert(record)
            }
            try context.save()
            return
        }
        for (index, kind) in ([IDKind.creditCard, .creditCard, .debitCard] + IDKind.allCases.filter { ![.creditCard, .debitCard].contains($0) }).enumerated() {
            var payload = IDPayload(values: ["name": "Test Person", "givenNames": "Test", "surname": "Person",
                "cardholderName": "Test Person", "accountHolder": "Test Person", "bank": "Sample Bank",
                "aadhaarNumber": "234123412346", "vid": "9876543210987656", "panNumber": "ABCDE1234F",
                "passportNumber": "K1234567", "epicNumber": "ABC1234567", "dlNumber": "MH12-20110012345",
                "accountNumber": "001234567890", "uanNumber": "100123456789", "dateOfBirth": "1990-01-01",
                "fatherName": "Sample Person", "gender": "Male", "address": "12 Sample Road, Pune\nMaharashtra 411001",
                "cardExpiry": "08/29", "dateOfExpiry": "2034-06-14", "ifsc": "TEST0000123",
                "accountType": "Savings", "nationality": "Indian", "sex": "M", "vehicleClasses": "LMV, MCWG"])
            if index < 3 {
                payload[.cardDesign] = [CardDesign.hsbcLivePlus, .hdfcPixelPlay, .hdfcMillennia][index].rawValue
                payload[.bank] = index == 0 ? "HSBC" : "HDFC Bank"
                payload[.cardNumber] = ["4242424242424242", "4111111111117781", "4111111111111111"][index]
                // README screenshots: public designs and neutral names, no replica art or real bank names.
                if ProcessInfo.processInfo.arguments.contains("-publicSampleData") {
                    let preset = CardFaceCatalog.presets[[6, 1, 3][index]]
                    payload[.cardDesign] = CardDesign.face(CardFace(design: ["cardy.12", "astra.horizonTicket", "astra.swissSignal"][index],
                        colors: preset.colors, colorway: .preset, presetID: preset.id, cardColors: preset.colors)).rawValue
                    payload[.bank] = ["Sample Bank", "Example Bank", "Demo Bank"][index]
                }
            }
            if index == 2 && ProcessInfo.processInfo.arguments.contains("-uiTestingFixedDesigns") {
                var face = CardFaceCatalog.fallback(for: "Sample Bank")
                face.colors = CardFaceCatalog.presets[6].colors
                face.presetID = CardFaceCatalog.presets[6].id
                face.cardColors = CardFaceCatalog.presets[7].colors
                payload[.cardDesign] = CardDesign.face(face).rawValue
            }
            if index == 2 && arguments.contains("-uiTestingLegacyDesign") { payload[.cardDesign] = "generic.ocean" }
            if index == 2 && arguments.contains("-uiTestingMissingDesign") { payload[.cardDesign] = nil }
            if index == 2 && arguments.contains("-uiTestingFutureDesign") { payload[.cardDesign] = "design99:future-format" }
            if index == 2 && arguments.contains("-uiTestingUnknownDesign1") {
                payload[.cardDesign] = ##"design1:{ "future": {"finish":"foil"}, "design":"cardy.999", "colors":{"primary":"#F5B635","secondary":"#0DB774","accent":"#0DB774"}, "colorway":"custom" }"##
            }
            if index == 2 && arguments.contains("-uiTestingOverlappingColours") {
                payload[.cardDesign] = CardDesign.face(CardFace(design: "cardy.15",
                    colors: CardColors(primary: "#777777", secondary: "#777777", accent: "#777777"))).rawValue
            }
            if index == 0 && ProcessInfo.processInfo.arguments.contains("-uiTestingCVV") { payload[.cvv] = "987" }
            if kind == .uan { payload.pfAccounts = [PFAccount(memberID: "MHBAN00000000000000001", employer: "Sample Employer")] }
            let record = try IDRecord(kind: kind, person: nil, payload: payload)
            record.createdAt = Date(timeIntervalSince1970: Double(index))
            if index < 3 { record.nickname = ProcessInfo.processInfo.arguments.contains("-publicSampleData")
                ? ["Travel Card", "Everyday", "Savings Debit"][index] : ["HSBC Live+", "HDFC Pixel Play", "HDFC Millennia"][index] }
            context.insert(record)
        }
        try context.save()
    }
}
#endif
