# Contributing

Issues and pull requests are welcome.

## Before you start on the audio path

Read [docs/ENGINEERING.md](docs/ENGINEERING.md). Core Audio process taps fail silently in several
ways that look like a bug in your change and are not — capture from a CLI binary returns silence
forever with no error, a tap-only aggregate device returns silence with no error, and killing a
process that holds a tap wedges system audio until `coreaudiod` is restarted.

Two rules that are not negotiable:

- **Never SIGKILL a process holding a tap.** Use SIGINT, or `raycast/restart-nowsee.sh`.
- **Never add a listener on a Core Audio property you mutate yourself.** A
  `kAudioHardwarePropertyDevices` listener produced an infinite rebuild loop, because creating the
  aggregate device is itself a device-list change.

## Setup

```sh
make cert     # once — a self-signed identity so macOS remembers the audio permission
make check    # DSP assertions, no audio device needed, makes no sound
make install  # build, install to /Applications, launch
```

Needs macOS 15 and Swift 6 with Command Line Tools. There is no Xcode project on purpose; SPM plus
the Makefile assembles the bundle, so everything stays as text files.

## Verifying a change

`make check` must pass. If your change touches DSP, add an assertion to
`Sources/nowsee-check/main.swift` — it is the test suite, and it exists in that shape because
neither XCTest nor swift-testing ships with Command Line Tools.

To see a change without playing anything:

```sh
NOWSEE_DIAGNOSTICS=1 NOWSEE_SELFTEST=signal open dist/Nowsee.app
tail -f ~/Library/Logs/nowsee.log
```

That feeds a synthetic stereo tone straight into the ring buffers, so every mode runs end to end in
silence. Because the tone is steady, `peak=` should hold constant frame after frame — drift means
something upstream is moving when it should not be.

When you report a CPU number, say which windows were open. The settings window roughly doubles it,
and a number without that context means nothing.

## Style

- No comments unless the code genuinely cannot say it. Name things so it can.
- Conventional commits (`feat:`, `fix:`, `perf:`, `docs:`, `refactor:`).
- Match the surrounding code rather than introducing a new idiom.
- Settings need a default, persistence in `NowseeSettings`, and a control in `SettingsView`.
- A new visualization needs a Metal pipeline in `SpectrogramRenderer` **and** a Core Graphics path
  in `StripVisualizationView`. The menu bar is not optional — if a mode cannot work at 72×22 pt,
  say so in the pull request and propose a fallback.

## The landing page

`web/` is a separate Vite and Tailwind project with its own [README](web/README.md).
