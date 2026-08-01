# Roadmap

Where Nowsee is and where it's going. Current release: **0.1.0**.

## Shipped

The four phases the project was planned around are all done.

| Phase | Scope | State |
|---|---|---|
| P0 | System audio capture via Core Audio process taps | done |
| P1 | Ring buffer, STFT, log-frequency mapping, auto-contrast | done |
| P2 | Metal renderer and the visualizer window | done |
| P3 | Menu bar strip | done |

On top of those:

- **Six visualizations** in two families — scrolling (Spectrogram, Waveform, Ocean) and
  fixed-frequency (Bars, Stereo, Morph).
- **Ten palettes** plus a custom three-stop gradient.
- **Settings** with a live preview of both surfaces, backed by a synthetic signal so the preview
  still moves in a quiet room.
- **Standby animations** — the baseline breathes, waves or sweeps when nothing is playing.
- **Configurable baseline** colour and opacity, or matching the system appearance.
- **Independent frame rates** for the window and the menu bar strip, because the strip turned out
  to cost more than the window.
- **Frame-rate-independent smoothing**, so 30 fps looks like 60 fps with fewer frames rather than
  twice the latency.
- **Tap resilience** — device changes, Bluetooth format renegotiation and clean teardown, all
  covered by [the engineering notes](docs/ENGINEERING.md).
- **Generated app icon**, drawn by `scripts/make-icon.swift`, so there are no binary assets in git.
- **Raycast restart command** that shuts the app down without leaking the aggregate device.

## Next

Roughly in the order they'd be worth doing.

### Distribution

- **Notarization.** The app is signed with a self-signed certificate today, so Gatekeeper shows
  the "unidentified developer" warning on first launch. Notarizing needs a paid Apple Developer
  account; until then the install instructions have to carry the right-click-Open step.
- **DMG** with a drag-to-Applications background, as an alternative to the zip.
- **Official Homebrew cask.** `homebrew/nowsee.rb` is ready for a personal tap now. The main
  `homebrew-cask` repository wants a project with some traction and a stable release history, so
  that comes later.

### Features

- **Launch at login**, via `SMAppService`. The obvious gap for a menu bar app.
- **Per-application capture.** `CATapDescription` can tap one process instead of the whole output
  mix, so Nowsee could visualize only Spotify and ignore notification sounds.
- **Floating panel.** A borderless, click-through, always-on-top window that sits over other
  content as an ambient visualizer rather than a normal window.
- **Notch mode.** Draw into the empty space either side of the camera housing on notched
  MacBooks — much more room than the menu bar strip, and otherwise wasted.
- **Freeze and export.** Pause the scroll, look at what just went past, save it as a PNG. This is
  the feature that would make Nowsee useful for something other than looking nice.
- **Presets.** Named bundles of visualization, palette and sensitivity, switchable from the menu.
- **Global hotkey** for show/hide and pause.

### More visualizations

Four candidates, all of which need a decision about the menu bar first — Lissajous and radial are
square, and a 72×22 pt strip cannot show them honestly. Either they become window-only with the
strip falling back to another mode, or the strip renders a degraded version.

- **Lissajous / goniometer** — left against right on an XY plot. The standard mastering tool for
  seeing stereo width and phase problems.
- **Radial spectrum** — the Bars mode wrapped into a circle.
- **Chromagram** — energy folded into twelve pitch classes, so it shows harmony rather than
  frequency.
- **Peak / VU meter** — deliberately boring, and the one that is actually readable at menu bar size.

Beyond those, [songsee](https://songsee.sh/) renders several analyses Nowsee does not: mel
spectrogram, MFCC, spectral flux, loudness, harmonic/percussive separation, tempogram and
self-similarity. They are all reachable from the existing STFT. Tempogram and self-similarity
need history that the current ring buffer does not keep.

### Engineering

- **Reconsider `swiftLanguageMode(.v5)`.** It is set because Core Audio's C callbacks fight Swift 6
  strict concurrency and the realtime thread has a discipline `Sendable` does not model. Worth
  revisiting now that the audio path has stopped changing.
- **A real test target.** `nowsee-check` is an executable full of assertions because neither XCTest
  nor swift-testing ships with Command Line Tools. If that changes, or if the project accepts an
  Xcode project, the assertions should become tests.
- **Lower the deployment target.** The code needs macOS 14.4 for process taps and 14.0 for
  `CADisplayLink` on `NSView`; the package declares 15.0. Dropping to 14.4 would widen the audience
  but needs testing on a 14.x machine.

## Non-goals

- **Capturing microphone input.** Nowsee visualizes what your Mac is playing. Microphone capture is
  a different permission, a different threat model and a different product.
- **Audio effects or routing.** The tap is read-only and stays that way.
- **iOS.** Process taps are macOS-only.
