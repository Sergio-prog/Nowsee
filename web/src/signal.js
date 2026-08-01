export const BANDS = 96;
export const HISTORY = 420;

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
  for (let b = from; b <= to; b++) {
    const d = b / (BANDS - 1) - centre;
    target[b] += amp * Math.exp(-d * d * spread);
  }
}

export function createSignal() {
  const left = new Float32Array(BANDS);
  const right = new Float32Array(BANDS);
  const smoothL = new Float32Array(BANDS);
  const smoothR = new Float32Array(BANDS);

  const history = [];
  for (let i = 0; i < HISTORY; i++) {
    history.push({ bands: new Float32Array(BANDS), lo: 0, hi: 0, swell: 0 });
  }

  let head = 0;
  let clock = 0;
  let pushes = 0;
  let swell = 0;
  let texture = 0.8;

  function advance(dt) {
    clock += dt;
    const beat = ((clock * 108) / 60) % 1;
    const hit = Math.exp(-beat * 5.5);
    const bar = Math.exp(-(((clock * 27) / 60) % 1) * 3.2);

    left.fill(0);
    right.fill(0);

    for (const p of PARTIALS) {
      const wander =
        Math.sin(clock * p.drift) * 0.05 + Math.sin(clock * p.drift * 0.41) * 0.028;
      const breath = 0.55 + 0.45 * Math.sin(clock * p.rate + p.centre * 9);
      const amp = p.gain * (0.34 + 0.66 * breath) * (1 - p.beat * 0.55 + p.beat * hit * 1.5);
      addPeak(left, p.centre + wander, amp, p.width);
      addPeak(right, p.centre + wander * 0.62 + 0.012, amp, p.width);
    }

    const root = 0.052 + 0.016 * Math.sin(clock * 0.19) + 0.008 * Math.sin(clock * 0.53);
    for (let h = 1; h <= HARMONICS; h++) {
      const centre = root * h * (1 + 0.006 * h);
      const voice = 0.62 + 0.38 * Math.sin(clock * (0.4 + h * 0.11) + h * 1.7);
      const amp = (0.66 / Math.pow(h, 0.78)) * voice * (0.7 + 0.3 * hit);
      const width = 0.009 + 0.0035 * h;
      addPeak(left, centre, amp, width);
      addPeak(right, centre * 1.002, amp * (0.86 + 0.14 * Math.sin(clock * 0.6 + h)), width);
    }

    for (let b = 0; b < BANDS; b++) {
      const x = b / (BANDS - 1);
      const air = 0.05 * (1 - x);
      const sizzle = x > 0.5 ? 0.16 * bar * hit * noise(b + Math.floor(clock * 14)) : 0;
      left[b] = Math.min(1, Math.max(0, left[b] * 0.56 + air + sizzle));
      right[b] = Math.min(1, Math.max(0, right[b] * 0.56 + air * 0.92 + sizzle));
      smoothL[b] += (left[b] - smoothL[b]) * 0.34;
      smoothR[b] += (right[b] - smoothR[b]) * 0.34;
    }

    let energy = 0;
    for (let b = 0; b < BANDS; b++) energy += left[b] * (1 - (b / BANDS) * 0.55);
    energy = Math.min(1, (energy / BANDS) * 6.4);

    pushes++;
    swell += (energy - swell) * 0.14;
    const grain = 0.55 + 0.45 * noise(pushes);
    texture += (grain - texture) * 0.55;

    head = (head + 1) % HISTORY;
    const slot = history[head];
    slot.bands.set(left);
    slot.swell = swell;
    slot.hi = energy * texture;
    slot.lo = -energy * (0.45 + 0.55 * (0.55 + 0.45 * noise(pushes + 7331)));
  }

  return {
    advance,
    smoothL,
    smoothR,
    column: (back) => history[(head - back + HISTORY * 2) % HISTORY],
  };
}
