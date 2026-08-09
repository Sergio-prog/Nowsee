# Site

Two pages at [nowsee.serhiifotex.dev](https://nowsee.serhiifotex.dev/): the one-screen landing
page at `/`, and the studio at `/studio/`. Vite and Tailwind CSS v4, no framework.

```sh
bun install
bun dev        # http://localhost:5173
bun run build  # -> dist/
bun preview
```

## The landing page

Nowsee is a visualizer, so a screenshot of it is a lie — the whole point is that it moves. The
page runs the visualizer instead: the same six modes and ten palettes as the app, drawn on a
canvas from a synthetic signal, at 30 fps.

The signal is a port of the app's own preview generator — drifting formant partials over a
harmonic series and a 108 bpm beat. It is the shape of music without being any music, which is
also why the app ships it: previews have to move in a quiet room.

The strip in the page's menu bar is a second surface reading the same history buffer, exactly as
the real menu bar item does. Switching modes changes both. That is the one thing on the page
worth remembering, so everything around it stays quiet.

The palette hexes in `src/palettes.js` are the app's real colormaps from
`Sources/Nowsee/Palette.swift`, converted to hex. If you change one there, change it here.

## The studio

`/studio/` is the same idea taken as far as it goes: four modes — Stereo, Bars, Sphere, Waves —
with every parameter exposed as a control, and real audio instead of only the synthetic signal.
Sources are the demo signal, the microphone, a local audio file, and a shared tab
(`getDisplayMedia`, Chrome and Edge only — the browser has no equivalent of the app's system tap).

Real audio goes through a port of the app's own chain: two `AnalyserNode`s split L/R, 128 log
bands over 30 Hz–16 kHz, the −85 dB floor and 80 dB span from `StereoSpectrumAnalyzer`, its
gaussian band spread, and its attack/release taus. The demo signal enters the same chain as raw
band targets, so both paths smooth identically.

Settings persist to `localStorage` and encode into the URL hash as a diff against the defaults,
which is what **Copy link** shares. Nothing is uploaded; audio never leaves the tab.

## Layout

```
index.html            landing markup, Tailwind utilities inline
studio/index.html     studio markup
src/main.js           landing wiring: controls, clipboard, clock, frame loop
src/signal.js         the synthetic signal
src/renderers.js      one draw function per landing visualization
src/palettes.js       colormaps and the 256-entry lookup table
src/style.css         @theme tokens and the handful of things utilities cannot express
src/studio/dsp.js     log frequency map, band smoother, shared constants
src/studio/demo.js    synthetic signal at the studio's band count, with a time-domain wave
src/studio/audio.js   sources, analysers, the frame the renderers read
src/studio/schema.js  defaults and every control, as data
src/studio/controls.js  builds the rail from the schema
src/studio/render.js  one draw function per studio mode, plus the bloom pass
src/studio/main.js    wiring: state, persistence, keys, frame loop
public/CNAME          custom domain for GitHub Pages
```

Adding a control means adding one entry to `GROUPS` in `schema.js` and reading `s.<key>` in the
renderer. Nothing else needs to change — the rail, randomiser, persistence and share link all
walk the schema.

Dynamic class names live in `MODE_CLASSES`, `SWATCH_CLASSES` and the constants at the top of
`src/studio/controls.js` as complete string literals, because Tailwind scans source text — a
class assembled at runtime never gets generated.

`base` is `/` rather than `./`, because relative asset paths break for a page one directory
down. The site is served from a domain root, so this is safe; opening `dist/index.html` over
`file://` is not.

## Deploying

`.github/workflows/pages.yml` builds `web/` and publishes to GitHub Pages on any push to `main`
that touches it. Two one-time steps:

1. Repository → Settings → Pages → Source: **GitHub Actions**.
2. A DNS `CNAME` record for `nowsee` pointing at `sergio-prog.github.io`.

`public/CNAME` is copied into `dist/` by Vite, which is what keeps the custom domain set across
deploys.
