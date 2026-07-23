import SwiftUI

enum LHTheme {
    static let mist = Color(hex: 0xF5F7F4)
    static let paper = Color.white
    static let ink = Color(hex: 0x152238)
    static let repairBlue = Color(hex: 0x3D63FF)
    static let maskCoral = Color(hex: 0xFF6B5E)
    static let successMint = Color(hex: 0x28B487)
    static let muted = Color(hex: 0x687386)
    static let hairline = Color(hex: 0xDDE3E6)

    static let canvasRadius: CGFloat = 28
    static let controlRadius: CGFloat = 18
}

extension Color {
    init(hex: UInt, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

extension View {
    func lhCard(padding: CGFloat = 16) -> some View {
        self
            .padding(padding)
            .background(LHTheme.paper)
            .clipShape(RoundedRectangle(cornerRadius: LHTheme.controlRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: LHTheme.controlRadius, style: .continuous)
                    .stroke(LHTheme.hairline.opacity(0.8), lineWidth: 1)
            }
    }
}

