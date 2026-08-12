import { BANDS, HISTORY } from "./signal.js";

const FIXED_GAIN = 1.7;

export const MODES = [
  { id: "bars", label: "Bars" },
  { id: "spectrogram", label: "Spectrogram" },
  { id: "waveform", label: "Waveform" },
  { id: "ocean", label: "Ocean" },
  { id: "stereo", label: "Stereo" },
  { id: "morph", label: "Morph" },
];

export function createSurface(canvas, { colWidth, barCount }) {
  const scratch = document.createElement("canvas");
  return {
    canvas,
    ctx: canvas.getContext("2d"),
    scratch,
    sctx: scratch.getContext("2d"),
    colWidth,
    barCount,
    peaks: new Float32Array(BANDS),
    w: 0,
    h: 0,
    dpr: 1,
  };
}

export function sizeSurface(s) {
  const dpr = Math.min(window.devicePixelRatio || 1, 2);
  const rect = s.canvas.getBoundingClientRect();
  if (!rect.width) return;
  const w = Math.round(rect.width * dpr);
  const h = Math.round(rect.height * dpr);
  if (w !== s.canvas.width || h !== s.canvas.height) {
    s.canvas.width = w;
    s.canvas.height = h;
  }
  s.w = w;
  s.h = h;
  s.dpr = dpr;
}

function cols(s) {
  return Math.max(8, Math.min(HISTORY, Math.floor(s.w / (s.colWidth * s.dpr))));
}

function shade(lut, level, alpha = 1) {
  const i = Math.max(0, Math.min(255, Math.round(level * 255))) * 3;
  return `rgba(${lut[i]},${lut[i + 1]},${lut[i + 2]},${alpha})`;
}

function drawSpectrogram(s, signal, lut) {
  const n = cols(s);
  if (s.scratch.width !== n || s.scratch.height !== BANDS) {
    s.scratch.width = n;
    s.scratch.height = BANDS;
  }
  const img = s.sctx.createImageData(n, BANDS);
  const px = img.data;
  for (let x = 0; x < n; x++) {
    const bands = signal.column(n - 1 - x).bands;
    for (let y = 0; y < BANDS; y++) {
      const i = Math.max(0, Math.min(255, Math.round(bands[BANDS - 1 - y] * 255))) * 3;
      const o = (y * n + x) * 4;
      px[o] = lut[i];
      px[o + 1] = lut[i + 1];
      px[o + 2] = lut[i + 2];
      px[o + 3] = 255;
    }
  }
  s.sctx.putImageData(img, 0, 0);
  s.ctx.imageSmoothingEnabled = true;
  s.ctx.imageSmoothingQuality = "high";
  s.ctx.drawImage(s.scratch, 0, 0, n, BANDS, 0, 0, s.w, s.h);
}

function drawWaveform(s, signal, lut) {
  const { ctx } = s;
  const n = cols(s);
  const mid = s.h / 2;
  const scale = s.h * 0.46;
  ctx.beginPath();
  for (let x = 0; x < n; x++) {
    ctx.lineTo((x / (n - 1)) * s.w, mid - signal.column(n - 1 - x).hi * scale);
  }
  for (let x = n - 1; x >= 0; x--) {
    ctx.lineTo((x / (n - 1)) * s.w, mid - signal.column(n - 1 - x).lo * scale);
  }
  ctx.closePath();
  const g = ctx.createLinearGradient(0, 0, 0, s.h);
  g.addColorStop(0, shade(lut, 0.9));
  g.addColorStop(0.5, shade(lut, 0.55));
  g.addColorStop(1, shade(lut, 0.9));
  ctx.fillStyle = g;
  ctx.fill();
}

function drawOcean(s, signal, lut) {
  const { ctx } = s;
  const n = cols(s);
  const scale = s.h * 0.78;
  const y = (x) => s.h - signal.column(n - 1 - x).swell * scale;

  ctx.beginPath();
  ctx.moveTo(0, s.h);
  for (let x = 0; x < n; x++) ctx.lineTo((x / (n - 1)) * s.w, y(x));
  ctx.lineTo(s.w, s.h);
  ctx.closePath();
  const g = ctx.createLinearGradient(0, s.h, 0, 0);
  g.addColorStop(0, shade(lut, 0.2));
  g.addColorStop(0.6, shade(lut, 0.55));
  g.addColorStop(1, shade(lut, 0.85));
  ctx.fillStyle = g;
  ctx.fill();

  ctx.beginPath();
  for (let x = 0; x < n; x++) ctx.lineTo((x / (n - 1)) * s.w, y(x));
  ctx.lineWidth = Math.max(1, s.h * 0.012);
  ctx.strokeStyle = shade(lut, 1);
  ctx.stroke();
}

function drawBars(s, signal, lut) {
  const { ctx } = s;
  const slot = s.w / s.barCount;
  const gap = slot * 0.18;
  const width = Math.max(1, slot - gap);
  const capHeight = Math.max(1, s.h * 0.012);
  for (let i = 0; i < s.barCount; i++) {
    const b = Math.min(BANDS - 1, Math.floor((i / s.barCount) * BANDS));
    const level = Math.min(1, signal.smoothL[b] * FIXED_GAIN);
    s.peaks[i] = Math.max(level, s.peaks[i] - 0.012);
    const h = level * s.h * 0.94;
    ctx.fillStyle = shade(lut, 0.32 + level * 0.68);
    ctx.fillRect(i * slot + gap / 2, s.h - h, width, h);
    ctx.fillStyle = shade(lut, 0.95, 0.85);
    ctx.fillRect(i * slot + gap / 2, s.h - s.peaks[i] * s.h * 0.94 - capHeight, width, capHeight);
  }
}

function drawStereo(s, signal, lut) {
  const { ctx } = s;
  const mid = s.h / 2;
  const scale = s.h * 0.47;
  const lobe = (data, sign) => {
    ctx.beginPath();
    ctx.moveTo(0, mid);
    for (let b = 0; b < BANDS; b++) {
      const level = Math.min(1, data[b] * FIXED_GAIN);
      ctx.lineTo((b / (BANDS - 1)) * s.w, mid - sign * level * scale);
    }
    ctx.lineTo(s.w, mid);
    ctx.closePath();
    const g = ctx.createLinearGradient(0, mid - sign * scale, 0, mid);
    g.addColorStop(0, shade(lut, 0.95));
    g.addColorStop(1, shade(lut, 0.35));
    ctx.fillStyle = g;
    ctx.fill();
    ctx.lineWidth = Math.max(1, s.h * 0.008);
    ctx.strokeStyle = shade(lut, 1, 0.75);
    ctx.stroke();
  };
  lobe(signal.smoothL, 1);
  lobe(signal.smoothR, -1);
}

function drawMorph(s, signal, lut) {
  const { ctx } = s;
  const mid = s.h / 2;
  const scale = s.h * 0.45;
  ctx.lineWidth = Math.max(1.2, s.h * 0.014);
  ctx.lineJoin = "round";
  const trace = (data, sign, level) => {
    ctx.beginPath();
    for (let b = 0; b < BANDS; b++) {
      ctx.lineTo((b / (BANDS - 1)) * s.w, mid - sign * Math.min(1, data[b] * FIXED_GAIN) * scale);
    }
    ctx.strokeStyle = shade(lut, level);
    ctx.stroke();
  };
  trace(signal.smoothL, 1, 0.92);
  trace(signal.smoothR, -1, 0.6);
}

const RENDER = {
  spectrogram: drawSpectrogram,
  waveform: drawWaveform,
  ocean: drawOcean,
  bars: drawBars,
  stereo: drawStereo,
  morph: drawMorph,
};

export function paint(s, mode, signal, lut) {
  if (!s.w) return;
  s.ctx.clearRect(0, 0, s.w, s.h);
  RENDER[mode](s, signal, lut);
}
