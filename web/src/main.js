import "./style.css";
import { inject } from "@vercel/analytics";
import { createSignal, HISTORY } from "./signal.js";
import { PALETTES, buildLut } from "./palettes.js";
import { MODES, createSurface, sizeSurface, paint } from "./renderers.js";

inject();

const FPS = 30;
const BREW = [
  "brew tap sergio-prog/tap",
  "brew trust --cask sergio-prog/tap/nowsee",
  "brew install --cask --no-quarantine nowsee",
].join("\n");

const signal = createSignal();
let mode = MODES[0].id;
let lut = buildLut(PALETTES.magma);

const surfaces = [
  createSurface(document.getElementById("scope"), { colWidth: 3, barCount: 46 }),
  createSurface(document.getElementById("strip"), { colWidth: 1, barCount: 13 }),
];

const repaint = () => surfaces.forEach((s) => paint(s, mode, signal, lut));

const stageTag = document.getElementById("stageTag");
const modeBox = document.getElementById("modes");
const paletteBox = document.getElementById("palettes");

const MODE_CLASSES = [
  "font-mono",
  "text-[11.5px]",
  "px-[9px]",
  "py-1",
  "rounded-full",
  "border",
  "border-transparent",
  "text-dim",
  "cursor-pointer",
  "transition-colors",
  "hover:text-ink",
  "hover:bg-white/5",
  "aria-pressed:text-ink",
  "aria-pressed:bg-white/8",
  "aria-pressed:border-hairline-bright",
];

MODES.forEach(({ id, label }) => {
  const button = document.createElement("button");
  button.type = "button";
  button.textContent = label;
  button.classList.add(...MODE_CLASSES);
  button.setAttribute("aria-pressed", String(id === mode));
  button.addEventListener("click", () => {
    mode = id;
    stageTag.textContent = label;
    [...modeBox.children].forEach((el, i) =>
      el.setAttribute("aria-pressed", String(MODES[i].id === id)),
    );
    surfaces.forEach((s) => s.peaks.fill(0));
    repaint();
  });
  modeBox.appendChild(button);
});

const SWATCH_CLASSES = [
  "w-[30px]",
  "h-[15px]",
  "rounded",
  "border",
  "border-white/15",
  "cursor-pointer",
  "transition-transform",
  "hover:-translate-y-0.5",
  "aria-pressed:shadow-[0_0_0_2px_var(--color-void),0_0_0_3px_var(--color-ink)]",
];

Object.entries(PALETTES).forEach(([name, stops], index) => {
  const button = document.createElement("button");
  button.type = "button";
  button.style.background = `linear-gradient(90deg, ${stops.join(",")})`;
  button.classList.add(...SWATCH_CLASSES);
  button.setAttribute("aria-pressed", String(index === 0));
  button.setAttribute("aria-label", name);
  button.title = name[0].toUpperCase() + name.slice(1);
  button.addEventListener("click", () => {
    lut = buildLut(stops);
    [...paletteBox.children].forEach((el) =>
      el.setAttribute("aria-pressed", String(el.getAttribute("aria-label") === name)),
    );
    repaint();
  });
  paletteBox.appendChild(button);
});

const copy = document.getElementById("copy");
copy.addEventListener("click", async () => {
  try {
    await navigator.clipboard.writeText(BREW);
    copy.textContent = "Copied";
    copy.classList.add("text-magma-4");
    setTimeout(() => {
      copy.textContent = "Copy";
      copy.classList.remove("text-magma-4");
    }, 1600);
  } catch {
    copy.textContent = "⌘C";
  }
});

const clockEl = document.getElementById("clock");
const showTime = () => {
  clockEl.textContent = new Date().toLocaleTimeString([], {
    hour: "numeric",
    minute: "2-digit",
  });
};
showTime();
setInterval(showTime, 20000);

const resize = () => {
  surfaces.forEach(sizeSurface);
  repaint();
};
window.addEventListener("resize", resize);
surfaces.forEach(sizeSurface);

for (let i = 0; i < HISTORY; i++) signal.advance(1 / FPS);
repaint();

if (!window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
  const interval = 1000 / FPS;
  let last = 0;
  let visible = true;

  document.addEventListener("visibilitychange", () => {
    visible = !document.hidden;
  });

  const frame = (now) => {
    requestAnimationFrame(frame);
    if (!visible || now - last < interval) return;
    signal.advance(Math.min(0.1, last ? (now - last) / 1000 : interval / 1000));
    last = now;
    repaint();
  };

  requestAnimationFrame(frame);
}
