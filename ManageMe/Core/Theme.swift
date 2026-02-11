import SwiftUI

// MARK: - Color Palette

extension Color {
    // Primary accent
    static let appAccent = Color.indigo
    static let appAccentLight = Color.indigo.opacity(0.12)
    static let appAccentSoft = Color.indigo.opacity(0.06)

    // Surfaces
    static let appCard = Color(.systemBackground)
    static let appCardSecondary = Color(.secondarySystemBackground)
    static let appSurfaceElevated = Color(.tertiarySystemBackground)

    // Semantic
    static let appSuccess = Color.green
    static let appWarning = Color.orange
    static let appDanger = Color.red
}

// MARK: - Gradients

extension LinearGradient {
    static let accentGradient = LinearGradient(
        colors: [.indigo, .purple],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let accentSoftGradient = LinearGradient(
        colors: [.indigo.opacity(0.15), .purple.opacity(0.08)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let cardGradient = LinearGradient(
        colors: [.indigo.opacity(0.08), .purple.opacity(0.04)],
        startPoint: .top,
        endPoint: .bottom
    )
}

// MARK: - Design Tokens

enum AppStyle {
    static let cornerRadius: CGFloat = 16
    static let cornerRadiusSmall: CGFloat = 10
    static let cornerRadiusPill: CGFloat = 20

    static let shadowRadius: CGFloat = 8
    static let shadowOpacity: Double = 0.06
    static let shadowY: CGFloat = 4

    static let padding: CGFloat = 16
    static let paddingSmall: CGFloat = 8
    static let paddingLarge: CGFloat = 24

    static let cardSpacing: CGFloat = 12
}

// MARK: - View Modifiers

struct CardStyle: ViewModifier {
    var padding: CGFloat = AppStyle.padding

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(.background)
            .clipShape(RoundedRectangle(cornerRadius: AppStyle.cornerRadius))
            .shadow(
                color: .black.opacity(AppStyle.shadowOpacity),
                radius: AppStyle.shadowRadius,
                y: AppStyle.shadowY
            )
    }
}

struct AccentCardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(AppStyle.padding)
            .background(LinearGradient.accentSoftGradient)
            .clipShape(RoundedRectangle(cornerRadius: AppStyle.cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: AppStyle.cornerRadius)
                    .stroke(Color.accent.opacity(0.15), lineWidth: 1)
            )
    }
}

struct PillBadge: ViewModifier {
    var color: Color = .accent

    func body(content: Content) -> some View {
        content
            .font(.caption2)
            .fontWeight(.semibold)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.12))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}

extension View {
    func cardStyle(padding: CGFloat = AppStyle.padding) -> some View {
        modifier(CardStyle(padding: padding))
    }

    func accentCardStyle() -> some View {
        modifier(AccentCardStyle())
    }

    func pillBadge(color: Color = .accent) -> some View {
        modifier(PillBadge(color: color))
    }
}

// MARK: - Animated Dots (for loading)

struct TypingIndicator: View {
    @State private var animating = false

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(Color.accent.opacity(0.6))
                    .frame(width: 7, height: 7)
                    .scaleEffect(animating ? 1.0 : 0.5)
                    .opacity(animating ? 1.0 : 0.3)
                    .animation(
                        .easeInOut(duration: 0.6)
                        .repeatForever()
                        .delay(Double(index) * 0.2),
                        value: animating
                    )
            }
        }
        .onAppear { animating = true }
    }
}
