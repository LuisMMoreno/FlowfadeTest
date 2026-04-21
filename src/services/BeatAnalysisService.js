const DEFAULT_BPM = 120;
const DEFAULT_CONFIDENCE = 0.25;
const BPM_MIN = 80;
const BPM_MAX = 160;
const ANALYSIS_TIMEOUT_MS = 1800;

const COMMON_BPM_CANDIDATES = [90, 96, 100, 105, 110, 115, 120, 124, 126, 128, 130, 135, 140];

const clamp = (value, min, max) => Math.min(max, Math.max(min, value));

const normalizeBpm = (bpm) => {
  let normalized = bpm;

  while (normalized < BPM_MIN) normalized *= 2;
  while (normalized > BPM_MAX) normalized /= 2;

  return clamp(normalized, BPM_MIN, BPM_MAX);
};

const nearestCommonBpm = (value) => COMMON_BPM_CANDIDATES.reduce((closest, current) => (
  Math.abs(current - value) < Math.abs(closest - value) ? current : closest
), COMMON_BPM_CANDIDATES[0]);

const createBeatGrid = (bpm, duration, offset = 0) => {
  const beatDuration = 60 / bpm;
  const barDuration = beatDuration * 4;
  const beatCount = Math.max(1, Math.floor(Math.max(duration, beatDuration) / beatDuration));
  const barCount = Math.max(1, Math.floor(Math.max(duration, barDuration) / barDuration));

  return {
    beatDuration,
    barDuration,
    offset,
    beatCount,
    barCount
  };
};

const createFallbackAnalysis = (song, reason = 'heuristic') => {
  const duration = Number(song?.duration) || 0;
  const seededValue = duration > 0
    ? nearestCommonBpm(96 + ((Math.round(duration) % 44)))
    : DEFAULT_BPM;
  const bpm = normalizeBpm(seededValue);

  return {
    songId: song?.id ?? null,
    bpm,
    confidence: DEFAULT_CONFIDENCE,
    source: reason,
    duration,
    estimatedDownbeatOffset: 0,
    beatGrid: createBeatGrid(bpm, duration, 0),
    analyzedAt: Date.now()
  };
};

const withTimeout = async (promise, timeoutMs) => {
  let timeoutId = null;

  try {
    return await Promise.race([
      promise,
      new Promise((_, reject) => {
        timeoutId = setTimeout(() => reject(new Error('analysis-timeout')), timeoutMs);
      })
    ]);
  } finally {
    if (timeoutId) clearTimeout(timeoutId);
  }
};

class BeatAnalysisService {
  constructor() {
    this.analysisCache = new Map();
    this.pendingCache = new Map();
  }

  getTrackKey(song) {
    return song?.id ?? song?.url ?? song?.fileName ?? null;
  }

  getCachedAnalysis(song) {
    const key = this.getTrackKey(song);
    return key ? this.analysisCache.get(key) ?? null : null;
  }

  async analyzeTrack(song, blob, options = {}) {
    const key = this.getTrackKey(song);
    if (!key) {
      return createFallbackAnalysis(song, 'missing-key');
    }

    if (this.analysisCache.has(key)) {
      return this.analysisCache.get(key);
    }

    if (this.pendingCache.has(key)) {
      return this.pendingCache.get(key);
    }

    const analysisPromise = withTimeout(
      this.runAnalysis(song, blob, options).catch((error) => {
        console.warn('[BeatAnalysisService] Fallback heuristic:', error);
        return createFallbackAnalysis(song, 'fallback');
      }),
      options.timeoutMs ?? ANALYSIS_TIMEOUT_MS
    )
      .then((analysis) => {
        this.analysisCache.set(key, analysis);
        this.pendingCache.delete(key);
        return analysis;
      })
      .catch(() => {
        const fallback = createFallbackAnalysis(song, 'timeout');
        this.analysisCache.set(key, fallback);
        this.pendingCache.delete(key);
        return fallback;
      });

    this.pendingCache.set(key, analysisPromise);
    return analysisPromise;
  }

  async runAnalysis(song, blob) {
    if (!blob) {
      return createFallbackAnalysis(song, 'missing-blob');
    }

    const arrayBuffer = await blob.arrayBuffer();
    const audioBuffer = await this.decodeAudioData(arrayBuffer);
    const peakData = this.extractPeakData(audioBuffer);

    if (!peakData.tempoCandidates.length) {
      return createFallbackAnalysis(song, 'insufficient-peaks');
    }

    const bestCandidate = peakData.tempoCandidates[0];
    const bpm = normalizeBpm(bestCandidate.bpm);
    const duration = Number.isFinite(audioBuffer.duration) ? audioBuffer.duration : Number(song?.duration) || 0;
    const beatDuration = 60 / bpm;
    const offset = peakData.firstPeakTime > 0 ? peakData.firstPeakTime % beatDuration : 0;
    const totalWeight = peakData.tempoCandidates.reduce((sum, candidate) => sum + candidate.weight, 0) || bestCandidate.weight;
    const confidence = clamp(bestCandidate.weight / totalWeight, 0.2, 0.98);

    return {
      songId: song?.id ?? null,
      bpm,
      confidence,
      source: 'decoded-peaks',
      duration,
      estimatedDownbeatOffset: offset,
      beatGrid: createBeatGrid(bpm, duration, offset),
      analyzedAt: Date.now()
    };
  }

  async decodeAudioData(arrayBuffer) {
    const AudioCtx = window.AudioContext || window.webkitAudioContext;
    if (!AudioCtx) {
      throw new Error('AudioContext not available');
    }

    const context = new AudioCtx();

    try {
      const decoded = await context.decodeAudioData(arrayBuffer.slice(0));
      return decoded;
    } finally {
      if (typeof context.close === 'function') {
        try {
          await context.close();
        } catch (error) {
          console.warn('[BeatAnalysisService] Could not close analysis context:', error);
        }
      }
    }
  }

  extractPeakData(audioBuffer) {
    const channelCount = audioBuffer.numberOfChannels;
    const sampleRate = audioBuffer.sampleRate;
    const duration = audioBuffer.duration;
    const maxAnalysisSeconds = Math.min(duration, 90);
    const usableLength = Math.floor(maxAnalysisSeconds * sampleRate);

    if (!usableLength || !channelCount) {
      return { tempoCandidates: [], firstPeakTime: 0 };
    }

    const mono = new Float32Array(usableLength);
    for (let channel = 0; channel < channelCount; channel += 1) {
      const source = audioBuffer.getChannelData(channel);
      for (let i = 0; i < usableLength; i += 1) {
        mono[i] += source[i] / channelCount;
      }
    }

    const envelopeWindow = 1024;
    const envelopeLength = Math.floor(usableLength / envelopeWindow);
    if (!envelopeLength) {
      return { tempoCandidates: [], firstPeakTime: 0 };
    }

    const envelope = new Float32Array(envelopeLength);
    for (let index = 0; index < envelopeLength; index += 1) {
      let energy = 0;
      const start = index * envelopeWindow;
      const end = Math.min(start + envelopeWindow, usableLength);

      for (let i = start; i < end; i += 1) {
        const sample = mono[i];
        energy += sample * sample;
      }

      envelope[index] = Math.sqrt(energy / Math.max(1, end - start));
    }

    let mean = 0;
    for (let i = 0; i < envelope.length; i += 1) {
      mean += envelope[i];
    }
    mean /= envelope.length;

    let variance = 0;
    for (let i = 0; i < envelope.length; i += 1) {
      const diff = envelope[i] - mean;
      variance += diff * diff;
    }
    variance /= envelope.length;

    const deviation = Math.sqrt(variance);
    const threshold = mean + deviation * 1.15;
    const minSpacingSeconds = 0.25;
    const minSpacingFrames = Math.max(1, Math.floor((minSpacingSeconds * sampleRate) / envelopeWindow));
    const peaks = [];

    let lastPeakFrame = -minSpacingFrames;
    for (let i = 1; i < envelope.length - 1; i += 1) {
      const current = envelope[i];
      if (current < threshold) continue;
      if (current <= envelope[i - 1] || current < envelope[i + 1]) continue;
      if ((i - lastPeakFrame) < minSpacingFrames) continue;

      peaks.push({
        time: (i * envelopeWindow) / sampleRate,
        weight: current
      });
      lastPeakFrame = i;
    }

    if (peaks.length < 8) {
      return { tempoCandidates: [], firstPeakTime: peaks[0]?.time ?? 0 };
    }

    const histogram = new Map();
    for (let i = 0; i < peaks.length; i += 1) {
      const current = peaks[i];
      for (let j = i + 1; j < Math.min(i + 10, peaks.length); j += 1) {
        const interval = peaks[j].time - current.time;
        if (interval <= 0.3 || interval >= 1.6) continue;

        const bpm = normalizeBpm(60 / interval);
        const bucket = Math.round(bpm);
        const weight = current.weight + peaks[j].weight;
        histogram.set(bucket, (histogram.get(bucket) ?? 0) + weight);
      }
    }

    const tempoCandidates = [...histogram.entries()]
      .map(([bpm, weight]) => ({ bpm: Number(bpm), weight }))
      .sort((a, b) => b.weight - a.weight)
      .slice(0, 5);

    return {
      tempoCandidates,
      firstPeakTime: peaks[0]?.time ?? 0
    };
  }
}

export const beatAnalysisService = new BeatAnalysisService();
export { createFallbackAnalysis };
