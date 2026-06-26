import SwiftUI

// MARK: - Glass Card Modifier

/// Standard glass card matching the Pixel-Glass (dark) / Luminous Glass (light) spec.
/// Dark:  rgba(255,255,255,0.03) + blur(24px) + directional border + multi-layer shadow
/// Light: rgba(255,255,255,0.4)  + blur(20px) + subtle border + soft shadow
struct GlassCardModifier: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial)
            .background(Color.designGlassBg)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color.designGlassBorderHighlight, lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.08), radius: 6, y: -1)
            .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
    }
}

// MARK: - Liquid Background Modifier

/// Screen-level liquid background with radial gradient blobs.
/// Dark:  green blob top-left + red blob bottom-right
/// Light: subtle green blob top-left + milder blob top-right
struct LiquidBackgroundModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    Color.designBackground

                    Circle()
                        .fill(Color.designSurfaceTint.opacity(0.08))
                        .blur(radius: 80)
                        .offset(x: -80, y: -180)
                        .scaleEffect(1.3)

                    Circle()
                        .fill(Color.designTertiaryContainer.opacity(0.06))
                        .blur(radius: 80)
                        .offset(x: 120, y: 280)
                        .scaleEffect(1.2)
                }
                #if os(iOS)
                .ignoresSafeArea()
                #endif
            }
    }
}

// MARK: - Hero Card Glow Modifier

/// Internal glow blob placed inside hero/feature cards.
struct HeroGlowModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .overlay(alignment: .topTrailing) {
                Circle()
                    .fill(Color.designPrimaryFixedDim.opacity(0.12))
                    .blur(radius: 60)
                    .frame(width: 128, height: 128)
                    .offset(x: 32, y: -32)
                    .allowsHitTesting(false)
            }
    }
}

// MARK: - Neon Glow Modifier

/// Green outer glow for active/focused elements (dark mode prominent).
struct NeonGlowModifier: ViewModifier {
    let isActive: Bool

    func body(content: Content) -> some View {
        content
            .shadow(
                color: isActive ? Color.designPrimaryFixedDim.opacity(0.4) : .clear,
                radius: isActive ? 12 : 0
            )
    }
}

// MARK: - Pixel Border Modifier (8-bit style)

struct PixelBorderModifier: ViewModifier {
    let color: Color

    func body(content: Content) -> some View {
        content
            .shadow(color: color, radius: 0, x: 0, y: -2)
            .shadow(color: color, radius: 0, x: 0, y: 2)
            .shadow(color: color, radius: 0, x: -2, y: 0)
            .shadow(color: color, radius: 0, x: 2, y: 0)
    }
}

// MARK: - Design Button Styles

/// Primary button: solid Spring Green bg + black text (light) / Neon Green bg + dark text (dark).
/// Light: #00D16B bg, black text. Dark: #00FF7F bg, #003917 text.
struct DesignPrimaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Color.designOnPrimaryContainer)
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .background(Color.designPrimaryContainer)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(
                color: Color.designPrimaryFixedDim.opacity(configuration.isPressed ? 0.15 : 0.35),
                radius: configuration.isPressed ? 4 : 14
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// Glass secondary/ghost button: semi-transparent bg + subtle border.
struct DesignSecondaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Color.designOnSurface)
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .background(Color.designGlassBg)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.designOutline.opacity(0.2), lineWidth: 1)
            }
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Design Input Field Modifier

struct DesignInputModifier: ViewModifier {
    let isFocused: Bool

    func body(content: Content) -> some View {
        content
            .padding(.vertical, 8)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(isFocused ? Color.designPrimaryContainer : Color.designOutlineVariant)
                    .frame(height: 2)
            }
    }
}

// MARK: - Design Chip/Badge Modifier

struct DesignChipModifier: ViewModifier {
    let color: Color

    func body(content: Content) -> some View {
        content
            .font(.caption)
            .fontWeight(.medium)
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(color.opacity(0.1))
            .clipShape(Capsule())
    }
}

// MARK: - Design List Row Modifier

struct DesignListRowModifier: ViewModifier {
    let isLast: Bool

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .overlay(alignment: .bottom) {
                if !isLast {
                    Rectangle()
                        .fill(Color.designOutlineVariant.opacity(0.3))
                        .frame(height: 1)
                        .padding(.leading, 16)
                }
            }
    }
}

// MARK: - Glass Section Modifier (compact card with padding)

struct GlassSectionModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(Color.designGlassBg)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.designGlassBorderHighlight, lineWidth: 1)
            }
    }
}

// MARK: - Screen Background Modifier

struct DesignScreenModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .modifier(LiquidBackgroundModifier())
    }
}

// MARK: - View Extensions

extension View {
    /// Full-screen liquid background
    func designScreen() -> some View {
        modifier(DesignScreenModifier())
    }

    /// Glass card with blur + border + shadow
    func glassCard(cornerRadius: CGFloat = 24) -> some View {
        modifier(GlassCardModifier(cornerRadius: cornerRadius))
    }

    /// Glass section with padding + blur
    func glassSection() -> some View {
        modifier(GlassSectionModifier())
    }

    /// Internal glow blob for hero cards
    func heroGlow() -> some View {
        modifier(HeroGlowModifier())
    }

    /// Neon green outer glow (active/focused elements)
    func neonGlow(isActive: Bool = true) -> some View {
        modifier(NeonGlowModifier(isActive: isActive))
    }

    /// 8-bit pixel border effect
    func pixelBorder(color: Color = .designPrimary) -> some View {
        modifier(PixelBorderModifier(color: color))
    }

    /// Design input field with bottom accent line
    func designInput(isFocused: Bool = false) -> some View {
        modifier(DesignInputModifier(isFocused: isFocused))
    }

    /// Chip/tag badge
    func designChip(color: Color = .designPrimaryContainer) -> some View {
        modifier(DesignChipModifier(color: color))
    }

    /// List row with subtle separator
    func designListRow(isLast: Bool = false) -> some View {
        modifier(DesignListRowModifier(isLast: isLast))
    }
}
