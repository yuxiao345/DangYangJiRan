import SwiftUI

// MARK: - Design System Fonts
//
// Space Grotesk: headings, UI, body
// JetBrains Mono: data, labels, monospace values
//
// iOS: uses relativeTo for Dynamic Type scaling
// macOS: uses fixedSize (Dynamic Type not supported on macOS)
//
// Size reference — macOS is ~3-4pt smaller than iOS to match platform conventions:
//   macOS body = 13pt (NSFont.systemFontSize), iOS body = 17pt

extension Font {

    // MARK: Space Grotesk (headings & UI)

    /// Display large — 48pt Bold (iOS) / 32pt Bold (Mac)
    static let designDisplay: Font = {
        #if os(macOS)
        Font.custom("SpaceGrotesk-Bold", fixedSize: 32)
        #else
        Font.custom("SpaceGrotesk-Bold", size: 48, relativeTo: .largeTitle)
        #endif
    }()

    /// Display large mobile — 32pt Bold (iOS) / 24pt Bold (Mac)
    static let designDisplayMobile: Font = {
        #if os(macOS)
        Font.custom("SpaceGrotesk-Bold", fixedSize: 24)
        #else
        Font.custom("SpaceGrotesk-Bold", size: 32, relativeTo: .title)
        #endif
    }()

    /// Headline large — 40pt SemiBold (iOS) / 22pt SemiBold (Mac)
    static let designHeadlineLarge: Font = {
        #if os(macOS)
        Font.custom("SpaceGrotesk-SemiBold", fixedSize: 22)
        #else
        Font.custom("SpaceGrotesk-SemiBold", size: 40, relativeTo: .largeTitle)
        #endif
    }()

    /// Headline medium — 24pt SemiBold (iOS) / 16pt SemiBold (Mac)
    static let designHeadlineMedium: Font = {
        #if os(macOS)
        Font.custom("SpaceGrotesk-SemiBold", fixedSize: 16)
        #else
        Font.custom("SpaceGrotesk-SemiBold", size: 24, relativeTo: .title2)
        #endif
    }()

    /// Body large — 18pt Regular (iOS) / 15pt Regular (Mac)
    static let designBodyLarge: Font = {
        #if os(macOS)
        Font.custom("SpaceGrotesk-Regular", fixedSize: 15)
        #else
        Font.custom("SpaceGrotesk-Regular", size: 18, relativeTo: .body)
        #endif
    }()

    /// Body medium — 16pt Regular (iOS) / 13pt Regular (Mac, macOS HIG standard body)
    static let designBodyMedium: Font = {
        #if os(macOS)
        Font.custom("SpaceGrotesk-Regular", fixedSize: 13)
        #else
        Font.custom("SpaceGrotesk-Regular", size: 16, relativeTo: .body)
        #endif
    }()

    /// Body small — 14pt Regular (iOS) / 12pt Regular (Mac)
    static let designBodySmall: Font = {
        #if os(macOS)
        Font.custom("SpaceGrotesk-Regular", fixedSize: 12)
        #else
        Font.custom("SpaceGrotesk-Regular", size: 14, relativeTo: .caption)
        #endif
    }()

    // MARK: JetBrains Mono (data & labels)

    /// Label — 12pt Bold (iOS) / 11pt Bold (Mac)
    static let designLabel: Font = {
        #if os(macOS)
        Font.custom("JetBrainsMono-Bold", fixedSize: 11)
        #else
        Font.custom("JetBrainsMono-Bold", size: 12, relativeTo: .caption2)
        #endif
    }()

    /// Label small — 10pt Bold (both platforms)
    static let designLabelSmall = Font.custom("JetBrainsMono-Bold", fixedSize: 10)

    /// Mono data — 14pt Medium (iOS) / 13pt Medium (Mac)
    static let designMonoData: Font = {
        #if os(macOS)
        Font.custom("JetBrainsMono-Medium", fixedSize: 13)
        #else
        Font.custom("JetBrainsMono-Medium", size: 14, relativeTo: .caption)
        #endif
    }()

    /// Mono data small — 12pt Medium (iOS) / 11pt Medium (Mac)
    static let designMonoDataSmall: Font = {
        #if os(macOS)
        Font.custom("JetBrainsMono-Medium", fixedSize: 11)
        #else
        Font.custom("JetBrainsMono-Medium", size: 12, relativeTo: .caption2)
        #endif
    }()

    /// Mono data compact — 11pt Medium (iOS) / 10pt Medium (Mac)
    static let designMonoDataCompact: Font = {
        #if os(macOS)
        Font.custom("JetBrainsMono-Medium", fixedSize: 10)
        #else
        Font.custom("JetBrainsMono-Medium", fixedSize: 11)
        #endif
    }()

    // MARK: Space Grotesk additional

    /// Body caption — 12pt Regular (iOS) / 11pt Regular (Mac)
    static let designBodyCaption: Font = {
        #if os(macOS)
        Font.custom("SpaceGrotesk-Regular", fixedSize: 11)
        #else
        Font.custom("SpaceGrotesk-Regular", fixedSize: 12)
        #endif
    }()

    /// Micro label — 9pt Regular SpaceGrotesk (macOS only, fixedSize for micro-labels that shouldn't scale)
    static let designMicroLabel: Font = {
        #if os(macOS)
        Font.custom("SpaceGrotesk-Regular", fixedSize: 9)
        #else
        Font.custom("SpaceGrotesk-Regular", fixedSize: 9)
        #endif
    }()
}
