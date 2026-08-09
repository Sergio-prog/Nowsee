export const PALETTES = {
  magma: ["#000004", "#3b0f6f", "#8c2981", "#dd4968", "#fc8d62", "#fcfdbf"],
  inferno: ["#000004", "#420a67", "#932667", "#dd513a", "#f98e09", "#fcffa4"],
  viridis: ["#440154", "#482475", "#3a5289", "#20918c", "#5ec962", "#fde725"],
  classic: ["#000000", "#0b0e4f", "#007bb3", "#2ecc73", "#f6e034", "#f9faf1"],
  ice: ["#020517", "#082553", "#0e5c96", "#2f9dce", "#8bdaec", "#ecfcff"],
  sunset: ["#0c051b", "#44104b", "#96215a", "#dd5145", "#f99c42", "#ffeaaf"],
  neon: ["#050214", "#2e0866", "#7e0ebf", "#e619a5", "#4cf2e5", "#e6fffb"],
  ember: ["#050201", "#3e0b05", "#8b2106", "#d04a08", "#f68f1d", "#ffe5a3"],
  mono: ["#000000", "#2e2e2e", "#737373", "#b8b8b8", "#e8e8e8", "#ffffff"],
};

function hexToRgb(hex) {
  const n = parseInt(hex.slice(1), 16);
  return [(n >> 16) & 255, (n >> 8) & 255, n & 255];
}

function rgbToHex(rgb) {
  return `#${rgb.map((c) => Math.round(Math.max(0, Math.min(255, c))).toString(16).padStart(2, "0")).join("")}`;
}

export function customStops(low, mid, high) {
  const l = hexToRgb(low);
  const m = hexToRgb(mid);
  const h = hexToRgb(high);
  const blend = (a, b) => rgbToHex(a.map((v, i) => v + (b[i] - v) * 0.5));
  return [rgbToHex(l.map((c) => c * 0.15)), low, blend(l, m), mid, blend(m, h), high];
}

export function buildLut(stops) {
  const rgb = stops.map(hexToRgb);
  const out = new Uint8ClampedArray(256 * 3);
  for (let i = 0; i < 256; i++) {
    const pos = (i / 255) * (rgb.length - 1);
    const lo = Math.min(Math.floor(pos), rgb.length - 1);
    const hi = Math.min(lo + 1, rgb.length - 1);
    const t = pos - lo;
    for (let c = 0; c < 3; c++) out[i * 3 + c] = rgb[lo][c] + (rgb[hi][c] - rgb[lo][c]) * t;
  }
  return out;
}
