# Landing page

The one-screen site at [nowsee.serhiifotex.dev](https://nowsee.serhiifotex.dev/). Vite and
Tailwind CSS v4, no framework.

```sh
pnpm install
pnpm dev       # http://localhost:5173
pnpm build     # -> dist/
pnpm preview
```

## What it is

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

## Layout

```
index.html          markup, Tailwind utilities inline
src/main.js         wiring: controls, clipboard, clock, frame loop
src/signal.js       the synthetic signal
src/renderers.js    one draw function per visualization
src/palettes.js     colormaps and the 256-entry lookup table
src/style.css       @theme tokens and the handful of things utilities cannot express
public/CNAME        custom domain for GitHub Pages
```

Dynamic class names live in the `MODE_CLASSES` and `SWATCH_CLASSES` arrays as complete string
literals, because Tailwind scans source text — a class assembled at runtime never gets generated.

## Deploying

`.github/workflows/pages.yml` builds `web/` and publishes to GitHub Pages on any push to `main`
that touches it. Two one-time steps:

1. Repository → Settings → Pages → Source: **GitHub Actions**.
2. A DNS `CNAME` record for `nowsee` pointing at `sergio-prog.github.io`.

`public/CNAME` is copied into `dist/` by Vite, which is what keeps the custom domain set across
deploys.
