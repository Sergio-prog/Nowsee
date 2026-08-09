export const MODES = [
  { id: "stereo", label: "Stereo", detail: "Left channel above the axis, right below." },
  { id: "bars", label: "Bars", detail: "Equalizer bars with falling peak caps." },
  { id: "sphere", label: "Sphere", detail: "A globe of points pushed out by frequency." },
  { id: "waves", label: "Waves", detail: "A dotted ribbon that folds along the signal." },
];

export const SOURCES = [
  { id: "demo", label: "Demo signal", hint: "Synthetic. Nothing to allow." },
  { id: "mic", label: "Microphone", hint: "Asks for input access." },
  { id: "file", label: "Audio file", hint: "Plays locally. Never uploaded." },
  { id: "tab", label: "Tab audio", hint: "Chrome and Edge. Share a tab with sound." },
];

export const DEFAULTS = {
  mode: "waves",
  palette: "magma",
  low: "#0b0e4f",
  mid: "#2ecc73",
  high: "#f9faf1",
  background: "#000000",
  glow: 0.4,
  trails: 0,
  fps: 60,

  gain: 1.15,
  smoothing: 0.55,
  floor: 0.04,
  lowHz: 30,
  highHz: 16000,

  waveLayers: 38,
  waveDots: 300,
  waveDot: 1.3,
  waveAmp: 0.58,
  waveFreq: 1.25,
  waveTwist: 0.04,
  waveSpeed: 0.55,
  wavePinch: 1.35,
  waveReact: 0.85,
  waveShape: "dots",

  stereoScale: 0.86,
  stereoAxis: 0.5,
  stereoLayout: "split",
  stereoFill: true,
  stereoStroke: 1.2,
  stereoSmooth: true,

  barCount: 56,
  barGap: 0.16,
  barRadius: 0.3,
  barScale: 0.94,
  barLayout: "bottom",
  barChannel: "mix",
  barCaps: true,
  barCapFall: 0.6,

  sphereRings: 34,
  spherePoints: 110,
  sphereRadius: 0.6,
  sphereReact: 0.6,
  sphereSpin: 0.22,
  sphereTilt: 0.03,
  sphereDot: 1.4,
  sphereDepth: 0.72,
  sphereFov: 2.6,
  sphereWire: false,
};

const percent = (value) => `${Math.round(value * 100)}%`;
const fixed = (digits) => (value) => value.toFixed(digits);
const count = (value) => String(Math.round(value));
const hertz = (value) => (value >= 1000 ? `${(value / 1000).toFixed(1)} kHz` : `${Math.round(value)} Hz`);

export const GROUPS = [
  {
    id: "colour",
    title: "Colour",
    controls: [
      { key: "palette", type: "palette", label: "Colormap" },
      { key: "low", type: "color", label: "Low", when: (s) => s.palette === "custom" },
      { key: "mid", type: "color", label: "Mid", when: (s) => s.palette === "custom" },
      { key: "high", type: "color", label: "High", when: (s) => s.palette === "custom" },
      { key: "background", type: "color", label: "Background" },
      { key: "glow", type: "range", label: "Glow", min: 0, max: 1, step: 0.01, format: percent },
      { key: "trails", type: "range", label: "Trails", min: 0, max: 0.94, step: 0.01, format: percent },
    ],
  },
  {
    id: "signal",
    title: "Signal",
    controls: [
      { key: "gain", type: "range", label: "Gain", min: 0.2, max: 6, step: 0.05, format: fixed(2) },
      { key: "smoothing", type: "range", label: "Smoothing", min: 0, max: 1, step: 0.01, format: percent },
      { key: "floor", type: "range", label: "Noise floor", min: 0, max: 0.5, step: 0.005, format: percent },
      { key: "lowHz", type: "range", label: "Lowest", min: 20, max: 400, step: 5, format: hertz },
      { key: "highHz", type: "range", label: "Highest", min: 2000, max: 20000, step: 250, format: hertz },
      {
        key: "fps",
        type: "select",
        label: "Frame rate",
        options: [
          { value: 15, label: "15" },
          { value: 30, label: "30" },
          { value: 60, label: "60" },
          { value: 120, label: "120" },
        ],
      },
    ],
  },
  {
    id: "waves",
    title: "Waves",
    when: (s) => s.mode === "waves",
    controls: [
      {
        key: "waveShape",
        type: "select",
        label: "Texture",
        options: [
          { value: "dots", label: "Dots" },
          { value: "lines", label: "Lines" },
        ],
      },
      { key: "waveLayers", type: "range", label: "Layers", min: 3, max: 64, step: 1, format: count },
      { key: "waveDots", type: "range", label: "Density", min: 40, max: 420, step: 10, format: count },
      { key: "waveDot", type: "range", label: "Dot size", min: 0.4, max: 4, step: 0.1, format: fixed(1) },
      { key: "waveAmp", type: "range", label: "Amplitude", min: 0.05, max: 1, step: 0.01, format: percent },
      { key: "waveFreq", type: "range", label: "Wavelength", min: 0.25, max: 6, step: 0.05, format: fixed(2) },
      { key: "waveTwist", type: "range", label: "Twist", min: 0, max: 0.6, step: 0.005, format: fixed(3) },
      { key: "waveSpeed", type: "range", label: "Drift", min: 0, max: 3, step: 0.01, format: fixed(2) },
      { key: "wavePinch", type: "range", label: "Pinch", min: 0.3, max: 4, step: 0.05, format: fixed(2) },
      { key: "waveReact", type: "range", label: "Reactivity", min: 0, max: 2, step: 0.01, format: fixed(2) },
    ],
  },
  {
    id: "stereo",
    title: "Stereo",
    when: (s) => s.mode === "stereo",
    controls: [
      {
        key: "stereoLayout",
        type: "select",
        label: "Layout",
        options: [
          { value: "split", label: "Split" },
          { value: "mirror", label: "Mirror" },
          { value: "stack", label: "Stack" },
        ],
      },
      { key: "stereoScale", type: "range", label: "Height", min: 0.2, max: 1, step: 0.01, format: percent },
      { key: "stereoAxis", type: "range", label: "Axis", min: 0.15, max: 0.85, step: 0.01, format: percent },
      { key: "stereoStroke", type: "range", label: "Outline", min: 0, max: 4, step: 0.1, format: fixed(1) },
      { key: "stereoFill", type: "toggle", label: "Fill" },
      { key: "stereoSmooth", type: "toggle", label: "Curved" },
    ],
  },
  {
    id: "bars",
    title: "Bars",
    when: (s) => s.mode === "bars",
    controls: [
      {
        key: "barLayout",
        type: "select",
        label: "Baseline",
        options: [
          { value: "bottom", label: "Bottom" },
          { value: "center", label: "Centre" },
          { value: "mirror", label: "Mirror" },
        ],
      },
      {
        key: "barChannel",
        type: "select",
        label: "Channels",
        options: [
          { value: "mix", label: "Mix" },
          { value: "left", label: "Left" },
          { value: "right", label: "Right" },
          { value: "split", label: "Split" },
        ],
      },
      { key: "barCount", type: "range", label: "Bars", min: 8, max: 160, step: 1, format: count },
      { key: "barGap", type: "range", label: "Gap", min: 0, max: 0.7, step: 0.01, format: percent },
      { key: "barRadius", type: "range", label: "Rounding", min: 0, max: 0.5, step: 0.01, format: percent },
      { key: "barScale", type: "range", label: "Height", min: 0.2, max: 1, step: 0.01, format: percent },
      { key: "barCaps", type: "toggle", label: "Peak caps" },
      {
        key: "barCapFall",
        type: "range",
        label: "Cap fall",
        min: 0.05,
        max: 2,
        step: 0.05,
        format: fixed(2),
        when: (s) => s.barCaps,
      },
    ],
  },
  {
    id: "sphere",
    title: "Sphere",
    when: (s) => s.mode === "sphere",
    controls: [
      { key: "sphereRings", type: "range", label: "Rings", min: 6, max: 64, step: 1, format: count },
      { key: "spherePoints", type: "range", label: "Points per ring", min: 12, max: 180, step: 2, format: count },
      { key: "sphereRadius", type: "range", label: "Radius", min: 0.2, max: 0.95, step: 0.01, format: percent },
      { key: "sphereReact", type: "range", label: "Displacement", min: 0, max: 1.5, step: 0.01, format: fixed(2) },
      { key: "sphereSpin", type: "range", label: "Spin", min: -1.5, max: 1.5, step: 0.01, format: fixed(2) },
      { key: "sphereTilt", type: "range", label: "Tumble", min: -1, max: 1, step: 0.01, format: fixed(2) },
      { key: "sphereDot", type: "range", label: "Point size", min: 0.4, max: 5, step: 0.1, format: fixed(1) },
      { key: "sphereDepth", type: "range", label: "Depth fade", min: 0, max: 1, step: 0.01, format: percent },
      { key: "sphereFov", type: "range", label: "Perspective", min: 1.2, max: 5, step: 0.05, format: fixed(2) },
      { key: "sphereWire", type: "toggle", label: "Wireframe" },
    ],
  },
];

export const RANDOMISABLE = GROUPS.flatMap((group) =>
  group.controls
    .filter((control) => control.type === "range" || control.type === "toggle" || control.type === "select")
    .filter((control) => !["fps", "lowHz", "highHz", "gain", "floor"].includes(control.key))
    .map((control) => ({ ...control, group: group.id })),
);
