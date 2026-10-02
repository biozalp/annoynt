<p align="center"><img src="docs/icon.png" width="128" alt="Annoynt icon"></p>

<h1 align="center">Annoynt</h1>

<p align="center">Makes the macOS Spaces switch animation faster. It keeps the native slide and makes it quicker, or turns it instant.</p>

<p align="center"><a href="https://github.com/biozalp/annoynt/releases/latest/download/Annoynt.dmg"><b>Download Annoynt.dmg</b></a> · macOS 14+ · Apple Silicon &amp; Intel · free and open source</p>

---

Switching desktops on macOS (Control + ←/→, or a three/four-finger swipe) plays a slide that takes about 0.8 s, and macOS has no setting to shorten it. Annoynt is a small menu-bar app that lets you pick the speed, from about 480 ms down to instant. The animation is still macOS's own slide, so it looks native, just quicker.

## Install

1. Download **[Annoynt.dmg](https://github.com/biozalp/annoynt/releases/latest/download/Annoynt.dmg)** from the [latest release](https://github.com/biozalp/annoynt/releases/latest).
2. Open it and drag **Annoynt** into **Applications**.
3. Launch it. When asked, allow it under **System Settings › Privacy & Security › Accessibility**. It needs this to catch your Spaces shortcuts and swipes. It starts working as soon as access is granted.

The app is signed with Developer ID and notarized by Apple, so it opens without Gatekeeper warnings. It doesn't modify system files or require turning off SIP.

## Use

Click the icon in the menu bar:

- **On/off switch**: off hands everything back to the normal macOS animation.
- **Speed**: the presets Instant, Fast (≈50 ms), Smooth (≈120 ms) and Relaxed (≈300 ms), or the slider for anything up to ≈480 ms.
- **Speed up trackpad swipes**: also applies to three/four-finger swipes between Spaces.
- **Handle "Switch to Desktop N" shortcuts**: jumps to a numbered desktop instantly.
- **Reverse direction**: if switches go the wrong way on your macOS version.
- **Launch at login**.

Annoynt follows the shortcuts set in **System Settings › Keyboard › Keyboard Shortcuts › Mission Control**, and only those that are enabled there.

## How it works

Annoynt intercepts your Spaces shortcuts and swipes, and replays each one as a synthetic trackpad "flick" with a chosen release velocity. The Dock responds as it would to a fast real swipe: it plays its own slide, shortened to match. The velocity for each duration was measured by screen-recording switches at 120 fps (see [`tools/anim-probe`](tools/anim-probe) and [`Core/SpeedCurve.swift`](Sources/Annoynt/Core/SpeedCurve.swift)).

This relies on private macOS internals (undocumented CGEvent fields and SkyLight functions), so a macOS update can break it. If it stops working after an update, please [open an issue](https://github.com/biozalp/annoynt/issues).

## Known limits

- Durations are approximate. They were calibrated on macOS 27 on a built-in 120 Hz display.
- With the trackpad you get a fixed-speed switch as soon as the direction is clear. The slide doesn't follow your fingers.
- Jumping several desktops at once (Desktop N), or pressing again while a slide is running, is instant.
- Inside Mission Control, and for a desktop on another display, Annoynt hands control back to macOS.
- Developed and tested on macOS 27. macOS 14–26 use an older gesture recipe that hasn't been tested.

## Build from source

Pure Swift, built with Swift Package Manager. No Xcode project.

```sh
scripts/build-app.sh            # → build/Annoynt.app
scripts/build-app.sh --install  # → /Applications, relaunched
```

The build is signed with your Apple Development certificate if you have one, otherwise ad-hoc (`SIGN_IDENTITY=-`). With an ad-hoc signature, macOS revokes the Accessibility permission after every rebuild. `scripts/release.sh` produces the notarized DMG; it needs a Developer ID certificate.

Project notes: [`docs/business-logic/space-switching.md`](docs/business-logic/space-switching.md) describes the behaviour in detail, and [`docs/JOURNAL.md`](docs/JOURNAL.md) records how it got here.

## Credits

The synthetic dock-swipe technique comes from [InstantSpaceSwitcher](https://github.com/jurplel/InstantSpaceSwitcher). The macOS 27 gesture payload was reverse-engineered by [joshuarli/iss](https://github.com/joshuarli/iss) and documented by [Space Rabbit](https://github.com/Tahul/space-rabbit). Annoynt's code was written independently.

## License

[MIT](LICENSE)
