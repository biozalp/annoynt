# Space switching

## What triggers a switch

- **Keyboard:** Annoynt acts only on shortcuts that are **enabled in System Settings → Keyboard Shortcuts → Mission Control**: "Move left a space" (id 79), "Move right a space" (id 81) and "Switch to Desktop 1–10" (ids 118–127).
  - An entry missing from preferences falls back to macOS's default (Control + ←/→). A disabled or cleared entry is never intercepted.
  - A Desktop N binding with no modifier is never intercepted, so a bare number key can't be hijacked.
  - Shortcuts are re-read whenever System Settings loses focus and whenever the menu opens.
- **Trackpad:** horizontal three/four-finger swipes between Spaces ("Speed up trackpad swipes", on by default).
  - The physical swipe is swallowed. As soon as it has moved 5% of the way, the switch fires in that direction at the chosen speed.
  - If the fingers reverse by 20% without lifting, the switch is undone, just as macOS lets you take back a swipe.
  - A very quick flick that ends before moving 5% uses its release direction.
  - While Mission Control is open, swipes are left to macOS, because there they scroll the Spaces bar.
- When the master **Enabled** switch is off, everything passes through and macOS animates as usual. "Desktop N" handling and trackpad handling can each be turned off separately.

## How a switch looks

- Annoynt doesn't draw any animation itself. Each step is posted as a synthetic swipe with near-zero finger travel and a chosen **release velocity**. The Dock reacts as it would to a fast trackpad flick: it plays its **own** slide animation, shortened according to the velocity.
  - Measured on macOS 27.0.1: velocities up to ~45 give the full native slide (~750–900 ms). From 50 the slide shortens steeply (50 → 480 ms, 54 → 88 ms, 65 → 36 ms, 80 → 13 ms). From ~100 it's instant.
  - The duration the user picks is converted to a velocity with this table (`Core/SpeedCurve.swift`), interpolating in log-duration. That's why the durations shown in the menu are marked "≈".
  - Anything below the shortest measured slide (13 ms) is posted as an instant switch (velocity 9999).
  - v0.1 drove the slide frame by frame instead. That flickered, because the Dock's progress mapping doesn't match the gesture's: it jumped ~20% on the first frame and snapped the last ~20%. It was replaced by this approach.
- The switch acts on the display **under the mouse cursor**, the same as macOS.
- **Multi-space jumps (Desktop N):** one swipe per step, all instant. Animated swipes in a row would each play a slide.
- **Pressing again while a slide is running:** the new switch is instant. A swipe that arrives mid-animation makes the Dock finish with its slow native settle (~600 ms creep), which looks worse than snapping.
- **At the first/last space:** nothing happens and the input is still swallowed. Natively this would be a slow rubber-band bounce.
- **Rapid presses:** presses made before the window server reports the new space are counted, so they step correctly and stop at the edge.
- **Key auto-repeat** is swallowed and ignored, matching native behaviour.
- **Desktop N on another display,** or a layout that can't be read: the input is passed through to macOS.

## Direction

- **Posting:** on macOS 27 the Dock reads a synthetic swipe's direction through the "Natural scrolling" preference (`com.apple.swipescrolldirection`, default on = inverted). Annoynt applies that rule automatically. The **Reverse direction** setting flips the result as an escape hatch. The Dock only picks up a change to Natural scrolling when it restarts.
- **Reading physical swipes:** positive progress/velocity always means "towards the space on the right". The window server already accounts for Natural scrolling.

## Defaults

Enabled on, duration ≈120 ms, trackpad on, Desktop N on, Reverse off. Duration is capped at ≈480 ms, the longest slide the curve can produce.

## Permissions

Accessibility access is required. It covers the keyboard and trackpad event taps and posting gestures. Without it, the app shows a banner and polls every 1.5 s until access is granted, then starts with no relaunch needed.
