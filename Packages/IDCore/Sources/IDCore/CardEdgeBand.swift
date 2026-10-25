import Foundation

/// An edge light covers the entire artwork region, never an individual text box.
public struct CardEdgeBand: Sendable {
    public enum Edge: Sendable { case top, bottom }
    public let edge: Edge
    public let width: Double
    public let color: String
    public let opacity: Double
    public static let height = 0.5
    public static let tastefulOpacity = 0.72

    /// Normalized distance from the card edge; a flat light through the text, then a smooth feather.
    public static let stops: [(location: Double, strength: Double)] = (0...20).map { index in
        let location = Double(index) / 20
        let t = max(0, (location - 0.4) / 0.6)
        return (location, 1 - t * t * (3 - 2 * t))
    }

    public func alpha(atY y: Double) -> Double {
        let distance = (edge == .top ? y : 1 - y) / Self.height
        guard distance >= 0, distance < 1 else { return 0 }
        let i = min(Self.stops.count - 2, Int(distance * 20))
        let a = Self.stops[i], b = Self.stops[i + 1]
        return opacity * (a.strength + (b.strength - a.strength) * (distance - a.location) / (b.location - a.location))
    }
}

public struct CardLegibility: Sendable {
    public let treatments: [CardTextZone: CardTextTreatment]
    public let bands: [CardEdgeBand]

    public subscript(_ zone: CardTextZone) -> CardTextTreatment { treatments[zone]! }
}
