# Annoynt — agent notes

macOS menu-bar app (pure Swift, SwiftPM, no Xcode project) that replaces the Spaces switch animation with one of user-chosen duration.

- Single app, **not a monorepo**. Build: `scripts/build-app.sh [--install]`. Swift language mode 5 (event-tap callbacks / dlsym'd C pointers).
- Bundle id `com.tudu.annoynt`, `LSUIElement` (no Dock icon). Signed with the Apple Development identity so the Accessibility (TCC) grant survives rebuilds — don't switch to ad-hoc signing.
- Layout: `Core/` = private API, gesture construction, switch engine, space queries; `Input/` = event tap, System Settings shortcut parsing, permissions; `App/` = SwiftUI MenuBarExtra + settings.
- Behavior rules live in `docs/business-logic/space-switching.md`; keep it in sync with code.
- Testing a switch moves the user's real desktop — ask before doing it from an agent shell.
- Switch speed = release velocity of a synthetic swipe; the Dock animates natively (see `Core/SpeedCurve.swift`). Don't reintroduce frame-by-frame progress driving — it flickers.
- Calibration / visual verification: `tools/anim-probe` (screen-records switches at 120 fps). Recalibrate `SpeedCurve` after macOS updates.
