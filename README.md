# Nowsee

Live spectrogram of whatever your Mac is playing. Inspired by [songsee](https://songsee.sh/),
which renders spectrograms from audio *files* — Nowsee does it continuously, in real time.

## Status

| Phase | State |
|---|---|
| P0 — system audio capture | **working** |
| P1 — ring buffer + STFT | **working** |
| P2 — Metal spectrogram + window | **working** |
| P3 — menu bar strip | **working** |

Live visualization of system audio, in a window and in the menu bar. Five modes in two families:

*Scrolling* — history moves right to left.

- **Spectrogram** — frequency map with auto-contrast
- **Waveform** — amplitude envelope around a centre line
- **Ocean** — filled swell rising from the bottom edge with a lit crest

*Fixed* — frequency runs along X, so bass stays left and treble stays right. Nothing travels;
the shape morphs in place, the way an FL Studio visualizer does.

- **Bars** — classic equalizer rising from the bottom, with falling peak caps
- **Stereo** — mirrored spectrum, left channel above the axis, right channel below
- **Morph** — one line per channel, mirrored about the axis

Four palettes, selectable frame rate, adjustable sensitivity, and a pause toggle that fully
releases the audio tap. Verified capturing Spotify playback.

The menu bar strip always draws a baseline, so the app is visibly present rather than an empty
transparent gap. Where that line sits depends on the mode — centred for Waveform, Stereo and Morph,
along the bottom for Spectrogram and Ocean — so it reads as the axis the visualization grows from
rather than as a separate idle graphic. When capture is paused it becomes a pause glyph instead.

## Stack

Swift only. Everything the app needs is an Apple framework with no cross-language equivalent:

| Layer | Framework |
|---|---|
| System audio capture | CoreAudio process taps |
| FFT / DSP | Accelerate (vDSP) |
| Rendering | Metal |
| Shell, menu bar | AppKit |

## Requirements

- macOS 14.4+ (Core Audio process taps). Developed on macOS 26.5.
- Swift 6.3 with Command Line Tools. **No Xcode project** — SPM plus a Makefile that assembles
  the `.app` bundle by hand, so the whole project stays as text files.

## Build

```sh
make install         # build and install to /Applications, then launch
make app             # build + sign dist/Nowsee.app (release by default)
make check           # run the scope DSP checks (no audio needed)
make run-app         # restart the dist/ build
make probe-app       # build the P0 capture-verification app
make run-probe-app   # launch it for 15s; writes ~/Library/Logs/nowsee-probe.log
make reset-tcc       # revoke the audio permission to re-test the prompt
```

`NOWSEE_DIAGNOSTICS=1` makes the app append render stats to `~/Library/Logs/nowsee.log`
every two seconds — Metal state, columns ingested, frames drawn, scope peak, registered strips,
current device.

`NOWSEE_SELFTEST` takes a comma-separated list. `signal` feeds a synthetic stereo tone
(different frequency per channel) straight into the ring buffers, which drives every mode end to end
**without playing anything through the speakers**; the reported peak should match the synthetic
amplitude exactly. `settings` opens the settings window after 2 s and logs its geometry. `pause`
exercises the pause path without a human clicking the menu.

`make check` runs `nowsee-check`, which feeds known signals through `ScopeAnalyzer` and asserts on
the results — stereo separation, trigger stability, silence handling. There is no test target
because neither XCTest nor swift-testing ships with Command Line Tools, and this project has no
Xcode project on purpose; an executable full of assertions is the version that actually runs here.
The probe's `--spectrogram` flag dumps an ASCII spectrogram to its log, which is how the DSP chain
was validated before any Metal existed.

## Settings

`Settings…` (⌘,) from the menu bar opens a window with a live preview of both the main view and the
menu bar strip. Everything persists in `UserDefaults`.

When nothing is playing, the previews fall back to a synthetic signal — a drifting four-band contour
shaped like music, generated numerically and never sent to an output device. Without it the previews
are a flat line whenever the room is quiet, which is exactly when someone is most likely to be
adjusting palettes. Real audio takes over the moment it arrives, and the mock feeds only the preview
strips: the menu bar keeps showing its true idle state, so it never claims to hear something it
cannot. The generator runs only while the settings window is open.

| Setting | Options | Default |
|---|---|---|
| Visualization | Spectrogram, Waveform, Ocean, Bars, Stereo, Morph | Spectrogram |
| Sensitivity | 1–30× (every mode except Spectrogram) | 4× |
| Smoothing | 0–100% (Bars, Stereo, Morph, Ocean) | 55% |
| Bars | 8–96 (Bars only) | 56 |
| Bar spacing | 0–60% of each slot (Bars only) | 16% |
| Palette | Magma, Inferno, Viridis, Classic, Mono, Ice, Sunset, Neon, Ember, Custom | Magma |
| Custom colours | low / mid / high stops, any colour | blue → green → white |
| Frame rate | 15 / 30 / 60, capped to the display refresh rate | 30 |
| Float above all windows | on / off | off |
| Window background opacity | 0–100% | 100% |
| Menu bar width | 40–220 pt | 72 pt |
| Menu bar edge fade | 0–30 px | 6 px |
| Menu bar opacity | 20–100% | 100% |
| Pause capture | releases the tap entirely | running |

## Raycast and Spotlight

`make install` copies the bundle to `/Applications`, which is where Raycast and Spotlight look —
`dist/` is a build directory neither of them indexes and `make clean` deletes it. `LSUIElement`
apps still appear in both, so "Nowsee" finds it. Launching it while it is already running shows
the visualizer window rather than doing nothing, via `applicationShouldHandleReopen`.

For an actual restart, `raycast/restart-nowsee.sh` is a Raycast script command. Add its directory
under Raycast → Extensions → Script Commands → Add Directory, and "Restart Nowsee" becomes
searchable. It stops the app with SIGINT so CoreAudio tears the tap down cleanly, waits for it to
exit, and only then falls back to SIGKILL — killing a process that holds an audio tap without
letting it clean up leaks the aggregate device into `coreaudiod` and breaks system-wide playback.

`ditto` is used rather than `cp` so the code signature survives the copy, which keeps the audio
permission grant intact.

## Code signing

Ad-hoc signing gives the binary a new code hash on every rebuild, so TCC treats each build as a new
application and re-prompts for audio permission every single time. `make cert` creates a self-signed
code-signing identity called `Nowsee Dev`, which makes the designated requirement identity-based:

```
designated => identifier "sh.nowsee.Nowsee" and certificate leaf = H"ccf8cd8b…"
```

That is stable across rebuilds, so the permission is granted once and remembered. The Makefile picks
the identity up automatically by SHA-1 (not by name — two certificates sharing a name make `codesign`
fail with `ambiguous`) and falls back to ad-hoc if it is missing.

## P0 findings

Verified on macOS 26.5.1 with ad-hoc signing and no Apple Developer account.

**Capture must run from a real `.app` bundle.** This is the one that costs you a day if you don't
know it. A CLI binary launched from a shell cannot be a TCC principal, so the permission prompt
never appears and `AudioHardwareCreateProcessTap` *succeeds anyway* — it just delivers buffers of
pure silence forever. There is no error code. Wrap the same binary in a bundle with an `Info.plist`,
launch it with `open`, and it prompts and works.

**Ad-hoc signing (`codesign -s -`) is sufficient.** No developer certificate needed, and the grant
persists across rebuilds and relaunches.

**A real output device must be the aggregate's main sub-device.** A tap-only aggregate produces
silence with no error. `kAudioAggregateDeviceMainSubDeviceKey` gets the default output device's UID,
and that device also appears in `kAudioAggregateDeviceSubDeviceListKey`.

**No callbacks at all means the output device is idle, not that capture is broken.** With AirPods
and nothing playing, the IOProc simply doesn't fire. Distinguish the two failure modes:
zero callbacks = idle device; callbacks full of zeros = permission denied.

**The aggregate exposes exactly one 2ch input stream** (`buf0=2ch`, 4096 B = 512 stereo frames per
callback at 48 kHz, ~94 callbacks/sec). The tap is the only input stream — the output device's own
microphone does not appear alongside it.

**Diagnosing is much easier with per-buffer peaks** than with a mixed-down level meter, because it
separates "wrong buffer" from "no signal". `SystemAudioTap.onRawBuffers` exists for this.

**The output device changing out from under you is the dangerous case.** If the device the aggregate
was built on disappears — AirPods disconnecting is the everyday version — the aggregate is left
pointing at a device that no longer exists. `AudioDeviceStop` and `AudioHardwareDestroyAggregateDevice`
then block *forever* rather than returning an error, which hangs the process during teardown and
blocks all other playback on the machine (`afplay` fails with `AudioQueueStart failed (-66681)`).

Three defences, all now in place:

- `SystemAudioTap` listens on `kAudioHardwarePropertyDefaultOutputDevice` and rebuilds the whole
  tap/aggregate chain when the default output changes, so it never holds a stale device.
- It also listens on the current output device for `kAudioDevicePropertyDeviceHasChanged`,
  `NominalSampleRate`, `DeviceIsAlive` and `StreamFormat`. Bluetooth devices renegotiate their format
  on their own schedule — changing AirPods volume can do it — and the tap goes silent until the chain
  is rebuilt. Rebuilds are debounced 0.35 s so a burst of notifications costs one rebuild, and all
  chain mutation is serialized on `controlQueue`. `NOWSEE_SELFTEST=reconfigure` forces rebuilds on a
  timer to exercise the path without touching real hardware.
- Teardown is idempotent and ordered: stop the IOProc, destroy the IOProc, destroy the aggregate,
  destroy the tap.
- The probe arms a 3-second watchdog before teardown and `_exit`s if it overruns, so a blocked
  CoreAudio call can never wedge the machine again.

**Never SIGKILL a process holding a tap.** The private aggregate device leaks inside `coreaudiod`
and system-wide playback stays broken even after the process is gone — the device list still looks
completely normal, which makes it very confusing to diagnose. Recovery is `sudo killall coreaudiod`.
The probe handles SIGTERM as well as SIGINT so `pkill` shuts it down cleanly.

Still unverified: whether the tapped signal is attenuated by system output volume (which would dim
the spectrogram when you turn the music down). Test by holding playback steady and changing volume.

## P1–P3 findings

**Validate the DSP as ASCII before writing any Metal.** A 30 Hz→16 kHz logarithmic sweep must trace
a dead-straight diagonal across a log-frequency spectrogram; any curvature means the bin mapping is
wrong. That test caught nothing because the mapping was right, but it would have been miserable to
debug through a shader.

**Auto-contrast needs a noise floor.** The 5th/98th percentile clamp is what makes the image readable
without manual gain, but on a near-silent signal both percentiles land on the float32 FFT noise floor
(around -140 dB) and it happily stretches numerical noise to full brightness. `AutoContrast` clamps
its low anchor to -95 dB so silence stays black.

**Always measure a release build.** A debug build ran at 42% CPU; the same code in release runs at
~7%. Profiling the debug build was actively misleading — `sample` showed the time going into
`IndexingIterator.next` and `_swift_getGenericMetadata`, which is just unspecialised generic code,
not a real hot spot. The ring buffer's per-element loops were replaced with two bulk `update(from:)`
copies regardless, since wrap-around only ever needs two chunks.

**A `ScrollView` has no intrinsic height, which renders an `NSHostingController` window empty.**
`NSWindow(contentViewController:)` sizes itself from the SwiftUI fitting size; a root `ScrollView`
with only `.frame(width:)` reports a height of zero, so the window opens with a title bar and no
content and no error anywhere. The settings root sets an explicit width *and* height. Worth checking
`contentView.fittingSize` before assuming the view failed to build — and measuring after a layout
pass, since subview counts are still zero immediately after `makeKeyAndOrderFront`.

**Metal shaders compile at runtime with no Xcode.** `device.makeLibrary(source:)` works with only
Command Line Tools installed, so the shader lives in a Swift string and there is no `.metallib`
build step.

**Decouple the menu bar redraw from the hop rate.** Columns arrive ~94/sec; a 72×22 pt strip does not
need that. It coalesces to the chosen frame rate and reuses one pixel buffer. The Metal view also
pauses when its window is closed or minimised.

**A frame rate setting that cannot be reached is worse than no setting.** The picker offered 120 fps
on a 60 Hz panel, so 60 and 120 rendered identically and the control felt broken. Worse, the menu bar
strip was separately clamped to 20 fps, so for anyone watching only the strip the setting did nothing
at all. Options are now filtered by `NSScreen.maximumFramesPerSecond`, the caption names the display's
rate, and the strip follows the setting. Measured cost of un-clamping the strip: 7.5% CPU at 30 fps
versus 9.4% at 60.

**Idling properly is what makes it an always-on app.** Rendering an unchanging image at 30 fps and
running 94 FFTs/sec on digital silence costs ~8% CPU for nothing. Two fixes take idle to ~0.2%:
`SpectrumAnalyzer` skips the FFT entirely when a hop is all zeros, and the Metal view pauses once
the *whole visible history* has scrolled to silence — not merely when the current hop is quiet, or
it would freeze mid-scroll leaving a stale half-drawn image.

Measured: ~9% CPU with audio playing and the window open at 30 fps, ~0.2% idle, 30 MB resident.

**"Static" means frequency on X, not a cleverer time window.** The first attempt at Stereo and Morph
put time on X and tried to hold the picture still with a zero-crossing trigger. It still scrolled,
and it always would: a trigger only locks sub-period phase, while the window itself keeps advancing
with the audio clock every frame. A synthetic test hid this, because a pure tone *is* periodic
across the whole window and so appears to lock perfectly. Real music is not.

Putting frequency on X removes the motion by construction — band *k* is always at the same X, and
only its height changes. `make check` now asserts the property that was actually broken: advance the
ring by a fraction of a window and a steady tone must not change bands. It moves 0.

The lesson generalises: the test has to exercise the thing that's hard, not the thing that's easy to
generate. A pure sine was the one input that could not fail.

**Smooth the bands, not the pixels.** 128 discrete bands read as visible chunks. The obvious fix —
widening the gaussian in the fragment shader — costs a dynamic loop per pixel and has to be
duplicated in the Core Graphics strip. Doing it once in the analyzer, over 128 values, is far
cheaper and both renderers inherit it. The Smoothing control drives the kernel radius *and* the
attack/release rates together, because spatial stepping and temporal flicker are the same complaint.
`make check` measures the band-to-band step directly: 0.370 at 0%, 0.033 at 100%.

Blurring is energy-preserving, so a narrow peak gets shorter as smoothing rises. Broadband music
barely changes; an isolated pure tone visibly shrinks. Sensitivity compensates, and deliberately is
not applied automatically — coupling the two would make the gain slider fight the smoothing slider.

**Sharp edges had two causes, and band smoothing fixed neither.** `smoothstep` with `fwidth(y)`
antialiases only along Y, so wherever the level changes quickly between bands the boundary is nearly
vertical and gets no antialiasing at all. And sampling 128 bands through a linear filter produces a
piecewise-linear curve — visibly faceted, with a corner at every band centre. The fixes are 4× MSAA
(`MTKView.sampleCount`, plus `rasterSampleCount` on every pipeline) and Catmull-Rom interpolation
across four band samples, which is C1-continuous so the corners disappear. Together they cost about
one point of CPU: 9.4% → 10.5% at 60 fps.

**Never listen to a CoreAudio property you mutate yourself.** Adding a
`kAudioHardwarePropertyDevices` listener to detect device reconfiguration produced an infinite
rebuild loop — creating and destroying the private aggregate *is* a device-list change, so every
rebuild retriggered itself, 29 times in 18 seconds. The device-list listener is gone; default-output
and per-device liveness listeners cover the same failure without the feedback. A 0.5 s settle window
after each rebuild guards against any other self-triggering property.

**Rate-limiting off a coarser timer quantizes badly.** The drain timer ticks every 16 ms, so a
naive `elapsed >= 1/30` test skips the 32 ms tick and fires at 48 ms — a requested 30 fps silently
became 21. Subtracting half a tick from the interval makes it land on 32 ms. Scope emission now
tracks the configured frame rate 1:1.

**Verifying a visualizer without playing audio.** Screenshots are unavailable (the shell has no
Screen Recording permission) and playing test tones is obnoxious. `NOWSEE_SELFTEST=signal` writes a
synthetic stereo tone directly into the ring buffers, which exercises analyzer, Metal upload, and
menu bar strip end to end in silence. Because the tone is steady, `peak=` in the diagnostics log
should hold a constant value frame after frame — drift there means something upstream is moving
when it should not be.

## Layout

```
Sources/
  NowseeCore/            capture + DSP, no UI
    AudioObjectUtils     CoreAudio property helpers
    SystemAudioTap       process tap -> aggregate device -> mono mixdown
    AudioRingBuffer      lock-free SPSC, shared by both analyzers
    STFT                 vDSP FFT, magnitude -> dB
    LogFrequencyMap      linear bins -> log-spaced rows
    AutoContrast         decaying-histogram percentile clamp
    SpectrumAnalyzer     ring -> normalized spectrogram columns
    WaveformAnalyzer     ring -> min/max envelope, no FFT
    ScopeAnalyzer        stereo rings -> trigger-aligned fixed window
  Nowsee/                the app
    AudioEngine          owns the rings, drives the active analyzer
    SpectrogramRenderer  Metal, one pipeline per visualization
    StripVisualizationView  Core Graphics strip for menu bar and previews
    SettingsView         SwiftUI settings with live preview
  nowsee-probe/          P0 capture verification CLI
  nowsee-check/          DSP assertions, no audio device needed
```

`SystemAudioTap` splits every callback into left and right channels first and derives the mono
mixdown from those, so the scrolling modes and the stereo modes are fed from the same single pass.
The three analyzers read from rings owned by `AudioEngine`, so switching visualization costs nothing
at the capture layer — only the active analyzer runs.

`swiftLanguageMode(.v5)` is set deliberately: CoreAudio's C callbacks fight Swift 6 strict
concurrency, and the realtime audio thread has its own discipline that `Sendable` does not model.
Worth revisiting once the audio path stops changing.
