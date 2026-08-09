import "../style.css";
import { PALETTES, buildLut, customStops } from "../palettes.js";
import { createEngine } from "./audio.js";
import { createControls } from "./controls.js";
import { createScene, paint, shade, sizeScene } from "./render.js";
import { DEFAULTS, GROUPS, MODES, RANDOMISABLE, SOURCES } from "./schema.js";

const STORE = "nowsee.studio.v1";
const STRIP = {
  barCount: 13,
  barGap: 0.22,
  barCaps: false,
  waveLayers: 9,
  waveDots: 70,
  waveDot: 1,
  waveAmp: 0.62,
  sphereRings: 10,
  spherePoints: 26,
  sphereRadius: 0.78,
  sphereDot: 1,
  stereoStroke: 0.8,
  stereoScale: 0.95,
  glow: 0.15,
  trails: 0,
};

const $ = (id) => document.getElementById(id);

function decodePreset() {
  const match = location.hash.match(/p=([^&]+)/);
  if (!match) return null;
  try {
    return JSON.parse(atob(decodeURIComponent(match[1])));
  } catch {
    return null;
  }
}

function loadState() {
  let stored = {};
  try {
    stored = JSON.parse(localStorage.getItem(STORE) || "{}");
  } catch {
    stored = {};
  }
  return { ...DEFAULTS, ...stored, ...(decodePreset() || {}) };
}

const state = loadState();
const engine = createEngine();
const stage = createScene($("stage"));
const strip = createScene($("strip"));
const stripState = { ...state, ...STRIP };

let lut = buildLut(PALETTES.magma);
let playing = !window.matchMedia("(prefers-reduced-motion: reduce)").matches;
let frames = 0;
let fpsClock = 0;

function stops() {
  return state.palette === "custom"
    ? customStops(state.low, state.mid, state.high)
    : PALETTES[state.palette] || PALETTES.magma;
}

function applyPalette() {
  lut = buildLut(stops());
  const root = document.documentElement;
  const accent = shade(lut, 0.82, 1);
  const index = Math.round(0.82 * 255) * 3;
  const bright = (lut[index] * 0.299 + lut[index + 1] * 0.587 + lut[index + 2] * 0.114) / 255;
  root.style.setProperty("--accent", accent);
  root.style.setProperty("--accent-ink", bright > 0.6 ? "#08070d" : "#efedf5");
  root.style.setProperty("--halo", shade(lut, 0.55, 0.34));
  root.style.setProperty("--halo-soft", shade(lut, 0.72, 0.16));
}

function persist() {
  const diff = {};
  for (const key of Object.keys(DEFAULTS)) {
    if (state[key] !== DEFAULTS[key]) diff[key] = state[key];
  }
  try {
    localStorage.setItem(STORE, JSON.stringify(diff));
  } catch {
    /* private mode */
  }
  return diff;
}

const rail = $("rail");
const modeDetail = $("modeDetail");
const stageTag = $("stageTag");
const sourceNote = $("sourceNote");

const controls = createControls(rail, state, (key, value) => {
  state[key] = value;
  Object.assign(stripState, state, STRIP);
  if (["palette", "low", "mid", "high"].includes(key)) applyPalette();
  if (key === "barCount") stage.caps.fill(0);
  controls.refresh();
  persist();
});

const modeButtons = MODES.map((mode) => {
  const button = document.createElement("button");
  button.type = "button";
  button.className =
    "flex cursor-pointer flex-col gap-[3px] rounded-[7px] border border-hairline bg-white/2 px-[10px] py-2 text-left transition-colors hover:border-hairline-bright hover:bg-white/5 aria-pressed:border-transparent aria-pressed:bg-[var(--accent)] aria-pressed:text-[var(--accent-ink)]";
  const label = document.createElement("span");
  label.className = "text-[12.5px] font-medium tracking-tight";
  label.textContent = mode.label;
  button.append(label);
  button.addEventListener("click", () => setMode(mode.id));
  $("modes").append(button);
  return { button, mode };
});

function setMode(id) {
  state.mode = id;
  Object.assign(stripState, state, STRIP);
  stage.caps.fill(0);
  strip.caps.fill(0);
  modeButtons.forEach(({ button, mode }) =>
    button.setAttribute("aria-pressed", String(mode.id === id)),
  );
  const current = MODES.find((mode) => mode.id === id);
  stageTag.textContent = current.label;
  modeDetail.textContent = current.detail;
  controls.refresh();
  persist();
}

const sourceButtons = SOURCES.map((source) => {
  const button = document.createElement("button");
  button.type = "button";
  button.className =
    "cursor-pointer rounded-[6px] border border-hairline bg-white/2 px-[9px] py-[6px] font-mono text-[11px] text-dim transition-colors hover:border-hairline-bright hover:text-ink aria-pressed:border-transparent aria-pressed:bg-[var(--accent)] aria-pressed:text-[var(--accent-ink)]";
  button.textContent = source.label;
  button.title = source.hint;
  button.addEventListener("click", () => {
    if (source.id === "file") $("file").click();
    else pickSource(source.id);
  });
  $("sources").append(button);
  return { button, source };
});

function syncSource() {
  sourceButtons.forEach(({ button, source }) =>
    button.setAttribute("aria-pressed", String(engine.status.kind === source.id)),
  );
  const active = SOURCES.find((source) => source.id === engine.status.kind);
  sourceNote.textContent = engine.status.error || `${engine.status.detail} · ${active.hint}`;
  sourceNote.style.color = engine.status.error ? "var(--accent)" : "";
}

async function pickSource(kind, payload) {
  sourceNote.textContent =
    kind === "tab" ? "Pick a tab or screen, then tick “Share audio”." : "Waiting for permission…";
  await engine.setSource(kind, payload);
  syncSource();
}

$("file").addEventListener("change", (event) => {
  const file = event.target.files?.[0];
  if (file) pickSource("file", file);
});

const shell = $("shell");
shell.addEventListener("dragover", (event) => {
  event.preventDefault();
  shell.classList.add("ring-1", "ring-[var(--accent)]");
});
shell.addEventListener("dragleave", () => shell.classList.remove("ring-1", "ring-[var(--accent)]"));
shell.addEventListener("drop", (event) => {
  event.preventDefault();
  shell.classList.remove("ring-1", "ring-[var(--accent)]");
  const file = [...(event.dataTransfer?.files || [])].find((item) => item.type.startsWith("audio"));
  if (file) pickSource("file", file);
});

function randomise() {
  const pool = Object.keys(PALETTES);
  state.palette = pool[Math.floor(Math.random() * pool.length)];
  RANDOMISABLE.forEach((control) => {
    const group = GROUPS.find((item) => item.id === control.group);
    if (group.when && !group.when(state)) return;
    if (control.when && !control.when(state)) return;
    if (control.type === "range") {
      const steps = Math.round((control.max - control.min) / control.step);
      state[control.key] = Number(
        (control.min + Math.round(Math.random() * steps) * control.step).toFixed(4),
      );
    } else if (control.type === "toggle") {
      state[control.key] = Math.random() > 0.4;
    } else {
      const option = control.options[Math.floor(Math.random() * control.options.length)];
      state[control.key] = option.value;
    }
  });
  state.trails = Math.min(state.trails, 0.75);
  Object.assign(stripState, state, STRIP);
  applyPalette();
  controls.refresh();
  persist();
}

function reset() {
  Object.assign(state, DEFAULTS);
  Object.assign(stripState, state, STRIP);
  applyPalette();
  setMode(state.mode);
  controls.refresh();
  persist();
}

async function share(button) {
  const encoded = encodeURIComponent(btoa(JSON.stringify(persist())));
  const url = `${location.origin}${location.pathname}#p=${encoded}`;
  history.replaceState(null, "", `#p=${encoded}`);
  const original = button.textContent;
  try {
    await navigator.clipboard.writeText(url);
    button.textContent = "Link copied";
  } catch {
    button.textContent = "Copy failed";
  }
  setTimeout(() => {
    button.textContent = original;
  }, 1800);
}

function snapshot() {
  stage.canvas.toBlob((blob) => {
    const link = document.createElement("a");
    link.href = URL.createObjectURL(blob);
    link.download = `nowsee-${state.mode}.png`;
    link.click();
    URL.revokeObjectURL(link.href);
  });
}

const playButton = $("play");
function setPlaying(next) {
  playing = next;
  playButton.textContent = playing ? "Pause" : "Play";
  playButton.setAttribute("aria-pressed", String(!playing));
}

playButton.addEventListener("click", () => setPlaying(!playing));
$("randomise").addEventListener("click", randomise);
$("reset").addEventListener("click", reset);
$("share").addEventListener("click", (event) => share(event.currentTarget));
$("snapshot").addEventListener("click", snapshot);
$("expand").addEventListener("click", () => {
  const box = $("stageBox");
  if (document.fullscreenElement) document.exitFullscreen();
  else box.requestFullscreen?.();
});

document.addEventListener("keydown", (event) => {
  if (event.target.matches("input, select, textarea, button")) return;
  const index = Number(event.key) - 1;
  if (index >= 0 && index < MODES.length) setMode(MODES[index].id);
  if (event.key === " ") {
    event.preventDefault();
    setPlaying(!playing);
  }
  if (event.key.toLowerCase() === "r") randomise();
  if (event.key.toLowerCase() === "f") $("expand").click();
});

const meterL = $("meterL");
const meterR = $("meterR");
const fpsRead = $("fps");

function readouts(dt) {
  meterL.style.width = `${Math.round(Math.min(1, engine.frame.levelL * 2.4) * 100)}%`;
  meterR.style.width = `${Math.round(Math.min(1, engine.frame.levelR * 2.4) * 100)}%`;
  frames++;
  fpsClock += dt;
  if (fpsClock >= 0.5) {
    fpsRead.textContent = `${Math.round(frames / fpsClock)} fps`;
    frames = 0;
    fpsClock = 0;
  }
}

const resize = () => {
  sizeScene(stage);
  sizeScene(strip);
};

if (window.ResizeObserver) {
  const observer = new ResizeObserver(resize);
  observer.observe(stage.canvas);
  observer.observe(strip.canvas);
}
window.addEventListener("resize", resize);
document.addEventListener("fullscreenchange", resize);
resize();

engine.onstatus = syncSource;
applyPalette();
setMode(state.mode);
syncSource();
setPlaying(playing);

let previous = 0;
let carry = 0;

function frame(now) {
  requestAnimationFrame(frame);
  const dt = previous ? Math.min(0.1, (now - previous) / 1000) : 1 / 60;
  previous = now;
  if (!playing || document.hidden) return;
  carry += dt;
  if (carry < 1 / state.fps - 0.002) return;
  const step = carry;
  carry = 0;
  engine.update(step, state);
  paint(stage, engine.frame, state, lut, step);
  paint(strip, engine.frame, stripState, lut, step);
  readouts(step);
}

engine.update(1 / 60, state);
paint(stage, engine.frame, state, lut, 1 / 60);
paint(strip, engine.frame, stripState, lut, 1 / 60);
requestAnimationFrame(frame);
