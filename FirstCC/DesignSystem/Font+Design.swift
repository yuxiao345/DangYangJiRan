import SwiftUI

// MARK: - Design System Fonts
//
// Space Grotesk: headings, UI, body
// JetBrains Mono: data, labels, monospace values

extension Font {

    // MARK: Space Grotesk (headings & UI)

    /// Display large — 48pt Bold (dark) / 64pt Bold (light)
    static let designDisplay = Font.custom("SpaceGrotesk-Bold", size: 48, relativeTo: .largeTitle)

    /// Display large mobile — 32pt Bold
    static let designDisplayMobile = Font.custom("SpaceGrotesk-Bold", size: 32, relativeTo: .title)

    /// Headline large — 40pt SemiBold
    static let designHeadlineLarge = Font.custom("SpaceGrotesk-SemiBold", size: 40, relativeTo: .largeTitle)

    /// Headline medium — 24pt SemiBold
    static let designHeadlineMedium = Font.custom("SpaceGrotesk-SemiBold", size: 24, relativeTo: .title2)

    /// Body large — 18pt Regular
    static let designBodyLarge = Font.custom("SpaceGrotesk-Regular", size: 18, relativeTo: .body)

    /// Body medium — 16pt Regular
    static let designBodyMedium = Font.custom("SpaceGrotesk-Regular", size: 16, relativeTo: .body)

    /// Body small — 14pt Regular
    static let designBodySmall = Font.custom("SpaceGrotesk-Regular", size: 14, relativeTo: .caption)

    // MARK: JetBrains Mono (data & labels)

    /// Label caps — 12pt Bold, uppercase
    static let designLabel = Font.custom("JetBrainsMono-Bold", size: 12, relativeTo: .caption2)

    /// Label small — 10pt Bold, uppercase (metric card labels)
    static let designLabelSmall = Font.custom("JetBrainsMono-Bold", size: 10)

    /// Mono data — 14pt Medium
    static let designMonoData = Font.custom("JetBrainsMono-Medium", size: 14, relativeTo: .caption)

    /// Mono data small — 12pt Medium
    static let designMonoDataSmall = Font.custom("JetBrainsMono-Medium", size: 12, relativeTo: .caption2)

    /// Mono data compact — 11pt Medium (chart rows, compact labels)
    static let designMonoDataCompact = Font.custom("JetBrainsMono-Medium", fixedSize: 11)

    // MARK: Space Grotesk additional

    /// Body caption — 12pt Regular
    static let designBodyCaption = Font.custom("SpaceGrotesk-Regular", fixedSize: 12)
}
