import { AudioStorageService } from './AudioStorageService';
import { beatAnalysisService, createFallbackAnalysis } from './BeatAnalysisService';

const EPSILON_VOLUME = 0.001;
const PROGRESS_EVENT = 'flowfade:playback-progress';
const MAX_BEATMATCH_RATE_DELTA = 0.06;
const CROSSFADE_MIN_SECONDS = 5;
const CROSSFADE_MAX_SECONDS = 8;
const RATE_RESET_TOLERANCE = 0.001;

const clamp = (value, min, max) => Math.min(max, Math.max(min, value));
const now = () => (typeof performance !== 'undefined' ? performance.now() : Date.now());
const isIOS = () => /iPad|iPhone|iPod/.test(navigator.userAgent) && !window.MSStream;

/**
 * Motor de audio orientado a iOS background:
 * - HTMLAudioElement persistente como salida audible principal.
 * - Web Audio API solo para analisis en foreground cuando es seguro.
 * - Metadatos de mezcla por pista para auto-mix sincronizado a barras.
 */
class AudioEngine {
  constructor() {
    this.audioElements = [];
    this.objectUrls = [null, null];
    this.slotVolumes = [0, 0];
    this.currentIndex = -1;
    this.crossfadeDuration = 5;
    this.isPlaying = false;
    this.currentSongId = null;
    this.masterVolume = 1;
    this.isInitialized = false;

    this.loadRequestId = 0;
    this.activePlaybackId = 0;
    this.pausedSlots = [];
    this.fadeInterval = null;
    this.almostEndedTimeout = null;
    this.almostEndedFired = false;
    this.onEndedCallback = null;
    this.onAlmostEndedCallback = null;
    this.analysisRequestId = 0;

    // Metadatos de mezcla
    this.trackAnalysis = new Map();
    this.slotTrackIds = [null, null];
    this.slotPlaybackRates = [1, 1];
    this.currentMixState = this.createInitialMixState();

    // Analyser (opcional, solo foreground en no-iOS)
    this.audioContext = null;
    this.analyserNode = null;
    this.analyserGainNode = null;
    this.sourceNodes = [null, null];
    this.isAnalyserActive = false;
  }

  createInitialMixState() {
    return {
      status: 'idle',
      currentSongId: null,
      incomingSongId: null,
      outgoingSongId: null,
      currentBpm: null,
      targetBpm: null,
      playbackRate: 1,
      incomingPlaybackRate: 1,
      crossfadeDuration: this.crossfadeDuration,
      crossfadeWindow: null,
      phaseAligned: false,
      confidence: 0,
      analyserActive: false,
      updatedAt: Date.now()
    };
  }

  createAudioElement(index) {
    const audio = new Audio();
    audio.preload = 'auto';
    audio.loop = false;
    audio.playsInline = true;
    audio.setAttribute('playsinline', 'true');
    audio.setAttribute('webkit-playsinline', 'true');
    audio.volume = EPSILON_VOLUME;
    audio.playbackRate = 1;
    audio.defaultPlaybackRate = 1;
    audio.preservesPitch = true;
    audio.webkitPreservesPitch = true;
    audio.mozPreservesPitch = true;

    const emitProgress = () => {
      if (index !== this.currentIndex) return;
      window.dispatchEvent(new CustomEvent(PROGRESS_EVENT, {
        detail: this.getPlaybackSnapshot()
      }));
      
      const audio = this.audioElements[index];
      if (audio && audio.duration > 0 && !audio.paused && !this.almostEndedFired && this.onAlmostEndedCallback) {
        const analysis = this.getCurrentTrackAnalysis();
        const crossfadeStart = this.getAlignedCrossfadeStart(audio, analysis);
        if (audio.currentTime >= crossfadeStart) {
          this.almostEndedFired = true;
          this.onAlmostEndedCallback();
        }
      }
    };

    audio.addEventListener('timeupdate', emitProgress);
    audio.addEventListener('loadedmetadata', emitProgress);
    audio.addEventListener('play', emitProgress);
    audio.addEventListener('pause', emitProgress);
    audio.addEventListener('seeking', emitProgress);
    audio.addEventListener('seeked', emitProgress);
    audio.addEventListener('ended', emitProgress);

    return audio;
  }

  async initialize() {
    if (this.isInitialized) return;

    this.audioElements = [this.createAudioElement(0), this.createAudioElement(1)];
    this.isInitialized = true;
  }

  getProgressEventName() {
    return PROGRESS_EVENT;
  }

  clearAlmostEndedTimeout() {
    this.almostEndedFired = false;
    if (this.almostEndedTimeout) {
      clearTimeout(this.almostEndedTimeout);
      this.almostEndedTimeout = null;
    }
  }

  clearFadeInterval() {
    if (this.fadeInterval) {
      clearInterval(this.fadeInterval);
      this.fadeInterval = null;
    }
  }

  revokeObjectUrl(index) {
    if (this.objectUrls[index]) {
      URL.revokeObjectURL(this.objectUrls[index]);
      this.objectUrls[index] = null;
    }
  }

  updateElementVolume(index) {
    const audio = this.audioElements[index];
    if (!audio) return;

    const volume = clamp(this.slotVolumes[index] * this.masterVolume, 0, 1);
    audio.volume = volume;
  }

  setSlotVolume(index, value) {
    this.slotVolumes[index] = clamp(value, 0, 1);
    this.updateElementVolume(index);
  }

  setPlaybackRate(index, value) {
    const audio = this.audioElements[index];
    if (!audio) return;

    const rate = clamp(value, 1 - MAX_BEATMATCH_RATE_DELTA, 1 + MAX_BEATMATCH_RATE_DELTA);
    audio.playbackRate = rate;
    audio.defaultPlaybackRate = rate;
    audio.preservesPitch = true;
    audio.webkitPreservesPitch = true;
    audio.mozPreservesPitch = true;
    this.slotPlaybackRates[index] = rate;
  }

  emitProgress() {
    window.dispatchEvent(new CustomEvent(PROGRESS_EVENT, {
      detail: this.getPlaybackSnapshot()
    }));
  }

  setMixState(nextState) {
    this.currentMixState = {
      ...this.currentMixState,
      ...nextState,
      analyserActive: this.isAnalyserActive,
      updatedAt: Date.now()
    };
  }

  cacheTrackAnalysis(song, analysis) {
    if (!song?.id || !analysis) return;
    this.trackAnalysis.set(song.id, analysis);
  }

  getTrackAnalysis(songId) {
    if (songId == null) return null;
    return this.trackAnalysis.get(songId) ?? null;
  }

  getCurrentTrackAnalysis() {
    return this.getTrackAnalysis(this.currentSongId);
  }

  getMixState() {
    return {
      ...this.currentMixState,
      slots: this.audioElements.map((audio, index) => ({
        index,
        songId: this.slotTrackIds[index],
        volume: this.slotVolumes[index],
        playbackRate: this.slotPlaybackRates[index],
        currentTime: audio?.currentTime ?? 0,
        isReady: Boolean(audio?.src)
      }))
    };
  }

  resetSlot(index) {
    const audio = this.audioElements[index];
    if (!audio) return;

    audio.onended = null;

    try {
      audio.pause();
    } catch (error) {
      console.warn('[AudioEngine] No se pudo pausar el slot.', error);
    }

    audio.removeAttribute('src');
    audio.load();
    this.revokeObjectUrl(index);
    this.setSlotVolume(index, 0);
    this.setPlaybackRate(index, 1);
    this.slotTrackIds[index] = null;
  }

  async prepareSlot(index, song, requestId, blob) {
    const audio = this.audioElements[index];
    const resolvedBlob = blob ?? await AudioStorageService.getAudioBlob(song.url);

    if (requestId !== this.loadRequestId) {
      return null;
    }

    const objectUrl = URL.createObjectURL(resolvedBlob);
    this.resetSlot(index);
    this.objectUrls[index] = objectUrl;
    this.slotTrackIds[index] = song.id ?? null;
    audio.src = objectUrl;

    await new Promise((resolve, reject) => {
      const handleLoaded = () => {
        cleanup();
        resolve();
      };

      const handleError = () => {
        cleanup();
        reject(new Error(`No se pudo cargar el audio para "${song.title}".`));
      };

      const cleanup = () => {
        audio.removeEventListener('loadedmetadata', handleLoaded);
        audio.removeEventListener('canplay', handleLoaded);
        audio.removeEventListener('error', handleError);
      };

      audio.addEventListener('loadedmetadata', handleLoaded, { once: true });
      audio.addEventListener('canplay', handleLoaded, { once: true });
      audio.addEventListener('error', handleError, { once: true });
      audio.load();
    });

    if (requestId !== this.loadRequestId) {
      this.resetSlot(index);
      return null;
    }

    audio.currentTime = 0;
    return audio;
  }

  async ensureTrackAnalysis(song, blob, options = {}) {
    const fallback = createFallbackAnalysis(song, 'engine-fallback');
    if (!song) return fallback;

    const existing = this.getTrackAnalysis(song.id);
    if (existing) return existing;

    try {
      const analysis = await beatAnalysisService.analyzeTrack(song, blob, options);
      this.cacheTrackAnalysis(song, analysis);
      return analysis;
    } catch (error) {
      console.warn('[AudioEngine] Falling back to heuristic BPM analysis:', error);
      this.cacheTrackAnalysis(song, fallback);
      return fallback;
    }
  }

  getCrossfadeDurationForAnalysis(analysis) {
    const desired = Number.isFinite(this.crossfadeDuration) ? this.crossfadeDuration : CROSSFADE_MIN_SECONDS;
    const bounded = clamp(desired, CROSSFADE_MIN_SECONDS, CROSSFADE_MAX_SECONDS);
    const barDuration = analysis?.beatGrid?.barDuration;

    if (!Number.isFinite(barDuration) || barDuration <= 0) {
      return bounded;
    }

    const bars = Math.max(1, Math.round(bounded / barDuration));
    return clamp(bars * barDuration, CROSSFADE_MIN_SECONDS, CROSSFADE_MAX_SECONDS);
  }

  getAlignedCrossfadeStart(audio, analysis) {
    const duration = Number.isFinite(audio?.duration) ? audio.duration : 0;
    const barDuration = analysis?.beatGrid?.barDuration;
    const offset = analysis?.beatGrid?.offset ?? 0;
    const crossfadeWindow = this.getCrossfadeDurationForAnalysis(analysis);

    if (!duration || !Number.isFinite(barDuration) || barDuration <= 0) {
      return Math.max(0, duration - crossfadeWindow);
    }

    const desiredStart = Math.max(0, duration - crossfadeWindow);
    if (desiredStart <= offset) return offset;

    const barsSinceOffset = Math.floor((desiredStart - offset) / barDuration);
    const alignedStart = offset + (barsSinceOffset * barDuration);
    return clamp(alignedStart, 0, Math.max(0, duration - 0.25));
  }

  scheduleTrackCallbacks(audio, playbackId) {
    this.clearAlmostEndedTimeout();

    const duration = Number.isFinite(audio.duration) ? audio.duration : 0;
    const analysis = this.getCurrentTrackAnalysis();
    const crossfadeStart = this.getAlignedCrossfadeStart(audio, analysis);

    audio.onended = () => {
      if (playbackId !== this.activePlaybackId) return;

      this.isPlaying = false;
      this.setMixState({
        status: 'ended',
        currentSongId: this.currentSongId,
        currentBpm: analysis?.bpm ?? null,
        playbackRate: this.slotPlaybackRates[this.currentIndex] ?? 1,
        incomingSongId: null,
        outgoingSongId: null,
        crossfadeWindow: null,
        phaseAligned: false
      });
      this.emitProgress();

      if (this.onEndedCallback) {
        this.onEndedCallback();
      }
    };

    // El evento 'onAlmostEndedCallback' ahora se evalúa continuamente dentro de 'emitProgress'
    // asociado al evento nativo 'timeupdate', para ser preciso y funcionar con la app en background en iOS.
  }

  buildBeatmatchPlan(outgoingAnalysis, incomingAnalysis) {
    const targetBpm = outgoingAnalysis?.bpm ?? incomingAnalysis?.bpm ?? null;
    const incomingBpm = incomingAnalysis?.bpm ?? targetBpm ?? null;
    const confidence = Math.min(outgoingAnalysis?.confidence ?? 0.25, incomingAnalysis?.confidence ?? 0.25);

    if (!targetBpm || !incomingBpm || confidence < 0.18) {
      return {
        incomingRate: 1,
        targetBpm,
        confidence,
        phaseAligned: false
      };
    }

    const rawRate = targetBpm / incomingBpm;
    const incomingRate = clamp(rawRate, 1 - MAX_BEATMATCH_RATE_DELTA, 1 + MAX_BEATMATCH_RATE_DELTA);

    return {
      incomingRate,
      targetBpm,
      confidence,
      phaseAligned: Math.abs(incomingRate - rawRate) <= 0.015
    };
  }

  async play(song, crossfade = false) {
    await this.initialize();

    const requestId = ++this.loadRequestId;
    const analysisRequestId = ++this.analysisRequestId;
    const nextIndex = this.currentIndex === -1 ? 0 : (this.currentIndex + 1) % 2;
    const previousIndex = this.currentIndex;
    const playbackBlob = await AudioStorageService.getAudioBlob(song.url);
    const nextAnalysisPromise = this.ensureTrackAnalysis(song, playbackBlob);
    const nextAudio = await this.prepareSlot(nextIndex, song, requestId, playbackBlob);

    if (!nextAudio || requestId !== this.loadRequestId) {
      return false;
    }

    const nextAnalysis = await nextAnalysisPromise;
    if (analysisRequestId !== this.analysisRequestId) {
      return false;
    }

    const playbackId = ++this.activePlaybackId;
    const outgoingAnalysis = this.getTrackAnalysis(this.currentSongId);
    const crossfadeWindow = this.getCrossfadeDurationForAnalysis(nextAnalysis);
    this.crossfadeDuration = crossfadeWindow;

    if (crossfade && previousIndex !== -1 && this.audioElements[previousIndex]?.src) {
      this.clearFadeInterval();
      this.setSlotVolume(nextIndex, 0);
      const beatmatchPlan = this.buildBeatmatchPlan(outgoingAnalysis, nextAnalysis);
      this.setPlaybackRate(nextIndex, beatmatchPlan.incomingRate);
      await nextAudio.play();

      const fadeMs = crossfadeWindow * 1000;
      const startTime = now();

      this.setMixState({
        status: 'crossfading',
        currentSongId: song.id,
        incomingSongId: song.id,
        outgoingSongId: this.slotTrackIds[previousIndex],
        currentBpm: nextAnalysis?.bpm ?? null,
        targetBpm: beatmatchPlan.targetBpm,
        playbackRate: beatmatchPlan.incomingRate,
        incomingPlaybackRate: beatmatchPlan.incomingRate,
        crossfadeDuration: crossfadeWindow,
        crossfadeWindow: {
          startAt: this.audioElements[previousIndex]?.currentTime ?? 0,
          endAt: (this.audioElements[previousIndex]?.currentTime ?? 0) + crossfadeWindow
        },
        phaseAligned: beatmatchPlan.phaseAligned,
        confidence: beatmatchPlan.confidence
      });
      this.emitProgress();

      this.fadeInterval = setInterval(() => {
        if (playbackId !== this.activePlaybackId) {
          this.clearFadeInterval();
          return;
        }

        const progress = clamp((now() - startTime) / fadeMs, 0, 1);
        const outgoingGain = Math.cos(progress * 0.5 * Math.PI);
        const incomingGain = Math.sin(progress * 0.5 * Math.PI);
        this.setSlotVolume(previousIndex, outgoingGain);
        this.setSlotVolume(nextIndex, incomingGain);
        this.setMixState({
          status: progress >= 1 ? 'playing' : 'crossfading',
          playbackRate: this.slotPlaybackRates[nextIndex],
          incomingPlaybackRate: this.slotPlaybackRates[nextIndex],
          crossfadeProgress: progress
        });
        this.emitProgress();

        if (progress >= 1) {
          this.clearFadeInterval();
          this.resetSlot(previousIndex);
          if (Math.abs(this.slotPlaybackRates[nextIndex] - 1) > RATE_RESET_TOLERANCE) {
            this.setPlaybackRate(nextIndex, this.slotPlaybackRates[nextIndex]);
          }
        }
      }, 50);
    } else {
      this.audioElements.forEach((_, index) => {
        if (index !== nextIndex) {
          this.resetSlot(index);
        }
      });

      this.setPlaybackRate(nextIndex, 1);
      this.setSlotVolume(nextIndex, 1);
      await nextAudio.play();
    }

    this.currentIndex = nextIndex;
    this.currentSongId = song.id;
    this.isPlaying = true;
    this.pausedSlots = [];
    this.setMixState({
      status: crossfade && previousIndex !== -1 ? this.currentMixState.status : 'playing',
      currentSongId: this.currentSongId,
      incomingSongId: crossfade && previousIndex !== -1 ? this.currentSongId : null,
      outgoingSongId: crossfade && previousIndex !== -1 ? this.slotTrackIds[previousIndex] : null,
      currentBpm: nextAnalysis?.bpm ?? null,
      targetBpm: crossfade && previousIndex !== -1
        ? (outgoingAnalysis?.bpm ?? nextAnalysis?.bpm ?? null)
        : (nextAnalysis?.bpm ?? null),
      playbackRate: this.slotPlaybackRates[nextIndex],
      incomingPlaybackRate: this.slotPlaybackRates[nextIndex],
      crossfadeDuration: crossfadeWindow,
      crossfadeWindow: crossfade && previousIndex !== -1 ? this.currentMixState.crossfadeWindow : null,
      phaseAligned: crossfade && previousIndex !== -1
        ? this.currentMixState.phaseAligned
        : true,
      confidence: nextAnalysis?.confidence ?? 0
    });
    this.scheduleTrackCallbacks(nextAudio, playbackId);
    this.emitProgress();
    return true;
  }

  async playCurrent() {
    await this.initialize();

    const slotsToResume = this.pausedSlots.length > 0
      ? [...this.pausedSlots]
      : [this.currentIndex].filter((index) => index !== -1 && this.audioElements[index]?.src);

    if (slotsToResume.length === 0) return false;

    await Promise.all(slotsToResume.map(async (index) => {
      const audio = this.audioElements[index];
      if (audio && audio.paused) {
        await audio.play();
      }
    }));

    this.pausedSlots = [];
    this.isPlaying = true;
    this.emitProgress();
    return true;
  }

  async unpause() {
    return this.playCurrent();
  }

  pause() {
    if (!this.isInitialized) return false;

    this.pausedSlots = this.audioElements
      .map((audio, index) => (!audio.paused ? index : null))
      .filter((value) => value !== null);

    this.audioElements.forEach((audio) => {
      try {
        audio.pause();
      } catch (error) {
        console.warn('[AudioEngine] No se pudo pausar un elemento de audio.', error);
      }
    });

    this.isPlaying = false;
    this.emitProgress();
    return true;
  }

  stopAll() {
    if (!this.isInitialized) return;

    this.clearAlmostEndedTimeout();
    this.clearFadeInterval();
    this.loadRequestId++;
    this.activePlaybackId++;
    this.audioElements.forEach((_, index) => this.resetSlot(index));
    this.currentIndex = -1;
    this.currentSongId = null;
    this.pausedSlots = [];
    this.isPlaying = false;
    this.currentMixState = this.createInitialMixState();
    this.emitProgress();
  }

  setVolume(value) {
    this.masterVolume = clamp(value, 0, 1);
    this.slotVolumes.forEach((_, index) => this.updateElementVolume(index));
    this.emitProgress();
  }

  seek(timeInSeconds) {
    const audio = this.audioElements[this.currentIndex];
    if (!audio) return;

    const safeTime = clamp(timeInSeconds, 0, Number.isFinite(audio.duration) ? audio.duration : 0);
    audio.currentTime = safeTime;
    this.scheduleTrackCallbacks(audio, this.activePlaybackId);
    this.emitProgress();
  }

  getPlaybackSnapshot() {
    const audio = this.audioElements[this.currentIndex];
    const mixState = this.getMixState();
    const currentAnalysis = this.getCurrentTrackAnalysis();

    return {
      currentTime: audio ? audio.currentTime : 0,
      duration: audio && Number.isFinite(audio.duration) ? audio.duration : 0,
      volume: this.masterVolume,
      isPlaying: this.isPlaying,
      playbackRate: audio?.playbackRate ?? 1,
      mix: mixState,
      analysis: currentAnalysis
    };
  }

  getIsActuallyPlaying() {
    if (this.currentIndex === -1) return false;
    const audio = this.audioElements[this.currentIndex];
    return Boolean(audio && !audio.paused && !audio.ended);
  }

  setOnEnded(callback) {
    this.onEndedCallback = callback;
  }

  setOnAlmostEnded(callback) {
    this.onAlmostEndedCallback = callback;
  }

  getAnalysisForSong(songId) {
    return this.getTrackAnalysis(songId);
  }

  /**
   * Conecta el AnalyserNode a los HTMLAudioElements activos.
   * Solo en navegadores no-iOS para no interferir con background playback.
   * @returns {boolean} - true si se conectó exitosamente.
   */
  connectAnalyser() {
    if (this.isAnalyserActive) return true;
    if (isIOS()) return false;

    try {
      const AudioCtx = window.AudioContext || window.webkitAudioContext;
      if (!AudioCtx) return false;

      if (!this.audioContext) {
        this.audioContext = new AudioCtx();
        this.analyserNode = this.audioContext.createAnalyser();
        this.analyserGainNode = this.audioContext.createGain();
        this.analyserNode.fftSize = 512;
        this.analyserNode.smoothingTimeConstant = 0.82;
        this.analyserGainNode.gain.value = 1;
        this.analyserNode.connect(this.analyserGainNode);
        this.analyserGainNode.connect(this.audioContext.destination);
      }

      // Conectar los elementos de audio existentes
      this.audioElements.forEach((audio, index) => {
        if (!this.sourceNodes[index] && audio) {
          try {
            const source = this.audioContext.createMediaElementSource(audio);
            source.connect(this.analyserNode);
            this.sourceNodes[index] = source;
          } catch (e) {
            console.warn(`[AudioEngine] No se pudo conectar elemento ${index} al analyser:`, e);
          }
        }
      });

      if (this.audioContext.state === 'suspended') {
        this.audioContext.resume();
      }

      this.isAnalyserActive = true;
      this.setMixState({ analyserActive: true });
      return true;
    } catch (error) {
      console.warn('[AudioEngine] Error conectando analyser:', error);
      return false;
    }
  }

  /**
   * Obtiene datos de frecuencia del AnalyserNode.
   * @returns {Uint8Array|null}
   */
  getFrequencyData() {
    if (!this.analyserNode || !this.isAnalyserActive) return null;

    const data = new Uint8Array(this.analyserNode.frequencyBinCount);
    this.analyserNode.getByteFrequencyData(data);
    return data;
  }

  /**
   * Nivel de bajos normalizado (0-1).
   */
  getBassLevel() {
    const data = this.getFrequencyData();
    if (!data) return 0;

    let sum = 0;
    const end = Math.min(10, data.length);
    for (let i = 0; i < end; i++) {
      sum += data[i];
    }
    return sum / (end * 255);
  }

  /**
   * Nivel de medios normalizado (0-1).
   */
  getMidLevel() {
    const data = this.getFrequencyData();
    if (!data) return 0;

    let sum = 0;
    const start = 10;
    const end = Math.min(60, data.length);
    for (let i = start; i < end; i++) {
      sum += data[i];
    }
    return sum / ((end - start) * 255);
  }
}

export const audioEngine = new AudioEngine();

