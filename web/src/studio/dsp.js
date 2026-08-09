export const BANDS = 128;
export const WAVE = 512;

const FLOOR_DB = -85;
const SPAN_DB = 80;
const PEAK_TAU = 0.27;

export function clamp(value, low, high) {
  return value < low ? low : value > high ? high : value;
}

export function buildMap(binCount, sampleRate, lowHz, highHz) {
  const hzPerBin = sampleRate / 2 / binCount;
  const top = Math.min(highHz, sampleRate / 2);
  const bottom = Math.min(lowHz, top / 2);
  const ratio = top / bottom;
  const ranges = new Int32Array(BANDS * 2);
  for (let band = 0; band < BANDS; band++) {
    const low = bottom * Math.pow(ratio, band / BANDS);
    const high = bottom * Math.pow(ratio, (band + 1) / BANDS);
    const from = clamp(Math.floor(low / hzPerBin), 0, binCount - 1);
    const to = clamp(Math.ceil(high / hzPerBin), from + 1, binCount);
    ranges[band * 2] = from;
    ranges[band * 2 + 1] = to;
  }
  return { ranges, sampleRate, lowHz: bottom, highHz: top, binCount };
}

export function foldDecibels(magnitudes, map, target) {
  const { ranges } = map;
  for (let band = 0; band < BANDS; band++) {
    let peak = -Infinity;
    for (let bin = ranges[band * 2]; bin < ranges[band * 2 + 1]; bin++) {
      const value = magnitudes[bin];
      if (value > peak) peak = value;
    }
    target[band] = clamp((peak - FLOOR_DB) / SPAN_DB, 0, 1);
  }
}

export function createSmoother() {
  const level = new Float32Array(BANDS);
  const peak = new Float32Array(BANDS);
  const shaped = new Float32Array(BANDS);
  let kernel = new Float32Array([1]);
  let kernelFor = -1;

  function rebuild(smoothing) {
    if (smoothing === kernelFor) return;
    kernelFor = smoothing;
    const radius = Math.round(smoothing * 12);
    if (radius <= 0) {
      kernel = new Float32Array([1]);
      return;
    }
    const sigma = Math.max(0.6, smoothing * 6);
    const weights = new Float32Array(radius * 2 + 1);
    let total = 0;
    for (let tap = -radius; tap <= radius; tap++) {
      const weight = Math.exp(-(tap * tap) / (2 * sigma * sigma));
      weights[tap + radius] = weight;
      total += weight;
    }
    for (let i = 0; i < weights.length; i++) weights[i] /= total;
    kernel = weights;
  }

  function spread(source) {
    if (kernel.length < 2) {
      shaped.set(source);
      return shaped;
    }
    const radius = kernel.length >> 1;
    for (let band = 0; band < BANDS; band++) {
      let total = 0;
      for (let tap = 0; tap < kernel.length; tap++) {
        total += source[clamp(band + tap - radius, 0, BANDS - 1)] * kernel[tap];
      }
      shaped[band] = total;
    }
    return shaped;
  }

  return {
    level,
    peak,
    blend(target, dt, smoothing, gain, gate) {
      rebuild(smoothing);
      const step = clamp(dt, 0, 0.25);
      const attack = 1 - Math.exp(-step / (0.02 + smoothing * 0.085));
      const release = 1 - Math.exp(-step / (0.11 + smoothing * 0.215));
      const fall = Math.exp(-step / PEAK_TAU);
      const source = spread(target);
      for (let band = 0; band < BANDS; band++) {
        const raw = source[band] * gain;
        const wanted = raw < gate ? 0 : clamp((raw - gate) / (1 - gate), 0, 1);
        const previous = level[band];
        level[band] = previous + (wanted - previous) * (wanted > previous ? attack : release);
        peak[band] = Math.max(peak[band] * fall, level[band]);
      }
    },
    reset() {
      level.fill(0);
      peak.fill(0);
    },
  };
}
