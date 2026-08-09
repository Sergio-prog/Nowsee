import { BANDS, WAVE, clamp } from "./dsp.js";

const TWO_PI = Math.PI * 2;

export function createScene(canvas) {
  const layer = document.createElement("canvas");
  const glow = document.createElement("canvas");
  return {
    canvas,
    ctx: canvas.getContext("2d", { alpha: false }),
    layer,
    lctx: layer.getContext("2d"),
    glow,
    gctx: glow.getContext("2d"),
    caps: new Float32Array(256),
    mix: new Float32Array(BANDS),
    w: 0,
    h: 0,
    dpr: 1,
    t: 0,
  };
}

export function sizeScene(scene, maxDpr = 2) {
  const dpr = Math.min(window.devicePixelRatio || 1, maxDpr);
  const rect = scene.canvas.getBoundingClientRect();
  if (!rect.width || !rect.height) return;
  const w = Math.round(rect.width * dpr);
  const h = Math.round(rect.height * dpr);
  if (w !== scene.canvas.width || h !== scene.canvas.height) {
    scene.canvas.width = w;
    scene.canvas.height = h;
  }
  if (w !== scene.layer.width || h !== scene.layer.height) {
    scene.layer.width = w;
    scene.layer.height = h;
  }
  scene.w = w;
  scene.h = h;
  scene.dpr = dpr;
}

function rgb(hex) {
  const value = parseInt(hex.slice(1), 16);
  return [(value >> 16) & 255, (value >> 8) & 255, value & 255];
}

function alphaOf(hex, alpha) {
  const [r, g, b] = rgb(hex);
  return `rgba(${r},${g},${b},${alpha})`;
}

export function shade(lut, level, alpha = 1) {
  const index = clamp(Math.round(level * 255), 0, 255) * 3;
  return `rgba(${lut[index]},${lut[index + 1]},${lut[index + 2]},${alpha})`;
}

function bandAt(data, position) {
  return data[clamp(Math.round(position * (BANDS - 1)), 0, BANDS - 1)];
}

function waveAt(data, position) {
  return data[clamp(Math.round(position * (WAVE - 1)), 0, WAVE - 1)];
}

function sliceLevel(data, from, to) {
  const start = clamp(Math.floor(from), 0, BANDS - 1);
  const end = clamp(Math.ceil(to), start + 1, BANDS);
  let peak = 0;
  for (let band = start; band < end; band++) peak = Math.max(peak, data[band]);
  return peak;
}

const hasRoundRect = typeof CanvasRenderingContext2D !== "undefined" && CanvasRenderingContext2D.prototype.roundRect;

function block(ctx, x, y, width, height, radius) {
  if (radius > 0.5 && hasRoundRect) {
    ctx.beginPath();
    ctx.roundRect(x, y, width, height, Math.min(radius, width / 2, Math.abs(height) / 2));
    ctx.fill();
  } else {
    ctx.fillRect(x, y, width, height);
  }
}

function drawWaves(ctx, scene, frame, s, lut) {
  const { w, h, dpr } = scene;
  const mid = h * 0.5;
  const layers = Math.round(s.waveLayers);
  const dots = Math.round(s.waveDots);
  const amp = s.waveAmp * h * 0.5;
  const phase = scene.t * s.waveSpeed * Math.PI;
  const size = Math.max(0.6, s.waveDot * dpr);
  const lines = s.waveShape === "lines";

  ctx.globalCompositeOperation = "lighter";
  ctx.lineJoin = "round";
  ctx.lineCap = "round";
  ctx.lineWidth = size;

  for (let layer = 0; layer < layers; layer++) {
    const spread = layers === 1 ? 1 : -1 + (2 * layer) / (layers - 1);
    const edge = Math.abs(spread);
    const tone = 0.3 + 0.7 * edge * (0.6 + 0.4 * frame.level);
    const alpha = (0.24 + 0.76 * edge) * (lines ? 0.5 : 0.72);
    const paint = shade(lut, tone, alpha);
    if (lines) {
      ctx.strokeStyle = paint;
      ctx.beginPath();
    } else {
      ctx.fillStyle = paint;
    }

    for (let index = 0; index < dots; index++) {
      const position = index / (dots - 1);
      const envelope = Math.pow(Math.sin(Math.PI * position), s.wavePinch);
      const sample = waveAt(frame.wave, position);
      const band = bandAt(frame.left, position);
      const swing = Math.sin(position * TWO_PI * s.waveFreq - phase + layer * s.waveTwist);
      const react = 1 + s.waveReact * band * 1.15;
      const detail = sample * s.waveReact * 0.45;
      const y = mid + envelope * spread * amp * (swing * react + detail);
      const x = position * w;
      if (lines) ctx.lineTo(x, y);
      else ctx.fillRect(x - size * 0.5, y - size * 0.5, size, size);
    }

    if (lines) ctx.stroke();
  }
}

function traceLobe(ctx, data, axis, scale, sign, w, smooth, close) {
  ctx.beginPath();
  let previousX = 0;
  let previousY = axis - sign * data[0] * scale;
  ctx.moveTo(previousX, previousY);
  for (let band = 1; band < BANDS; band++) {
    const x = (band / (BANDS - 1)) * w;
    const y = axis - sign * data[band] * scale;
    if (smooth) {
      ctx.quadraticCurveTo(previousX, previousY, (previousX + x) / 2, (previousY + y) / 2);
    } else {
      ctx.lineTo(x, y);
    }
    previousX = x;
    previousY = y;
  }
  ctx.lineTo(w, previousY);
  if (close) {
    ctx.lineTo(w, axis);
    ctx.lineTo(0, axis);
    ctx.closePath();
  }
}

function drawStereo(ctx, scene, frame, s, lut) {
  const { w, h, dpr } = scene;
  const axis = h * s.stereoAxis;
  const scale = h * s.stereoScale * 0.5;

  for (let band = 0; band < BANDS; band++) {
    scene.mix[band] = (frame.left[band] + frame.right[band]) * 0.5;
  }

  const lobes =
    s.stereoLayout === "mirror"
      ? [[scene.mix, 1], [scene.mix, -1]]
      : s.stereoLayout === "stack"
        ? [[frame.left, 1], [frame.right, 1]]
        : [[frame.left, 1], [frame.right, -1]];

  ctx.globalCompositeOperation = s.stereoLayout === "stack" ? "lighter" : "source-over";

  lobes.forEach(([data, sign], index) => {
    if (s.stereoFill) {
      traceLobe(ctx, data, axis, scale, sign, w, s.stereoSmooth, true);
      const gradient = ctx.createLinearGradient(0, axis - sign * scale, 0, axis);
      gradient.addColorStop(0, shade(lut, 0.95, index && s.stereoLayout === "stack" ? 0.55 : 1));
      gradient.addColorStop(1, shade(lut, 0.32, 0.85));
      ctx.fillStyle = gradient;
      ctx.fill();
    }
    if (s.stereoStroke > 0) {
      traceLobe(ctx, data, axis, scale, sign, w, s.stereoSmooth, false);
      ctx.lineWidth = s.stereoStroke * dpr;
      ctx.strokeStyle = shade(lut, 1, 0.8);
      ctx.stroke();
    }
  });
}

function barLevel(frame, s, index, count) {
  const half = count / 2;
  if (s.barChannel === "split") {
    const fromCentre = index < half ? half - 1 - index : index - half;
    const position = (fromCentre / Math.max(1, half - 1)) * BANDS;
    const data = index < half ? frame.left : frame.right;
    return sliceLevel(data, position, position + BANDS / half);
  }
  const from = (index / count) * BANDS;
  const to = ((index + 1) / count) * BANDS;
  if (s.barChannel === "left") return sliceLevel(frame.left, from, to);
  if (s.barChannel === "right") return sliceLevel(frame.right, from, to);
  return Math.max(sliceLevel(frame.left, from, to), sliceLevel(frame.right, from, to));
}

function drawBars(ctx, scene, frame, s, lut, dt) {
  const { w, h } = scene;
  const count = Math.round(s.barCount);
  const slot = w / count;
  const gap = slot * s.barGap;
  const width = Math.max(1, slot - gap);
  const radius = width * s.barRadius;
  const capHeight = Math.max(1, h * 0.008);
  const centred = s.barLayout === "center";
  const mirrored = s.barLayout === "mirror";
  const baseline = centred || mirrored ? h * 0.5 : h;
  const reach = (centred ? h * 0.5 : mirrored ? h * 0.5 : h) * s.barScale;

  ctx.globalCompositeOperation = "source-over";

  for (let index = 0; index < count; index++) {
    const level = clamp(barLevel(frame, s, index, count), 0, 1);
    scene.caps[index] = Math.max(level, scene.caps[index] - s.barCapFall * dt);
    const x = index * slot + gap / 2;
    const height = level * reach;
    ctx.fillStyle = shade(lut, 0.3 + level * 0.7);
    block(ctx, x, baseline - height, width, height, radius);
    if (mirrored) {
      ctx.fillStyle = shade(lut, 0.3 + level * 0.7, 0.45);
      block(ctx, x, baseline, width, height, radius);
    }
    if (centred) {
      ctx.fillStyle = shade(lut, 0.3 + level * 0.7);
      block(ctx, x, baseline, width, height, radius);
    }
    if (s.barCaps) {
      ctx.fillStyle = shade(lut, 0.98, 0.85);
      ctx.fillRect(x, baseline - scene.caps[index] * reach - capHeight, width, capHeight);
      if (mirrored || centred) {
        ctx.fillRect(x, baseline + scene.caps[index] * reach, width, capHeight);
      }
    }
  }
}

function drawSphere(ctx, scene, frame, s, lut) {
  const { w, h, dpr } = scene;
  const rings = Math.round(s.sphereRings);
  const points = Math.round(s.spherePoints);
  const radius = Math.min(w, h) * 0.5 * s.sphereRadius;
  const spin = scene.t * s.sphereSpin;
  const tumble = 0.34 + scene.t * s.sphereTilt;
  const cosSpin = Math.cos(spin);
  const sinSpin = Math.sin(spin);
  const cosTilt = Math.cos(tumble);
  const sinTilt = Math.sin(tumble);
  const camera = s.sphereFov;
  const size = s.sphereDot * dpr;

  ctx.globalCompositeOperation = "lighter";
  ctx.lineWidth = Math.max(0.5, size * 0.5);

  for (let ring = 0; ring < rings; ring++) {
    const theta = ((ring + 0.5) / rings) * Math.PI;
    const sinTheta = Math.sin(theta);
    const cosTheta = Math.cos(theta);
    const band = clamp(Math.round((ring / (rings - 1 || 1)) * (BANDS - 1)), 0, BANDS - 1);
    if (s.sphereWire) ctx.beginPath();

    for (let point = 0; point < points; point++) {
      const phi = (point / points) * TWO_PI;
      const cosPhi = Math.cos(phi);
      const channel = cosPhi >= 0 ? frame.right[band] : frame.left[band];
      const level = clamp(
        channel * 0.78 + frame.level * 0.22 + waveAt(frame.wave, point / points) * 0.08,
        0,
        1,
      );
      const push = radius * (1 + s.sphereReact * level);

      let x = sinTheta * cosPhi;
      let y = cosTheta;
      let z = sinTheta * Math.sin(phi);

      const y1 = y * cosTilt - z * sinTilt;
      const z1 = y * sinTilt + z * cosTilt;
      const x2 = x * cosSpin - z1 * sinSpin;
      const z2 = x * sinSpin + z1 * cosSpin;

      const depth = camera / (camera - z2);
      const screenX = w * 0.5 + x2 * push * depth;
      const screenY = h * 0.5 + y1 * push * depth;
      const near = clamp((z2 + 1) / 2, 0, 1);
      const alpha = clamp(1 - s.sphereDepth * (1 - near), 0.06, 1);

      if (s.sphereWire) {
        if (point === 0) ctx.moveTo(screenX, screenY);
        else ctx.lineTo(screenX, screenY);
      } else {
        const dot = Math.max(0.5, size * depth * 0.7);
        ctx.fillStyle = shade(lut, 0.45 + 0.55 * clamp(level * 1.4, 0, 1), alpha);
        ctx.fillRect(screenX - dot * 0.5, screenY - dot * 0.5, dot, dot);
      }
    }

    if (s.sphereWire) {
      ctx.closePath();
      const level = (frame.left[band] + frame.right[band]) * 0.5;
      ctx.strokeStyle = shade(lut, 0.3 + 0.7 * clamp(level * 1.4, 0, 1), 0.5);
      ctx.stroke();
    }
  }
}

function bloom(scene, amount) {
  const { ctx, layer, glow, gctx, w, h } = scene;
  const width = Math.max(1, Math.round(w * 0.32));
  const height = Math.max(1, Math.round(h * 0.32));
  if (glow.width !== width || glow.height !== height) {
    glow.width = width;
    glow.height = height;
  }
  gctx.clearRect(0, 0, width, height);
  gctx.drawImage(layer, 0, 0, width, height);
  ctx.save();
  ctx.globalCompositeOperation = "lighter";
  ctx.globalAlpha = 0.18 + amount * 0.62;
  ctx.filter = `blur(${(1.5 + amount * 9) * scene.dpr}px)`;
  ctx.drawImage(glow, 0, 0, w, h);
  ctx.restore();
}

const RENDER = {
  waves: drawWaves,
  stereo: drawStereo,
  bars: drawBars,
  sphere: drawSphere,
};

function reset(ctx) {
  ctx.setTransform(1, 0, 0, 1, 0, 0);
  ctx.globalCompositeOperation = "source-over";
  ctx.globalAlpha = 1;
  ctx.filter = "none";
}

export function paint(scene, frame, s, lut, dt) {
  if (!scene.w) return;
  const { ctx, lctx, w, h } = scene;
  scene.t += dt;

  reset(lctx);
  lctx.clearRect(0, 0, w, h);
  RENDER[s.mode](lctx, scene, frame, s, lut, dt);

  reset(ctx);
  ctx.fillStyle = s.trails > 0 ? alphaOf(s.background, Math.max(0.05, 1 - s.trails)) : s.background;
  ctx.fillRect(0, 0, w, h);
  ctx.drawImage(scene.layer, 0, 0);
  if (s.glow > 0) bloom(scene, s.glow);
}
