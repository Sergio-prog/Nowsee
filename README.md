<div align="center">

# Nowsee

**A live visualizer for whatever your Mac is playing — in the menu bar, and in a window.**

[![macOS 15+](https://img.shields.io/badge/macOS-15%2B-black?logo=apple)](https://github.com/Sergio-prog/Nowsee/releases)
[![Swift 6](https://img.shields.io/badge/Swift-6-orange?logo=swift&logoColor=white)](https://swift.org)
[![MIT](https://img.shields.io/badge/license-MIT-blue)](LICENSE)

[Install](#install) · [Visualizations](#visualizations) · [Settings](#settings) ·
[Roadmap](ROADMAP.md) · [Engineering notes](docs/ENGINEERING.md)

</div>

---

Nowsee taps the system audio output and draws it in real time. It works with anything that makes
sound — Spotify, YouTube, a video call, a game — because it reads the output mix rather than
integrating with any particular app.

It lives in the menu bar. There is no dock icon, no window on launch, and no account.

Inspired by [songsee](https://songsee.sh/), which renders spectrograms from audio *files*.
Nowsee does it continuously, from whatever is playing right now.

## Install

### Homebrew

```sh
brew tap Sergio-prog/tap
brew install --cask nowsee
```

### Download

Grab the latest `Nowsee.zip` from [Releases](https://github.com/Sergio-prog/Nowsee/releases),
unzip it, and drag `Nowsee.app` to `/Applications`.

### Build from source

Needs Swift 6 with Command Line Tools. There is no Xcode project — SPM plus a Makefile assembles
the bundle, so the whole thing stays as text files.

```sh
git clone https://github.com/Sergio-prog/Nowsee.git
cd Nowsee
make cert      # once: a self-signed identity, so macOS remembers the audio permission
make install   # build, install to /Applications, launch
```

### First launch

Nowsee is signed but **not notarized** — that needs a paid Apple Developer account. macOS will say
it cannot verify the developer. Right-click the app → **Open** → **Open**, once. After that it
launches normally.

Then macOS asks for permission to record system audio. Nowsee cannot draw anything without it.
Nothing is recorded to disk, nothing leaves the machine, and the microphone is never touched — the
audio is read, turned into numbers, and drawn.

## Visualizations

Six modes in two families.

**Scrolling** — history moves right to left.

| | |
|---|---|
| **Spectrogram** | Frequency map with auto-contrast. Bass at the bottom, treble at the top, brightness is energy. |
| **Waveform** | Amplitude envelope around a centre line. |
| **Ocean** | A filled swell rising from the bottom edge with a lit crest. |

**Fixed** — frequency runs along X, so bass stays left and treble stays right. Nothing travels; the
shape morphs in place, the way an FL Studio visualizer does.

| | |
|---|---|
| **Bars** | Classic equalizer rising from the bottom, with falling peak caps. |
| **Stereo** | Mirrored spectrum — left channel above the axis, right channel below. |
| **Morph** | One line per channel, mirrored about the axis. |

Ten palettes — Magma, Inferno, Viridis, Classic, Mono, Ice, Sunset, Neon, Ember — plus a custom
three-stop gradient you pick yourself.

## The menu bar strip

The strip always draws a baseline, so Nowsee is visibly present rather than an empty transparent
gap. Where that line sits depends on the mode — centred for Waveform, Stereo and Morph, along the
bottom for the others — so it reads as the axis the visualization grows from.

When nothing is playing it can animate: a slow breath, a travelling wave, or a drifting highlight.
That costs about 1.5% CPU, which is why `Off` is a first-class option rather than a disabled state.

Launching does not open the visualizer window. It is there when you want it, from **Show
Visualizer** (⌘S) or by launching the app again.

## Settings

**Settings…** (⌘,) opens a window with a live preview of both surfaces. Everything persists.

When nothing is playing, the previews fall back to a synthetic signal — a drifting four-band contour
shaped like music, generated numerically and never sent to an output device. Without it the previews
are a flat line whenever the room is quiet, which is exactly when someone is most likely to be
adjusting palettes. Real audio takes over the moment it arrives, and the mock feeds only the
previews: the menu bar keeps showing its true idle state, so it never claims to hear something it
cannot.

| Setting | Options | Default |
|---|---|---|
| Visualization | Spectrogram, Waveform, Ocean, Bars, Stereo, Morph | Spectrogram |
| Sensitivity | 1–30× (every mode except Spectrogram) | 4× |
| Smoothing | 0–100% (Bars, Stereo, Morph, Ocean) | 55% |
| Animate preview when quiet | on / off | on |
| Standby animation | Off, Breathe, Wave, Sweep | Breathe |
| Standby intensity | 0–100% | 60% |
| Baseline matches system | on / off | on |
| Baseline colour | any colour, when not matching the system | white |
| Baseline opacity | 0–100% | 100% |
| Bars | 8–96 (Bars only) | 56 |
| Bar spacing | 0–60% of each slot (Bars only) | 16% |
| Palette | ten built-ins plus Custom | Magma |
| Custom colours | low / mid / high stops | blue → green → white |
| Frame rate | 15 / 30 / 60, capped to the display refresh rate | 30 |
| Menu bar frame rate | 15 / 30 / 60, independent of the window | 30 |
| Float above all windows | on / off | off |
| Window background opacity | 0–100% | 100% |
| Menu bar width | 40–220 pt | 72 pt |
| Menu bar edge fade | 0–30 px | 6 px |
| Menu bar opacity | 20–100% | 100% |
| Pause capture | releases the tap entirely | running |

## Performance

Measured on Apple silicon with a synthetic signal, release build. Idle is ~0.2% CPU and 30 MB
resident; the app stops rendering entirely once the visible history has scrolled to silence.

| Playing audio, window at 60 fps | strip 15 fps | strip 30 fps | strip 60 fps |
|---|---|---|---|
| Window closed | 4.5% | 7.3% | 11.5% |
| Window open | 9.6% | 13.7% | ~18% |

The counterintuitive part: a 72×22 pt menu bar strip costs more than the 900×320 Metal window,
because the cost is per *redraw* and almost independent of size. That is why the strip has its own
frame rate. If Nowsee feels expensive, lower the menu bar rate before the window rate.

The **settings window is the expensive state** — two live previews redrawing puts it around 22%.
It is also, inconveniently, where people go to compare frame rates. Close it before measuring.

Full details, and the bug where 30 fps was genuinely twice as laggy rather than merely choppier,
are in the [engineering notes](docs/ENGINEERING.md).

## Privacy

Nowsee reads the system audio output mix so it can draw it. That is the entire data flow:

- Audio is turned into FFT magnitudes in memory and drawn. It is never written to disk.
- Nothing is sent anywhere. The app makes no network requests of any kind.
- The microphone is never accessed — that is a separate permission Nowsee does not request.
- Settings live in `UserDefaults`. There is no account, no telemetry, no analytics.

## Requirements

- **macOS 15+.** Core Audio process taps need 14.4, but the package targets 15.0 and has only been
  tested there. See the [roadmap](ROADMAP.md) for lowering it.
- Apple silicon or Intel.
- To build: Swift 6 with Command Line Tools. No Xcode project.

## Development

```sh
make check           # DSP assertions — no audio device, no sound
make app             # build + sign dist/Nowsee.app
make run-app         # restart the dist/ build
make install         # install to /Applications and launch
make icon            # regenerate the icon from scripts/make-icon.swift
make release         # zip the app and print the Homebrew cask sha256
make probe-app       # the P0 capture-verification app
make run-probe-app   # run it for 15s -> ~/Library/Logs/nowsee-probe.log
make reset-tcc       # revoke the audio permission to re-test the prompt
```

`make check` runs `nowsee-check`, which feeds known signals through the analyzers and asserts on the
results — stereo separation, band mapping, smoothing kernels, frame-rate independence. It needs no
audio device and makes no sound. There is no test target because neither XCTest nor swift-testing
ships with Command Line Tools.

Environment flags:

| Flag | Effect |
|---|---|
| `NOWSEE_DIAGNOSTICS=1` | Appends render stats to `~/Library/Logs/nowsee.log` every 2 s |
| `NOWSEE_SELFTEST=signal` | Feeds a synthetic stereo tone into the ring buffers — drives every mode **without playing anything** |
| `NOWSEE_SELFTEST=settings` | Opens the settings window after 2 s and logs its geometry |
| `NOWSEE_SELFTEST=reconfigure` | Forces tap rebuilds on a timer, to exercise device-change handling |
| `NOWSEE_WINDOW=1600x900` | Overrides the window's initial size, for measuring render cost against area |

### Layout

```
Sources/
  NowseeCore/               capture + DSP, no UI
    AudioObjectUtils        Core Audio property helpers
    SystemAudioTap          process tap -> aggregate device -> stereo + mono
    AudioRingBuffer         lock-free SPSC, shared by every analyzer
    STFT                    vDSP FFT, magnitude -> dB
    LogFrequencyMap         linear bins -> log-spaced rows
    AutoContrast            decaying-histogram percentile clamp
    SpectrumAnalyzer        ring -> normalized spectrogram columns
    WaveformAnalyzer        ring -> min/max envelope, no FFT
    EnvelopeSmoother        width-relative gaussian for the Ocean surface
    StereoSpectrumAnalyzer  stereo rings -> log bands, smoothed, peak-held
  Nowsee/                   the app
    AudioEngine             owns the rings, drives the active analyzer
    PreviewSignal           display-link driven mock for the settings previews
    SpectrogramRenderer     Metal, one pipeline per visualization
    StripVisualizationView  Core Graphics strip for menu bar and previews
    SettingsView            SwiftUI settings with live preview
  nowsee-probe/             P0 capture verification CLI
  nowsee-check/             DSP assertions, no audio device needed
scripts/
  make-icon.swift           draws the iconset; make icon runs iconutil over it
  make-cert.sh              self-signed identity so TCC remembers the grant
homebrew/nowsee.rb          cask, published to Sergio-prog/homebrew-tap
web/                        the landing page at nowsee.serhiifotex.dev
```

`SystemAudioTap` splits every callback into left and right channels first and derives the mono
mixdown from those, so the scrolling modes and the stereo modes are fed from one pass. The analyzers
read from rings owned by `AudioEngine`, so switching visualization costs nothing at the capture
layer — only the active analyzer runs.

## Stack

Swift only. Everything the app needs is an Apple framework with no cross-language equivalent.

| Layer | Framework |
|---|---|
| System audio capture | Core Audio process taps |
| FFT / DSP | Accelerate (vDSP) |
| Rendering | Metal |
| Shell, menu bar | AppKit |
| Settings | SwiftUI |

## Contributing

Issues and pull requests are welcome — see [CONTRIBUTING.md](CONTRIBUTING.md). If you are touching
the audio path, read [the engineering notes](docs/ENGINEERING.md) first; Core Audio taps fail
silently in several ways that look like your bug and are not.

## License

MIT — see [LICENSE](LICENSE).
