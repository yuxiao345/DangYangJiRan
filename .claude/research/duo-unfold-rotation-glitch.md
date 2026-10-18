# Feedback Assistant report — iPhone Duo unfold after outer-display rotation leaves stale/rotated scene geometry

**Area:** iOS > SwiftUI  (or Developer Tools > Xcode > Simulator)
**Reproducible:** Always, following the steps below (reproduced 2x by reporter)

---

## Title

iPhone Duo: system vertical tab bar and app safe-area chrome are laid out rotated 180° after rotating on the outer display, then unfolding

## Description

On the iPhone Duo simulator (iOS 27.1, Xcode 27.1), if the app is rotated through several outer-display orientations and then the device is unfolded to the inner display, the system's vertical tab bar is laid out **rotated 180°** (it appears on the screen's leading edge, upper half, instead of the trailing edge, lower half). At the same time, the app receives incorrect safe-area geometry:

- Views placed with `.safeAreaInset(edge: .bottom)` render near the **top** of the screen (our floating action button appears top-trailing, under the status bar, instead of bottom-trailing).
- App content underlaps the tab bar: the large navigation title is clipped by the tab bar on the leading edge.

The content body itself renders upright and at the correct landscape size (two-column layout is applied correctly), so this is not an orientation/layout decision inside the app — the app is following the geometry it is given.

Relaunching the app, or folding and unfolding again, immediately restores the correct layout. Apple's Settings app renders normally in the same state (though it is not a tab-based app).

## Steps to Reproduce

1. Boot the iPhone Duo simulator (iOS 27.1, Xcode 27.1).
2. Launch a tab-based SwiftUI app (`TabView` with 5 tabs, each tab hosting a `NavigationStack`; floating action button added via `.safeAreaInset(edge: .bottom)`).
3. On the **outer** display, rotate the device through all orientations: 90° → 180° → 270° → 360°.
4. Unfold the device to the inner display.
5. Observe the tab bar placement and the floating action button placement.

## Expected Results

- Vertical tab bar on the trailing (right) edge of the inner display, lower half — as in the normal inner-display layout.
- Content laid out inside the safe area; navigation title not clipped.
- `.safeAreaInset(edge: .bottom)` content (floating button) at the bottom-trailing corner.

## Actual Results

- System vertical tab bar is drawn on the **leading (left) edge**, upper half — i.e. rotated 180° relative to its normal position.
- App content starts at the screen edge and is overlaid/clipped by the tab bar (large title cut off).
- The floating action button (bottom safe-area inset) is rendered near the **top-trailing** corner, overlapping the status bar.
- Status bar itself is unchanged (top-right), and all content text is upright.

## Workaround

Relaunch the app, or fold and unfold the device again. Both restore the correct layout immediately.

## Environment

- Xcode 27.1 (Build 27A9275)
- Simulator runtime: iOS 27.1 (24A94425)
- Device: iPhone Duo simulator, UDID 4458B115-BF74-4D77-9947-0A7D7DEB7E8C
- Our app: bundle id com.qianey.app, Debug build, version 1.0 (1)
- App layout code deliberately uses **size classes + measured container size**, never `UIDevice.current.orientation` or `interfaceOrientation`, per the foldable guidance (Tech Talk 111461 §2:46).

## Attachments

1. `glitch-now.png` — glitched state (inner display). Tab bar on leading edge; FAB top-trailing under status bar; title clipped.
2. `glitch-relaunched.png` — the same session after relaunching the app (no other change). Everything correct: tab bar trailing edge, FAB bottom-trailing.
3. `bar-before.png` — earlier normal state for comparison.
4. `user-repro.png` — the reporter's screenshot of the same glitch.

## Additional notes

- The status bar stays top-right in both states, so the screen orientation itself did not change; only the tab bar/safe-area layout is rotated.
- In the glitch, the tab bar's position matches a 180° rotation of its normal position about the screen center.
- This looks like stale scene/interface-orientation state surviving the outer-display → inner-display transition; the system's own tab bar is affected, so the app cannot correct it.
