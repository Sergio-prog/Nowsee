import { BANDS, WAVE, clamp } from "./dsp.js";

const HARMONICS = 15;

const PARTIALS = [
  { centre: 0.04, width: 0.045, gain: 1.0, drift: 0.31, rate: 0.44, beat: 1.0 },
  { centre: 0.26, width: 0.075, gain: 0.5, drift: 0.83, rate: 0.27, beat: 0.3 },
  { centre: 0.52, width: 0.095, gain: 0.34, drift: 1.27, rate: 0.61, beat: 0.1 },
  { centre: 0.78, width: 0.13, gain: 0.22, drift: 1.91, rate: 0.38, beat: 0.05 },
];

function noise(n) {
  const s = Math.sin(n * 127.1 + 31.7) * 43758.5453;
  return s - Math.floor(s);
}

function addPeak(target, centre, amp, width) {
  if (centre > 1.04 || amp < 0.004) return;
  const spread = 1 / (2 * width * width);
  const from = Math.max(0, Math.floor((centre - width * 3) * (BANDS - 1)));
  const to = Math.min(BANDS - 1, Math.ceil((centre + width * 3) * (BANDS - 1)));
  for (let band = from; band <= to; band++) {
    const distance = band / (BANDS - 1) - centre;
    target[band] += amp * Math.exp(-distance * distance * spread);
  }
}

export function createDemo() {
  const left = new Float32Array(BANDS);
  const right = new Float32Array(BANDS);
  const wave = new Float32Array(WAVE);
  let clock = 0;

  function advance(dt) {
    clock += dt;
    const beat = ((clock * 108) / 60) % 1;
    const hit = Math.exp(-beat * 5.5);
    const bar = Math.exp(-(((clock * 27) / 60) % 1) * 3.2);

    left.fill(0);
    right.fill(0);

    for (const partial of PARTIALS) {
      const wander =
        Math.sin(clock * partial.drift) * 0.05 + Math.sin(clock * partial.drift * 0.41) * 0.028;
      const breath = 0.55 + 0.45 * Math.sin(clock * partial.rate + partial.centre * 9);
      const amp =
        partial.gain * (0.34 + 0.66 * breath) * (1 - partial.beat * 0.55 + partial.beat * hit * 1.5);
      addPeak(left, partial.centre + wander, amp, partial.width);
      addPeak(right, partial.centre + wander * 0.62 + 0.012, amp, partial.width);
    }

    const root = 0.052 + 0.016 * Math.sin(clock * 0.19) + 0.008 * Math.sin(clock * 0.53);
    for (let harmonic = 1; harmonic <= HARMONICS; harmonic++) {
      const centre = root * harmonic * (1 + 0.006 * harmonic);
      const voice = 0.62 + 0.38 * Math.sin(clock * (0.4 + harmonic * 0.11) + harmonic * 1.7);
      const amp = (0.66 / Math.pow(harmonic, 0.78)) * voice * (0.7 + 0.3 * hit);
      const width = 0.009 + 0.0035 * harmonic;
      addPeak(left, centre, amp, width);
      addPeak(
        right,
        centre * 1.002,
        amp * (0.86 + 0.14 * Math.sin(clock * 0.6 + harmonic)),
        width,
      );
    }

    for (let band = 0; band < BANDS; band++) {
      const position = band / (BANDS - 1);
      const air = 0.05 * (1 - position);
      const sizzle =
        position > 0.5 ? 0.16 * bar * hit * noise(band + Math.floor(clock * 14)) : 0;
      left[band] = clamp(left[band] * 0.56 + air + sizzle, 0, 1);
      right[band] = clamp(right[band] * 0.56 + air * 0.92 + sizzle, 0, 1);
    }

    for (let i = 0; i < WAVE; i++) {
      const phase = (i / WAVE) * Math.PI * 2;
      let sample = 0;
      for (let harmonic = 1; harmonic <= 7; harmonic++) {
        const amp = (0.62 / Math.pow(harmonic, 0.9)) * (0.6 + 0.4 * Math.sin(clock * (0.7 + harmonic * 0.23)));
        sample += amp * Math.sin(phase * harmonic * 3 + clock * (2.1 + harmonic * 0.37));
      }
      const grain = (noise(i + Math.floor(clock * 30)) - 0.5) * 0.14 * hit;
      wave[i] = clamp((sample * 0.28 + grain) * (0.45 + 0.55 * hit), -1, 1);
    }
  }

  return { left, right, wave, advance };
}
