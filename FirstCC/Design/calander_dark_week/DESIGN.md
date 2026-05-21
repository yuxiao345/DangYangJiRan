---
name: Pixel-Glass
colors:
  surface: '#131313'
  surface-dim: '#131313'
  surface-bright: '#3a3939'
  surface-container-lowest: '#0e0e0e'
  surface-container-low: '#1c1b1b'
  surface-container: '#201f1f'
  surface-container-high: '#2a2a2a'
  surface-container-highest: '#353534'
  on-surface: '#e5e2e1'
  on-surface-variant: '#b9cbb8'
  inverse-surface: '#e5e2e1'
  inverse-on-surface: '#313030'
  outline: '#849584'
  outline-variant: '#3b4b3c'
  surface-tint: '#00e471'
  primary: '#f0ffed'
  on-primary: '#003917'
  primary-container: '#00ff7f'
  on-primary-container: '#007134'
  inverse-primary: '#006d33'
  secondary: '#ffb3af'
  on-secondary: '#68000e'
  secondary-container: '#91081a'
  on-secondary-container: '#ff9994'
  tertiary: '#fff9ff'
  on-tertiary: '#3c0090'
  tertiary-container: '#e6d8ff'
  on-tertiary-container: '#7521ff'
  error: '#ffb4ab'
  on-error: '#690005'
  error-container: '#93000a'
  on-error-container: '#ffdad6'
  primary-fixed: '#63ff93'
  primary-fixed-dim: '#00e471'
  on-primary-fixed: '#00210b'
  on-primary-fixed-variant: '#005224'
  secondary-fixed: '#ffdad7'
  secondary-fixed-dim: '#ffb3af'
  on-secondary-fixed: '#410005'
  on-secondary-fixed-variant: '#91081a'
  tertiary-fixed: '#e9ddff'
  tertiary-fixed-dim: '#d1bcff'
  on-tertiary-fixed: '#23005b'
  on-tertiary-fixed-variant: '#5700c9'
  background: '#131313'
  on-background: '#e5e2e1'
  surface-variant: '#353534'
typography:
  display-lg:
    fontFamily: Space Grotesk
    fontSize: 48px
    fontWeight: '700'
    lineHeight: '1.1'
    letterSpacing: -0.02em
  display-lg-mobile:
    fontFamily: Space Grotesk
    fontSize: 32px
    fontWeight: '700'
    lineHeight: '1.2'
  headline-md:
    fontFamily: Space Grotesk
    fontSize: 24px
    fontWeight: '600'
    lineHeight: '1.3'
  body-lg:
    fontFamily: Space Grotesk
    fontSize: 18px
    fontWeight: '400'
    lineHeight: '1.6'
  body-sm:
    fontFamily: Space Grotesk
    fontSize: 14px
    fontWeight: '400'
    lineHeight: '1.5'
  label-caps:
    fontFamily: JetBrains Mono
    fontSize: 12px
    fontWeight: '700'
    lineHeight: '1'
    letterSpacing: 0.1em
  mono-data:
    fontFamily: JetBrains Mono
    fontSize: 14px
    fontWeight: '500'
    lineHeight: '1.4'
rounded:
  sm: 0.25rem
  DEFAULT: 0.5rem
  md: 0.75rem
  lg: 1rem
  xl: 1.5rem
  full: 9999px
spacing:
  unit: 4px
  gutter: 24px
  margin-mobile: 16px
  margin-desktop: 40px
  stack-xs: 8px
  stack-md: 24px
  stack-xl: 64px
---

## Brand & Style
This design system represents a collision between digital nostalgia and futuristic interface design. It blends the structural, lo-fi charm of **8-bit Pixel** aesthetics with the organic, fluid sophistication of **iOS-inspired Glassmorphism**. The target audience comprises tech-savvy investors and crypto-native users who value both heritage gaming culture and premium, high-performance tooling.

The visual style, "Pixel-Glass," uses sharp, aliased content—pixel-perfect icons and technical typography—suspended within a translucent, highly refined liquid environment. The emotional response should be one of high-tech precision mixed with approachable playfulness.

## Colors
The palette is rooted in a high-contrast foundation of deep blacks and pure whites, layered with vibrant, neon-inflected accents.

- **Primary (Neon Green):** Used for growth, success states, and primary actions. It should emit a subtle outer glow when placed against dark glass.
- **Secondary (Soft Red):** Reserved for alerts, liquidations, or destructive actions, treated with a matte glass finish.
- **Tertiary (Electric Purple):** Used for interactive flourishes and mesh gradient nodes.
- **Backgrounds:** Never solid. Use deep charcoal (#0F0F0F) or off-white glass with `backdrop-filter: blur(40px)` and `saturate(150%)`.
- **Mesh Gradients:** Implement soft, animating background blobs using the primary and tertiary colors at 15% opacity to provide depth behind the glass layers.

## Typography
The typography balances geometric modernism with technical precision. **Space Grotesk** provides a futuristic, legible voice for headings and UI copy, while **JetBrains Mono** is used for data points, labels, and "pixel-aligned" values to reinforce the 8-bit aesthetic.

Always ensure high legibility:
- **On Light Glass:** Use #0F0F0F for primary text and #4A4A4A for secondary.
- **On Dark Glass:** Use #FFFFFF for primary text and #A0A0A0 for secondary.
- Use uppercase for labels to mimic early arcade interface constraints.

## Layout & Spacing
The system utilizes a **Fluid Grid** model. Elements are positioned on a strict 4px baseline grid to maintain the "bit" logic, but the containers themselves flow to fill the viewport.

- **Desktop:** 12-column grid with 24px gutters. Content is housed in glass cards that can span multiple columns.
- **Mobile:** 4-column grid with 16px gutters.
- **Inner Padding:** Standard glass containers should use a minimum of 24px internal padding to provide "breathing room" for the sharp pixel content.
- **Vertical Rhythm:** Use the `stack` variables to maintain consistent white space between sections, ensuring the "floating" effect is maintained.

## Elevation & Depth
Depth is achieved through layering and optical physics rather than flat offsets.

1.  **Backdrop:** Mesh gradients with high-radius blurs (60px+) create the "liquid" environment.
2.  **Base Layer:** Semi-transparent surfaces (Opacity 60-80%) with `backdrop-filter: blur(24px)`.
3.  **Borders:** Each glass element must have a 1px solid inner border (Stroke) at 20% opacity white on top and 10% opacity white on the bottom to simulate a glass edge catching the light.
4.  **Shadows:** Use multi-layered ambient shadows. Example: `0 4px 6px -1px rgba(0,0,0,0.1), 0 10px 15px -3px rgba(0,0,0,0.2)`. No hard 1px/2px black offsets.

## Shapes
In a departure from traditional pixel art, the containers in this system are organic and hyper-rounded.

- **Containers:** Use `rounded-xl` (24px) for all glass cards and modals.
- **Interactive Elements:** Buttons and input fields use a consistent `rounded-lg` (16px).
- **Pixel Content:** Icons and decorative "bits" remain strictly 0px rounded (sharp squares) to create the signature "Pixel-Glass" contrast. The juxtaposition of a sharp pixel icon inside a hyper-rounded glass bubble is the core visual identifier.

## Components

- **Buttons:** Large, 24px rounded shapes. Primary buttons use a solid Neon Green gradient with a subtle outer glow. Ghost buttons use the "Glass Edge" style with centered pixel-art icons.
- **Glass Cards:** The primary layout unit. Features 24px corner radius, a 1px internal white border (20% alpha), and 40px backdrop blur.
- **Pixel Icons:** All iconography must be created on a 16x16 or 24x24 pixel grid. Do not anti-alias or round the corners of the icon paths.
- **Inputs:** Dark glass surfaces with a 1px highlight on the bottom edge. Focus state is indicated by a Neon Green outer glow and the appearance of a pixelated cursor.
- **Chips/Badges:** Pill-shaped glass elements used for status. Use "Pixel-font" (JetBrains Mono) for the text within these tags.
- **Progress Bars:** A smooth glass track containing a "chunky" pixelated filler that increments in visible blocks rather than a smooth gradient.