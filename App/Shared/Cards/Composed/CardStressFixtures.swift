#if DEBUG
import IDCore

/// Synthetic, in-memory stress cases shared by the simulator and Mac render tests.
enum CardStressFixtures {
    struct Fixture {
        let name: String
        let face: CardFace
        let number: String
    }
    static let cases: [Fixture] = [
        Fixture(name: "chrome-fold-garnet", face: CardFace(design: "cardy.8", colors: CardFaceCatalog.presets[6].colors), number: "4111111111113003"),
        Fixture(name: "counterform-equal-garnet", face: CardFace(design: "astra.counterform", colors: CardColors(primary: "#770A3C", secondary: "#770A3C", accent: "#770A3C")), number: "6073840000003003"),
        Fixture(name: "white-maze-visa", face: CardFace(design: "cardy.12", colors: CardColors(primary: "#FFFFFF", secondary: "#FFFFFF", accent: "#FFFFFF")), number: "4111111111113003"),
        Fixture(name: "white-maze-rupay", face: CardFace(design: "cardy.12", colors: CardColors(primary: "#FFFFFF", secondary: "#FFFFFF", accent: "#FFFFFF")), number: "6073840000003003"),
        Fixture(name: "overprint-grain-grey", face: CardFace(design: "astra.overprintPress", colors: CardColors(primary: "#414141", secondary: "#424341", accent: "#414442")), number: "6073840000003003"),
        Fixture(name: "foil-split-graphite", face: CardFace(design: "cardy.7", colors: CardFaceCatalog.presets[0].colors), number: "6073840000003003"),
    ]
}
#endif
