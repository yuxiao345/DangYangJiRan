---
name: Luminous Glass
colors:
  surface: '#fcf9f8'
  surface-dim: '#dcd9d9'
  surface-bright: '#fcf9f8'
  surface-container-lowest: '#ffffff'
  surface-container-low: '#f6f3f2'
  surface-container: '#f0edec'
  surface-container-high: '#ebe7e7'
  surface-container-highest: '#e5e2e1'
  on-surface: '#1c1b1b'
  on-surface-variant: '#3c4a3d'
  inverse-surface: '#313030'
  inverse-on-surface: '#f3f0ef'
  outline: '#6c7b6c'
  outline-variant: '#bbcbba'
  surface-tint: '#006d35'
  primary: '#006d35'
  on-primary: '#ffffff'
  primary-container: '#00d16b'
  on-primary-container: '#005326'
  inverse-primary: '#30e27a'
  secondary: '#5c5f60'
  on-secondary: '#ffffff'
  secondary-container: '#e1e3e4'
  on-secondary-container: '#626566'
  tertiary: '#5d5f5f'
  on-tertiary: '#ffffff'
  tertiary-container: '#b5b6b6'
  on-tertiary-container: '#464748'
  error: '#ba1a1a'
  on-error: '#ffffff'
  error-container: '#ffdad6'
  on-error-container: '#93000a'
  primary-fixed: '#62ff96'
  primary-fixed-dim: '#30e27a'
  on-primary-fixed: '#00210c'
  on-primary-fixed-variant: '#005226'
  secondary-fixed: '#e1e3e4'
  secondary-fixed-dim: '#c5c7c8'
  on-secondary-fixed: '#191c1d'
  on-secondary-fixed-variant: '#454748'
  tertiary-fixed: '#e2e2e2'
  tertiary-fixed-dim: '#c6c6c7'
  on-tertiary-fixed: '#1a1c1c'
  on-tertiary-fixed-variant: '#454747'
  background: '#fcf9f8'
  on-background: '#1c1b1b'
  surface-variant: '#e5e2e1'
typography:
  display:
    fontFamily: Space Grotesk
    fontSize: 64px
    fontWeight: '700'
    lineHeight: '1.1'
    letterSpacing: -0.04em
  headline-lg:
    fontFamily: Space Grotesk
    fontSize: 40px
    fontWeight: '600'
    lineHeight: '1.2'
    letterSpacing: -0.02em
  headline-lg-mobile:
    fontFamily: Space Grotesk
    fontSize: 32px
    fontWeight: '600'
    lineHeight: '1.2'
    letterSpacing: -0.02em
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
  body-md:
    fontFamily: Space Grotesk
    fontSize: 16px
    fontWeight: '400'
    lineHeight: '1.6'
  label-md:
    fontFamily: Space Grotesk
    fontSize: 14px
    fontWeight: '500'
    lineHeight: '1.2'
    letterSpacing: 0.05em
  label-sm:
    fontFamily: Space Grotesk
    fontSize: 12px
    fontWeight: '700'
    lineHeight: '1.2'
    letterSpacing: 0.1em
rounded:
  sm: 0.25rem
  DEFAULT: 0.5rem
  md: 0.75rem
  lg: 1rem
  xl: 1.5rem
  full: 9999px
spacing:
  base: 8px
  gutter: 24px
  margin-mobile: 16px
  margin-desktop: 64px
  container-max: 1440px
---

## Brand & Style

This design system embodies the intersection of high-end precision and organic fluidity. The visual narrative is built on "Prismatic Clarity"—a light-mode interpretation of futuristic interfaces where information floats within a liquid, translucent environment. 

The aesthetic blends **Minimalism** with **Glassmorphism**, prioritizing heavy whitespace and high-contrast typography to ensure a premium, airy feel. The emotional response is one of optimism, technological sophistication, and clinical cleanliness. It is designed for users who value cutting-edge aesthetics without sacrificing the readability and ergonomics of a professional tool.

## Colors

The palette is anchored by a high-transparency foundation. The primary accent is a refined **Spring Green (#00D16B)**, adjusted from neon for optimal legibility and "pop" against white surfaces while maintaining its high-energy vibration.

- **Surface:** The base layer uses a crisp off-white (#F8F9FA) to reduce eye strain compared to pure white.
- **Glass Layers:** Cards and overlays utilize a semi-transparent white (RGBA 255, 255, 255, 0.4) combined with a heavy backdrop-blur (20px+) to create depth.
- **Text:** Deep charcoal (#121212) provides a grounded, authoritative contrast against the ephemeral glass elements.
- **Accents:** Use the primary green sparingly for interactive states, progress indicators, and critical calls to action.

## Typography

The design system utilizes **Space Grotesk** exclusively to maintain a technical, geometric rhythm across all levels. 

For large display headings, use tight letter-spacing and bold weights to emphasize the "pixel-precise" nature of the brand. For labels and functional text, increase the letter-spacing and use uppercase styling to evoke a sense of instrumentation and data-density. Ensure that body copy maintains a generous line height (1.6) to balance the geometric stiffness of the typeface with readability.

## Layout & Spacing

This design system follows a **Fluid Grid** model with an emphasis on "negative space as a luxury." 

A 12-column grid is used for desktop layouts, with generous 64px outer margins to allow the glass components to breathe. Spacing follows a strictly linear 8px scale (8, 16, 24, 32, 48, 64, 80). 

On mobile devices, margins compress to 16px, and the grid collapses to 4 columns. Containers should use dynamic padding—often larger than standard systems—to enhance the "airy" feel of the floating glass panels.

## Elevation & Depth

Depth is not communicated through traditional dark shadows, but through **translucency levels and white-on-white layering.**

1.  **Base Layer:** The solid #F8F9FA background.
2.  **Level 1 (Cards):** White glass (40% opacity) with a 20px backdrop-blur and a very subtle 1px inner stroke (10% white) to define the edges.
3.  **Level 2 (Modals/Popovers):** Higher opacity white (70%) with a 40px backdrop-blur and a soft, wide-dispersion ambient shadow (Color: #000, Opacity: 0.04, Blur: 40px).
4.  **Floating Elements:** Elements like buttons utilize a "liquid" highlight—a subtle gradient stroke that catches the light, simulating a physical glass edge.

## Shapes

The shape language is sophisticated and rounded, mimicking the look of polished, machined glass. 

- **Components (Buttons, Inputs):** 0.5rem (8px) radius.
- **Containers (Cards, Sections):** 1rem (16px) radius.
- **Large Panels:** 1.5rem (24px) radius.

Avoid "pill" shapes for standard buttons to maintain the technical geometric vibe of Space Grotesk; use the "Rounded" (8px) standard instead. The consistent corner radius across nested elements is critical to maintaining the "Liquid Glass" aesthetic.

## Components

### Buttons
Primary buttons use a solid Spring Green (#00D16B) background with Black text for maximum impact. Secondary buttons are "Glass buttons": semi-transparent white with a 1px charcoal outline at 10% opacity. All buttons feature a subtle scale-down effect (98%) on press to simulate physical feedback.

### Cards
Cards are the hero of the system. They must always feature `backdrop-filter: blur(20px)` and a `background: rgba(255, 255, 255, 0.4)`. A 1px border with a linear gradient (Top-Left: White 30% to Bottom-Right: White 0%) creates a "specular highlight" on the edge.

### Input Fields
Inputs are minimal: a simple bottom border (2px) in light grey that transitions to Spring Green on focus. The input area itself can have a very faint glass tint to differentiate it from the base surface.

### Chips & Tags
Small, high-contrast badges. Use a light version of the accent color (10% opacity green) with solid green text for labels.

### Lists
List items are separated by generous whitespace rather than heavy lines. Use a subtle 1px divider in #EEEEEE or rely entirely on the 8px spacing grid for separation.