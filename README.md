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

Live spectrogram of system audio, in a window and in the menu bar. Four palettes, selectable frame
rate, and a pause toggle that fully releases the audio tap. Verified capturing Spotify playback.

The menu bar strip has three states: the scrolling spectrogram while audio plays, a thin flat line
when nothing has been heard for 1.5 s, and a pause glyph when capture is off — so the app is always
visibly present rather than an empty transparent gap.

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
make app             # build + ad-hoc sign dist/Nowsee.app  (release by default)
make run-app         # restart it
make probe-app       # build the P0 capture-verification app
make run-probe-app   # launch it for 15s; writes ~/Library/Logs/nowsee-probe.log
make reset-tcc       # revoke the audio permission to re-test the prompt
```

`NOWSEE_DIAGNOSTICS=1` makes the app append render stats to `~/Library/Logs/nowsee.log`
every two seconds — Metal state, columns ingested, frames drawn, current device. `NOWSEE_SELFTEST=1`
pauses capture at 5 s and resumes at 9 s, which is how the pause path gets exercised without a
human clicking the menu. The probe's `--spectrogram` flag dumps an ASCII spectrogram to its log,
which is how the DSP chain was validated before any Metal existed.

## Settings

Everything lives in the menu bar menu and persists in `UserDefaults`:

| Setting | Options | Default |
|---|---|---|
| Palette | Magma, Inferno, Viridis, Classic | Magma |
| Frame rate | 15 / 30 / 60 / 120 fps | 30 |
| Pause capture | releases the tap entirely | running |

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

**Metal shaders compile at runtime with no Xcode.** `device.makeLibrary(source:)` works with only
Command Line Tools installed, so the shader lives in a Swift string and there is no `.metallib`
build step.

**Decouple the menu bar redraw from the hop rate.** Columns arrive ~94/sec; a 72×22 pt strip does not
need that. It coalesces to 20 fps and reuses one pixel buffer. The Metal view also pauses when its
window is closed or minimised.

**Idling properly is what makes it an always-on app.** Rendering an unchanging image at 30 fps and
running 94 FFTs/sec on digital silence costs ~8% CPU for nothing. Two fixes take idle to ~0.2%:
`SpectrumAnalyzer` skips the FFT entirely when a hop is all zeros, and the Metal view pauses once
the *whole visible history* has scrolled to silence — not merely when the current hop is quiet, or
it would freeze mid-scroll leaving a stale half-drawn image.

Measured: ~9% CPU with audio playing and the window open at 30 fps, ~0.2% idle, 30 MB resident.

## Layout

```
Sources/
  NowseeCore/          capture + DSP, no UI
    AudioObjectUtils   CoreAudio property helpers
    SystemAudioTap     process tap -> aggregate device -> mono mixdown
  nowsee-probe/        P0 capture verification CLI
```

`swiftLanguageMode(.v5)` is set deliberately: CoreAudio's C callbacks fight Swift 6 strict
concurrency, and the realtime audio thread has its own discipline that `Sendable` does not model.
Worth revisiting once the audio path stops changing.
