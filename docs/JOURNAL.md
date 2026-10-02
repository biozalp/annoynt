# Journal

## 2026-10-02

**Session 3: open-sourced and released v0.1.0.**

- **Published at https://github.com/biozalp/annoynt** as a public repo under the MIT license (copyright "Tudu", matching the app's Info.plist).
  - Distribution is DMG-only from GitHub Releases. The owner chose no Sparkle auto-update, so the codebase stays pure Swift.
  - The README's download button uses `releases/latest/download/Annoynt.dmg`, so it always serves the newest release.
- **Release pipeline**, adapted from the macos-sparkle-release skill for SwiftPM, one repo and no appcast:
  - `scripts/release.sh`: pre-flight → universal (arm64 + x86_64) build signed with Developer ID + hardened runtime + timestamp → notarize/staple the app → styled DMG via `create-dmg` → notarize/staple the DMG → `gh release create vX.Y.Z --target <commit>`.
  - It refuses to run with uncommitted or unpushed changes, or when the tag already exists (`ALLOW_RERELEASE=1` overrides).
  - Notarization reuses the team-wide `DockLockr` keychain profile.
- **New assets:** app icon (`scripts/make-icon.swift` → `Resources/AppIcon.icns`) and DMG background (`scripts/dmg-background.swift`), both generated in Swift.
- **First run failed safely at step 2.** The hardened-runtime check used `codesign | grep -q`, and under `pipefail` grep's early exit makes the pipeline fail even when the flag is present. Fixed by capturing the output first (commit `3bb9c48`), then reran.
- **Shipped v0.1.0 (build 1)** from commit `3bb9c48`. Notarization submissions `9912b984…` (app) and `3dbfeb13…` (DMG) were both Accepted.
- **Verified the downloaded asset** with `scripts/verify-release.sh`. All checks passed:
  - DMG and app stapled
  - Gatekeeper `accepted, Notarized Developer ID` (assessed with a quarantine flag, as a browser download would have)
  - version 0.1.0 (1), universal x86_64 + arm64, minos 14.0, icon bundled
  - `latest/download` resolves, and v0.1.0 is the latest release
  - DMG: https://github.com/biozalp/annoynt/releases/download/v0.1.0/Annoynt.dmg
- ⚠ **confirm:** the Developer ID build signs differently from the local Apple Development build. If you install the DMG over your dev copy, macOS will ask for Accessibility again: remove the old Annoynt entry and re-allow it.
- ⚠ **confirm:** the released build hasn't been launched from the DMG on a clean Mac, and the Intel slice has never been run.

**Session 2: native-looking speed-up, plus trackpad support** (from owner feedback: "touchpad should be affected, the visual is bad, I just want the sped up version of the animation not flickering").

- **Why v0.1 flickered:** I measured it by screen-recording switches at 120 fps from the agent shell, with the owner's OK to move the desktop. My frame-by-frame slide jumped ~20% on its first frame, stalled at ~80%, and then snapped. The Dock doesn't map gesture progress 1:1 onto the slide.
- **New approach:** each switch is now one synthetic "flick" with near-zero travel and a chosen release velocity. The Dock plays its **own** animation, just shorter, so it looks exactly like macOS with a faster finish. Measured curve: velocity ≤45 gives the native ~800 ms, 50 → 480 ms, 54 → 88 ms, 65 → 36 ms, 80 → 13 ms, ≥100 → instant. This is stored in `Sources/Annoynt/Core/SpeedCurve.swift`. The hand-driven timer and the easing setting are gone.
- **End-to-end check of the installed app** using synthetic Ctrl+→: target 300 ms → measured 309, 120 → 113, 50 → 48, Instant → no in-between frames. Frame sheets show a clean, monotonic slide.
- **Trackpad:** new `Input/SwipeInterceptor.swift` swallows horizontal 3/4-finger swipes and fires a switch at the chosen speed once the direction is clear. Reversing the fingers undoes it, and swipes inside Mission Control are left to macOS. I tested it with a swipe-shaped synthetic gesture: 1 → 2 → 1 at ~119 ms.
  - Bug found and fixed along the way: toggling our own envelope tap delivers a "disabled by user input" notification, which was cancelling every swipe.
- **Rapid presses:** a swipe that lands mid-animation made the Dock finish with its slow native creep (~885 ms total for two presses). Presses during a running slide are now instant: two quick presses → ~100 ms total.
- **Kept the harness** as `tools/anim-probe` for recalibrating after macOS updates.
- The test runs overwrote the duration setting, so it's back at the default ≈120 ms.
- ⚠ **confirm:** try a real three/four-finger swipe. The physical swipe direction rule (positive = right) comes from Space Rabbit's measurements; I could only simulate the gesture here.
- ⚠ **confirm:** the curve was measured on the built-in 120 Hz display only. On an external monitor the durations may differ. Tell me and I'll calibrate per display.

**Session 1:** **Built the first version of Annoynt**, a menu-bar app that sets the speed of the Spaces switch animation.

- **Approach:** macOS has no setting for this animation. The app intercepts the Spaces keyboard shortcuts with an event tap (`Sources/Annoynt/Input/KeyInterceptor.swift`) and plays the switch itself as a synthetic trackpad "dock swipe". It advances the swipe's progress on a wall-clock timer (`Core/SpaceSwitcher.swift`), so the slide takes exactly the chosen duration no matter the monitor's refresh rate. That also covers the original complaint about the animation slowing down at high refresh rates.
- **macOS 27 specifics:** the Dock now rejects bare synthetic gestures. Each event carries extra mirrored fields and a serialized IOHID payload (`Core/DockSwipe.swift`). The direction convention follows the Natural scrolling preference. Researched from InstantSpaceSwitcher and Space Rabbit (MPL-2.0). The code was written fresh and only the technique and field numbers were reused.
- **Pure Swift:** SwiftPM package with a SwiftUI `MenuBarExtra`. `scripts/build-app.sh` bundles it and signs with the Apple Development identity, so the Accessibility permission survives rebuilds.
- **Verified:** release build is clean, and the private space-layout query reads this Mac correctly (1 display, 5 desktops, 120 Hz).
- **Not yet verified:** an actual switch hasn't been run, because that moves the real desktop.
- ⚠ **confirm:** after granting Accessibility, press Control+→ / Control+← and check that the direction is correct. If it's reversed, tick "Reverse direction" and tell me, because that means the auto-detection is wrong for build 26A434.
- ⚠ **confirm:** the pre-27 code path (macOS 14–26) is untested.
- Docs: `README.md`, `docs/business-logic/space-switching.md`, `docs/ROADMAP.md`.
