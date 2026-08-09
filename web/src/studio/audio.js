import { BANDS, WAVE, buildMap, clamp, createSmoother, foldDecibels } from "./dsp.js";
import { createDemo } from "./demo.js";

const FFT_SIZE = 2048;

export function createEngine() {
  const demo = createDemo();
  const smootherL = createSmoother();
  const smootherR = createSmoother();
  const rawL = new Float32Array(BANDS);
  const rawR = new Float32Array(BANDS);
  const spectrum = new Float32Array(FFT_SIZE / 2);
  const timeDomain = new Float32Array(FFT_SIZE);

  const frame = {
    left: smootherL.level,
    right: smootherR.level,
    peakL: smootherL.peak,
    peakR: smootherR.peak,
    wave: new Float32Array(WAVE),
    levelL: 0,
    levelR: 0,
    level: 0,
    bass: 0,
    mid: 0,
    treble: 0,
  };

  const status = { kind: "demo", label: "Demo signal", detail: "Synthetic", error: "" };

  const media = new Audio();
  media.loop = true;
  media.crossOrigin = "anonymous";

  let context = null;
  let analyserL = null;
  let analyserR = null;
  let splitter = null;
  let node = null;
  let stream = null;
  let mediaNode = null;
  let map = null;
  let mapKey = "";

  function teardown() {
    if (node) {
      node.disconnect();
      node = null;
    }
    if (stream) {
      stream.getTracks().forEach((track) => track.stop());
      stream = null;
    }
    if (status.kind === "file") media.pause();
  }

  async function ensureContext() {
    if (!context) {
      context = new (window.AudioContext || window.webkitAudioContext)();
      splitter = context.createChannelSplitter(2);
      analyserL = context.createAnalyser();
      analyserR = context.createAnalyser();
      for (const analyser of [analyserL, analyserR]) {
        analyser.fftSize = FFT_SIZE;
        analyser.smoothingTimeConstant = 0;
      }
      splitter.connect(analyserL, 0);
      splitter.connect(analyserR, 1);
    }
    if (context.state === "suspended") await context.resume();
    return context;
  }

  function connect(source) {
    node = source;
    node.connect(splitter);
  }

  async function useMicrophone() {
    stream = await navigator.mediaDevices.getUserMedia({
      audio: { echoCancellation: false, noiseSuppression: false, autoGainControl: false },
    });
    await ensureContext();
    connect(context.createMediaStreamSource(stream));
    const track = stream.getAudioTracks()[0];
    status.detail = track ? track.label || "Default input" : "Input";
  }

  async function useTab() {
    if (!navigator.mediaDevices.getDisplayMedia) {
      throw new Error("This browser cannot share tab audio. Chrome or Edge can.");
    }
    stream = await navigator.mediaDevices.getDisplayMedia({ video: true, audio: true });
    stream.getVideoTracks().forEach((track) => {
      track.stop();
      stream.removeTrack(track);
    });
    if (!stream.getAudioTracks().length) {
      throw new Error("That share had no audio. Tick “Share audio” in the picker and retry.");
    }
    await ensureContext();
    connect(context.createMediaStreamSource(stream));
    status.detail = "Shared tab";
    stream.getAudioTracks()[0].addEventListener("ended", async () => {
      await setSource("demo");
      engine.onstatus?.();
    });
  }

  async function useFile(file) {
    if (!file) throw new Error("Pick an audio file to play.");
    await ensureContext();
    media.src = URL.createObjectURL(file);
    if (!mediaNode) mediaNode = context.createMediaElementSource(media);
    mediaNode.connect(context.destination);
    connect(mediaNode);
    await media.play();
    status.detail = file.name;
  }

  async function setSource(kind, payload) {
    teardown();
    status.error = "";
    try {
      if (kind === "mic") await useMicrophone();
      else if (kind === "tab") await useTab();
      else if (kind === "file") await useFile(payload);
      else status.detail = "Synthetic";
      status.kind = kind;
    } catch (error) {
      teardown();
      status.kind = "demo";
      status.detail = "Synthetic";
      status.error = error?.message || "That source is not available.";
    }
    smootherL.reset();
    smootherR.reset();
    frame.wave.fill(0);
    return status;
  }

  function readChannel(analyser, target) {
    analyser.getFloatFrequencyData(spectrum);
    foldDecibels(spectrum, map, target);
  }

  function readWave(analyser) {
    analyser.getFloatTimeDomainData(timeDomain);
    const stride = timeDomain.length / WAVE;
    for (let i = 0; i < WAVE; i++) frame.wave[i] = timeDomain[Math.floor(i * stride)];
  }

  function summarise() {
    let sumL = 0;
    let sumR = 0;
    let bass = 0;
    let mid = 0;
    let treble = 0;
    const third = BANDS / 3;
    for (let band = 0; band < BANDS; band++) {
      const value = (frame.left[band] + frame.right[band]) * 0.5;
      sumL += frame.left[band];
      sumR += frame.right[band];
      if (band < third) bass += value;
      else if (band < third * 2) mid += value;
      else treble += value;
    }
    frame.levelL = clamp(sumL / BANDS, 0, 1);
    frame.levelR = clamp(sumR / BANDS, 0, 1);
    frame.level = (frame.levelL + frame.levelR) * 0.5;
    frame.bass = clamp(bass / third, 0, 1);
    frame.mid = clamp(mid / third, 0, 1);
    frame.treble = clamp(treble / third, 0, 1);
  }

  function update(dt, settings) {
    const live = status.kind !== "demo" && context && node;
    if (live) {
      const key = `${context.sampleRate}:${settings.lowHz}:${settings.highHz}`;
      if (key !== mapKey) {
        map = buildMap(spectrum.length, context.sampleRate, settings.lowHz, settings.highHz);
        mapKey = key;
      }
      readChannel(analyserL, rawL);
      readChannel(analyserR, rawR);
      readWave(analyserL);
    } else {
      demo.advance(dt);
      const span = Math.log(settings.highHz / settings.lowHz) / Math.log(16000 / 30);
      const shift = Math.log(settings.lowHz / 30) / Math.log(16000 / 30);
      for (let band = 0; band < BANDS; band++) {
        const source = clamp(shift + (band / (BANDS - 1)) * span, 0, 1) * (BANDS - 1);
        const index = Math.round(source);
        rawL[band] = demo.left[index];
        rawR[band] = demo.right[index];
      }
      frame.wave.set(demo.wave);
    }

    smootherL.blend(rawL, dt, settings.smoothing, settings.gain, settings.floor);
    smootherR.blend(rawR, dt, settings.smoothing, settings.gain, settings.floor);
    summarise();
  }

  const engine = { frame, status, media, update, setSource, onstatus: null };
  return engine;
}
