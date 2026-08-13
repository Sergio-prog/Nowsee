# Engineering notes

Everything that was surprising, expensive or wrong on the way to making this work. Kept because
most of it is not written down anywhere else — Core Audio process taps are young, sparsely
documented, and fail silently in ways that cost days.

If you are building anything that captures macOS system audio, the P0 section is the part to read.

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

## Capturing system audio (P0)

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

Defences now in place:

- `SystemAudioTap` listens on `kAudioHardwarePropertyDefaultOutputDevice` and rebuilds the whole
  tap/aggregate chain when the default output changes, so it never holds a stale device.
- It also listens on the current output device for `NominalSampleRate`, `DeviceIsAlive`,
  `StreamFormat` and `StreamConfiguration`. Bluetooth devices renegotiate these on their own
  schedule, and the tap goes silent until the chain is rebuilt. The broad
  `kAudioDevicePropertyDeviceHasChanged` notification is deliberately not observed: volume changes
  can fire it even when the capture format is unchanged, causing an unnecessary interruption.
  Rebuilds are debounced 0.35 s, retried when a Bluetooth device is not settled yet, and serialized
  on `controlQueue`. `NOWSEE_SELFTEST=reconfigure` forces rebuilds on a timer.
- Teardown is idempotent and ordered: stop the IOProc, destroy the IOProc, destroy the aggregate,
  destroy the tap.
- The probe arms a 3-second watchdog before teardown and `_exit`s if it overruns, so a blocked
  CoreAudio call can never wedge the machine again.

**Never SIGKILL a process holding a tap.** The private aggregate device leaks inside `coreaudiod`
and system-wide playback stays broken even after the process is gone — the device list still looks
completely normal, which makes it very confusing to diagnose. Recovery is `sudo killall coreaudiod`.
The probe handles SIGTERM as well as SIGINT so `pkill` shuts it down cleanly.

**The tap is upstream of the output volume, so turning the music down does not dim the picture.**
This was the last open question from P0 and the answer is the one you want: a 0.5-amplitude tone
(-6.02 dBFS) reads back as exactly 0.5000 at 4%, 10%, 25%, 49%, 75% and 100% system volume. Not
approximately — bit-identical across a 25x range. The visualization tracks what the application is
playing, not how loud the speakers are set, which is the correct behaviour for a meter. It follows
that no volume compensation is needed anywhere in the chain, and that a `kAudioDevicePropertyVolumeScalar`
listener would be pointless.

**Volume tests can be run in total silence.** Muting is applied after the tap as well, so
"muted at 75%" and "muted at 10%" are both completely inaudible yet still produce a full-scale
capture. That turns a test that seems to require blasting a tone through the speakers into one that
makes no sound at all, and it is the only way to sweep the volume range without being obnoxious
about it. Set the volume, mute, play a known-amplitude WAV, read `per-buffer peak` from the probe.

One trap: change the volume *while* the probe is running and the ramp itself gets captured, which
showed up once as a 0.5824 peak — a 16% overshoot that looked like level-dependent processing and
was nothing of the kind. Set the volume before the run starts, and re-run any outlier before
believing it. Both retries at 100% returned exactly 0.5000.

Also seen, and consistent with the teardown hazard above: at volume 0 with the device otherwise
idle, `tap.stop()` blocked long enough for the probe's 3-second watchdog to fire and `_exit`. The
watchdog did its job — the machine's audio stayed healthy — but it is a reminder that the blocking
teardown is a live hazard, not a historical one.

## DSP, rendering and performance (P1–P3)

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

**Decouple the menu bar redraw from the hop rate.** Spectrogram columns arrive ~47/sec; a 72×22 pt
strip does not need that. It coalesces to the chosen frame rate and reuses one pixel buffer. The
Metal view also pauses when its window is closed or minimised.

**A frame rate setting that cannot be reached is worse than no setting.** The picker offered 120 fps
on a 60 Hz panel, so 60 and 120 rendered identically and the control felt broken. Worse, the menu bar
strip was separately clamped to 20 fps, so for anyone watching only the strip the setting did nothing
at all. Options are now filtered by `NSScreen.maximumFramesPerSecond`, the caption names the display's
rate, and the strip follows the setting. Measured cost of un-clamping the strip: 7.5% CPU at 30 fps
versus 9.4% at 60.

**Idling properly is what makes it an always-on app.** Rendering an unchanging image at 30 fps and
running FFTs on digital silence costs CPU for nothing. The analyzer skips FFT work on zeroed hops,
the strip ignores silent updates once it reaches idle, and the Metal view pauses after its visible
history has cleared.

The Metal renderer and its window are created lazily, updated only while visible, and released on
close. Settings follows the same lifecycle. This matters more for resident memory than tuning the
small ring buffers does.

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

**Two clocks at the same rate drop half the frames.** The preview generator ticked on a 30 Hz
`Timer` and each strip independently throttled its redraw to 30 Hz. Any jitter — and a main-thread
`Timer` always has some — lands the tick a hair under the throttle interval, so the frame is dropped
entirely and the next one arrives 66 ms later. Measured: 19.5 fps delivered against 30 requested,
varying frame to frame, which is exactly what "laggy" looks like. Two changes fix it: the generator
runs off a `CADisplayLink` so it is vsync-aligned rather than free-running, and the throttle allows
a 15% tolerance so a frame that is barely early still draws. Same measurement after: 30.0 fps, flat.

Phase now advances by elapsed time rather than per tick, so a dropped frame changes nothing about
the animation's speed, and the scrolling modes emit a time-derived number of columns per frame
instead of a fixed count.

**Count the frames that actually reached the screen.** Frame pacing is invisible to every check that
does not measure it — the strip *was* redrawing, just not when it meant to. `previewDraws` in the
diagnostics is a plain counter incremented in `draw`, and the delta between two log lines is the
real delivered rate. That number is what turned "feels laggy" into "19.5 versus 30".

**Smoothing has to be scaled to what it is smoothing.** The Ocean control was wired end to end and
still did nothing visible: the blur was a fixed ±8 taps over a 1024-column envelope, so 100%
smoothing moved the surface by under 1% of the window width. Sigma is now a fraction of the buffer
width (1.8%, radius derived from it) rather than a constant, which is the same perceived blur in the
900 px window, the 416 px preview and the 72 px menu bar strip even though each holds a different
span of time. The Core Graphics strip had the older bug of the two — it ignored the setting entirely
and hardcoded ±3 taps — which is why the settings preview was the place it looked most broken.

The kernel lives in `EnvelopeSmoother` in `NowseeCore` so `make check` can assert on it: radius 2 at
0% versus 17 at 100%, column-to-column step 0.0574 down to 0.0008, and a steady level passes through
unchanged. The fragment shader duplicates the formula because it has to, so the constants are named
in one place and copied deliberately.

**The app icon is generated, not committed.** `scripts/make-icon.swift` draws all ten iconset
sizes with Core Graphics and `make icon` runs it through `iconutil`, so the repository stays free of
binary assets and the icon is editable as code like everything else. It is four bars over a magma
gradient on a dark squircle, with the app's own baseline underneath them — chosen because bars are
the only motif that still reads at 16 pt.

**A layer-backed view in the menu bar costs 20x.** Adding `wantsLayer = true` to
`StripVisualizationView` — done for the rounded corners on the settings preview, which needs it —
silently made the menu bar strip enormously more expensive to animate, because the status item is
composited into the shared menu bar surface and a layer-backed subview there forces an offscreen
pass. Standby animation measured 42.5% CPU with the layer and 9.5% without it, for identical
drawing. `wantsLayer` is now set only by the `cornerRadius` setter, so the preview gets it and the
menu bar strip never does.

That left frame rate as the only remaining lever, because the drawing itself is trivial — a stroked
70-point path, or thirty 2 px rects. All animated styles now redraw at 12 fps, which is plenty for
motion this slow:

| Standby | menu bar redraws | idle CPU |
|---|---|---|
| Off | 2/s | 0.8% |
| Breathe | 11/s | 2.3% |
| Wave | 11/s | 2.4% |
| Sweep | 11/s | 2.0% |

Roughly 1.5 points of CPU buys the animation. That is a real always-on cost against the 0.2% idle
figure above, which is why the control exists and why `Off` is a first-class option rather than a
disabled state.

**An animation that only runs when idle cannot pause the renderer.** The Metal view pauses once the
whole visible history has scrolled to silence, which is exactly when standby wants to draw. The idle
timer now checks the standby setting before pausing, so `Off` keeps the old behaviour — the window
stops rendering entirely — and any animated style keeps it alive while the window is open. Since the
window no longer opens at launch, that cost is only paid by someone actively looking at it.

Worth knowing when measuring this: a window covered by another window stops rendering, so opening
the settings window on top of the visualizer freezes its frame counter. That looked like a standby
bug for one confusing run and is macOS behaving correctly.

**The menu bar strip costs more than the whole visualizer window.** Profiling for CPU found the
opposite of the expected answer: a 72x22 pt strip was 10.4% CPU at 60 fps while the 900x320 Metal
window was 4.5%. Only 32 of the strip's 195 profile samples were our own pixel code — the rest is
`CALayer::display_if_needed` -> `CABackingStoreUpdate_` -> a CoreGraphics blit, plus a colour-space
conversion. That overhead is per *redraw* and almost independent of size, so the only real lever is
how often the strip redraws, not how fast it draws.

Window size barely matters, which confirms it: 900x320 and 1600x900 cost 13.7% and 14.1%. That part
is GPU-bound, not CPU-bound.

The menu bar strip therefore has its own frame rate, separate from the window's. This was the
original baseline measured with a synthetic signal before lazy window resources and reduced DSP
cadence were added:

| | strip 15 | strip 30 | strip 60 |
|---|---|---|---|
| Window closed | 4.5% | 7.3% | 11.5% |
| Window open | 9.6% | 13.7% | ~18% |

**Settings used to be the expensive state, and it is the one people measure in.** A report of "30% at
60 fps" turned out to be 29.0% measured with the settings window open — which is exactly where
someone goes to compare frame rates, so it is the state they see. Two live preview strips redrawing
is most of it, one of them 416x96. Capping preview redraws at 24 fps took that to 21.9%, and the
steady state with settings closed was 12.5%. Settings now mounts only the selected page's preview,
and mounts no preview on General. The lesson is to always record which windows were open alongside
a CPU number; without that the number means nothing.

**A per-frame smoothing coefficient is a latency bug wearing a smoothing hat.** Attack and release
were applied once per emitted frame, so halving the frame rate doubled the response time in
milliseconds. At 55% smoothing the attack constant of 0.33/frame reaches 90% in 5.75 frames — 96 ms
at 60 fps but 192 ms at 30, and the release constant of 0.0905/frame takes 403 ms versus 807 ms.
That is why 30 fps felt laggy rather than merely choppy: it *was* laggy, by exactly a factor of two,
and no amount of frame-rate tuning would have fixed it.

The rates are now time constants — `1 - exp(-dt / tau)` against the real interval since the last
snapshot — with tau chosen to reproduce the old 60 fps feel exactly. `make check` asserts the
property directly by driving the same tone at both rates and comparing the level after 150 ms: 0.595
at 60 fps versus 0.581 at 30, 2.3% apart. Any per-frame coefficient in a pipeline with a
configurable frame rate deserves the same suspicion.

**Verifying a visualizer without playing audio.** Screenshots are unavailable (the shell has no
Screen Recording permission) and playing test tones is obnoxious. `NOWSEE_SELFTEST=signal` writes a
synthetic stereo tone directly into the ring buffers, which exercises analyzer, Metal upload, and
menu bar strip end to end in silence. Because the tone is steady, `peak=` in the diagnostics log
should hold a constant value frame after frame — drift there means something upstream is moving
when it should not be.
