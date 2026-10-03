import SwiftUI

extension ClassEvent {
    /// Colours follow the ones used on plany.ubb.edu.pl.
    var tint: Color { Self.tint(for: kindCode) }

    static func tint(for kindCode: String) -> Color {
        switch kindCode.lowercased() {
        case "wyk": return Color(red: 0.31, green: 0.70, blue: 0.0)
        case "lab": return Color(red: 0.45, green: 0.45, blue: 0.95)
        case "ćw", "cw": return Color(red: 0.20, green: 0.66, blue: 0.90)
        case "lek": return Color(red: 0.95, green: 0.66, blue: 0.20)
        case "proj", "pro": return Color(red: 0.85, green: 0.35, blue: 0.55)
        default: return .gray
        }
    }

    var timeRange: String {
        "\(start.formatted(date: .omitted, time: .shortened)) – \(end.formatted(date: .omitted, time: .shortened))"
    }
}

extension ActivityClass {
    var tint: Color { ClassEvent.tint(for: kind) }
}
