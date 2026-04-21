import React, { useCallback, useMemo } from 'react';
import { motion } from 'framer-motion';
import { usePlayback } from '../hooks/usePlayback';
import { useAlbumColors } from '../hooks/useAlbumColors';
import { useAudioAnalyser } from '../hooks/useAudioAnalyser';
import { WaveBackground } from './WaveBackground';
import {
  Play,
  Pause,
  SkipBack,
  SkipForward,
  ChevronDown,
  Music,
  Sparkles,
  Radio,
  Waves,
  Disc3
} from 'lucide-react';

const PRESS_TRANSITION = 'transform 180ms cubic-bezier(0.22, 1, 0.36, 1), opacity 180ms cubic-bezier(0.22, 1, 0.36, 1), background-color 180ms cubic-bezier(0.22, 1, 0.36, 1), color 180ms cubic-bezier(0.22, 1, 0.36, 1), border-color 180ms cubic-bezier(0.22, 1, 0.36, 1)';

function formatTime(timeInSeconds) {
  const totalSeconds = Math.max(0, Math.floor(timeInSeconds));
  const minutes = Math.floor(totalSeconds / 60);
  const seconds = totalSeconds % 60;
  return `${minutes}:${seconds.toString().padStart(2, '0')}`;
}

function formatBpm(value) {
  const numeric = Number(value);
  if (!Number.isFinite(numeric) || numeric <= 0) return null;
  return `${Math.round(numeric)} BPM`;
}

function formatPlaybackRate(value) {
  const numeric = Number(value);
  if (!Number.isFinite(numeric) || numeric <= 0) return null;
  return `${numeric.toFixed(2)}x`;
}

function resolveMixMetrics(playback, currentSong, queue, currentIndex) {
  const nextSong = queue?.[currentIndex + 1] ?? null;

  const currentTempo = [
    playback.currentTempo,
    playback.currentBpm,
    playback.tempo,
    playback.bpm,
    currentSong?.bpm,
    currentSong?.metadata?.bpm
  ].find((value) => Number.isFinite(Number(value)) && Number(value) > 0);

  const targetTempo = [
    playback.targetTempo,
    playback.targetBpm,
    playback.mixTargetBpm,
    nextSong?.bpm,
    nextSong?.metadata?.bpm
  ].find((value) => Number.isFinite(Number(value)) && Number(value) > 0);

  const playbackRate = [
    playback.playbackRate,
    playback.mixPlaybackRate,
    playback.tempoPlaybackRate
  ].find((value) => Number.isFinite(Number(value)) && Number(value) > 0);

  const phaseOffset = [
    playback.phaseOffset,
    playback.beatPhaseOffset,
    playback.phaseAlignment
  ].find((value) => Number.isFinite(Number(value)));

  const rawMixProgress = [
    playback.mixProgress,
    playback.transitionProgress,
    playback.crossfadeProgress
  ].find((value) => Number.isFinite(Number(value)));

  const normalizedMixProgress = Number.isFinite(rawMixProgress)
    ? Math.max(0, Math.min(rawMixProgress > 1 ? rawMixProgress / 100 : rawMixProgress, 1))
    : null;

  const isMixing = Boolean(
    playback.isMixing ??
    playback.isBeatmatching ??
    playback.isAutoMixing ??
    (normalizedMixProgress !== null && normalizedMixProgress > 0 && normalizedMixProgress < 1) ??
    playback.isTransitioning
  );

  const beatmatchState = playback.beatmatchStatus || playback.mixStatus || playback.transitionLabel || null;

  return {
    nextSong,
    currentTempo,
    targetTempo,
    playbackRate,
    phaseOffset,
    mixProgress: normalizedMixProgress,
    isMixing,
    beatmatchState
  };
}

function getStatusLabel(metrics, isPlaying) {
  if (metrics.beatmatchState) return metrics.beatmatchState;
  if (metrics.isMixing) return 'Transition in progress';
  if (!isPlaying) return 'Paused';
  return 'Playback locked';
}

function TransportButton({ children, primary = false, disabled = false, ...props }) {
  return (
    <button
      type="button"
      disabled={disabled}
      {...props}
      className={`flex items-center justify-center rounded-full border backdrop-blur-xl ${
        primary
          ? 'bg-white text-slate-950 border-white/80 shadow-[0_20px_60px_rgba(255,255,255,0.28)]'
          : 'bg-white/10 text-white border-white/12 shadow-[0_12px_32px_rgba(0,0,0,0.22)]'
      } disabled:opacity-35 disabled:cursor-not-allowed`}
      style={{
        transition: PRESS_TRANSITION,
        ...props.style
      }}
    >
      {children}
    </button>
  );
}

/**
 * Vista de pantalla completa "Now Playing".
 * Se expande desde el MiniPlayer con animación.
 */
export const FullPlayerView = () => {
  const playback = usePlayback();
  const {
    currentSong,
    isPlaying,
    queue,
    currentTime,
    duration,
    isTransitioning,
    isPlayerExpanded,
    setIsPlayerExpanded,
    togglePlay,
    nextSong,
    previousSong,
    seekTo
  } = playback;

  const {
    primaryColor,
    secondaryColor,
    primaryRgb,
    secondaryRgb,
    gradient,
    surfaceGradient,
    ambientGradient,
    glowColor,
    mutedTextColor,
    accentSoft,
    shadowColor
  } = useAlbumColors(currentSong?.cover || null);

  const { bassLevel, midLevel } = useAudioAnalyser(isPlayerExpanded, isPlaying);

  const currentIndex = useMemo(() => {
    if (!currentSong || !Array.isArray(queue)) return -1;
    return queue.findIndex((song) => song.id === currentSong.id);
  }, [currentSong, queue]);

  const mixMetrics = useMemo(
    () => resolveMixMetrics(playback, currentSong, queue, currentIndex),
    [playback, currentSong, queue, currentIndex]
  );

  const hasSong = Boolean(currentSong);
  const canPlayPause = hasSong && !isTransitioning;
  const canGoPrevious = currentIndex > 0 && !isTransitioning;
  const canGoNext = currentIndex !== -1 && currentIndex < queue.length - 1 && !isTransitioning;
  const safeDuration = duration || 0;
  const safeCurrentTime = Math.min(currentTime || 0, safeDuration || 0);
  const progressPercent = safeDuration > 0 ? (safeCurrentTime / safeDuration) * 100 : 0;
  const queueLabel = currentIndex >= 0 ? `${currentIndex + 1} / ${queue.length || 1}` : null;
  const mixStatusLabel = getStatusLabel(mixMetrics, isPlaying);

  const stats = [
    {
      icon: Radio,
      label: 'Tempo',
      value: formatBpm(mixMetrics.currentTempo) || 'Streaming'
    },
    {
      icon: Waves,
      label: 'Mix',
      value: mixMetrics.targetTempo ? `to ${formatBpm(mixMetrics.targetTempo)}` : mixStatusLabel
    },
    {
      icon: Disc3,
      label: 'Rate',
      value: formatPlaybackRate(mixMetrics.playbackRate) || 'Native'
    }
  ];

  const handleSeek = useCallback((event) => {
    seekTo(Number(event.target.value));
  }, [seekTo]);

  const handleClose = useCallback(() => {
    setIsPlayerExpanded(false);
  }, [setIsPlayerExpanded]);

  if (!currentSong || !isPlayerExpanded) return null;

  return (
    <motion.div
      id="full-player-view"
      initial={{ y: '100%' }}
      animate={{ y: 0 }}
      exit={{ y: '100%' }}
      transition={{
        type: 'spring',
        damping: 32,
        stiffness: 300,
        mass: 0.82
      }}
      drag="y"
      dragConstraints={{ top: 0, bottom: 0 }}
      dragElastic={{ top: 0, bottom: 0.55 }}
      onDragEnd={(_, info) => {
        if (info.offset.y > 120 || info.velocity.y > 420) {
          handleClose();
        }
      }}
      className="fixed inset-0 z-[60] select-none overflow-hidden"
      style={{
        touchAction: 'none',
        WebkitUserSelect: 'none',
        background: ambientGradient
      }}
    >
      <div
        className="fullplayer-bg-blur"
        style={{
          backgroundImage: currentSong.cover ? `url(${currentSong.cover})` : gradient,
          opacity: 0.78,
          transform: 'scale(1.12)'
        }}
      />

      <div
        aria-hidden="true"
        className="absolute inset-0"
        style={{
          zIndex: 1,
          background: `
            radial-gradient(circle at 50% 18%, ${glowColor} 0%, rgba(0, 0, 0, 0) 34%),
            radial-gradient(circle at 20% 80%, rgba(${primaryRgb[0]}, ${primaryRgb[1]}, ${primaryRgb[2]}, 0.18) 0%, rgba(0, 0, 0, 0) 32%),
            radial-gradient(circle at 82% 72%, rgba(${secondaryRgb[0]}, ${secondaryRgb[1]}, ${secondaryRgb[2]}, 0.16) 0%, rgba(0, 0, 0, 0) 30%),
            linear-gradient(180deg, rgba(5, 10, 22, 0.2) 0%, rgba(4, 8, 20, 0.56) 46%, rgba(3, 7, 18, 0.92) 100%)
          `
        }}
      />

      <WaveBackground
        bassLevel={bassLevel}
        midLevel={midLevel}
        primaryRgb={primaryRgb}
        secondaryRgb={secondaryRgb}
        isPlaying={isPlaying}
      />

      <div
        className="absolute inset-0 backdrop-blur-[26px]"
        style={{
          zIndex: 2,
          background: 'linear-gradient(180deg, rgba(255,255,255,0.06) 0%, rgba(255,255,255,0.015) 18%, rgba(7,12,24,0.52) 60%, rgba(3,8,18,0.82) 100%)'
        }}
      />

      <div
        className="relative flex h-full flex-col"
        style={{
          zIndex: 3,
          paddingTop: 'calc(env(safe-area-inset-top, 0px) + 8px)',
          paddingBottom: 'calc(env(safe-area-inset-bottom, 0px) + 16px)',
          paddingLeft: 'max(env(safe-area-inset-left, 0px), 16px)',
          paddingRight: 'max(env(safe-area-inset-right, 0px), 16px)'
        }}
      >
        <div className="flex items-center justify-between px-2 pb-3 pt-2">
          <button
            onClick={handleClose}
            aria-label="Cerrar reproductor"
            className="flex items-center justify-center rounded-full border border-white/10 bg-white/8 text-white/78 backdrop-blur-xl"
            style={{
              width: '46px',
              height: '46px',
              transition: PRESS_TRANSITION
            }}
          >
            <ChevronDown size={24} />
          </button>

          <div className="flex flex-col items-center gap-2">
            <div
              aria-hidden="true"
              className="rounded-full"
              style={{
                width: '44px',
                height: '5px',
                background: 'rgba(255,255,255,0.28)'
              }}
            />
            <div className="text-[11px] font-semibold uppercase tracking-[0.28em] text-white/58">
              Now Playing
            </div>
          </div>

          <div
            className="rounded-full border border-white/10 px-3 py-2 text-[11px] font-semibold uppercase tracking-[0.22em] backdrop-blur-xl"
            style={{
              minWidth: '46px',
              minHeight: '46px',
              color: 'rgba(255,255,255,0.72)',
              background: 'rgba(255,255,255,0.06)'
            }}
          >
            {queueLabel || 'Live'}
          </div>
        </div>

        <div className="flex min-h-0 flex-1 flex-col justify-between gap-2 sm:gap-4 pb-2">
          <div className="flex min-h-0 flex-col gap-2 sm:gap-4 shrink">
            <motion.div
              initial={{ opacity: 0, y: 18 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ duration: 0.26, ease: [0.22, 1, 0.36, 1] }}
              className="flex-1 min-h-0 mx-auto w-full max-w-[420px] flex flex-col justify-center shrink px-2"
            >
              <div
                className="relative w-full flex-shrink overflow-hidden rounded-[32px] border border-white/12 p-3 sm:px-4 sm:py-4 shadow-[0_24px_90px_rgba(0,0,0,0.42)] flex flex-col"
                style={{
                  background: surfaceGradient,
                  boxShadow: `0 28px 90px ${shadowColor}`
                }}
              >
                <div
                  aria-hidden="true"
                  className="absolute inset-x-6 top-3 h-24 rounded-full blur-3xl"
                  style={{ background: `radial-gradient(circle, ${glowColor} 0%, rgba(255,255,255,0) 72%)` }}
                />

                <div className="relative w-full max-w-[min(100%,40vh)] mx-auto aspect-square overflow-hidden rounded-[26px] border border-white/10 bg-black/20 shrink">
                  {currentSong.cover ? (
                    <motion.img
                      key={currentSong.cover}
                      src={currentSong.cover}
                      alt={currentSong.title}
                      draggable="false"
                      initial={{ scale: 1.04, opacity: 0.88 }}
                      animate={{ scale: 1, opacity: 1 }}
                      transition={{ duration: 0.45, ease: [0.22, 1, 0.36, 1] }}
                      className="h-full w-full object-cover"
                    />
                  ) : (
                    <div
                      className="flex h-full w-full items-center justify-center"
                      style={{ background: gradient }}
                    >
                      <Music size={88} className="text-white/28" />
                    </div>
                  )}

                  <div
                    aria-hidden="true"
                    className="absolute inset-0"
                    style={{
                      background: 'linear-gradient(180deg, rgba(255,255,255,0.02) 0%, rgba(255,255,255,0) 36%, rgba(0,0,0,0.16) 100%)'
                    }}
                  />
                </div>

                <div className="relative mt-3 sm:mt-4 shrink-0 flex items-center justify-between gap-3 rounded-[22px] border border-white/10 bg-black/18 px-3 py-2 sm:px-4 sm:py-3 backdrop-blur-xl">
                  <div className="min-w-0">
                    <div className="text-[11px] font-semibold uppercase tracking-[0.22em] text-white/48">
                      Session Flow
                    </div>
                    <div className="mt-1 flex items-center gap-2 text-sm font-medium text-white/88">
                      <Sparkles size={15} style={{ color: accentSoft }} />
                      <span className="truncate">{mixStatusLabel}</span>
                    </div>
                  </div>

                  {mixMetrics.mixProgress !== null ? (
                    <div className="min-w-[74px] text-right">
                      <div className="text-[11px] font-semibold uppercase tracking-[0.18em] text-white/42">
                        Blend
                      </div>
                      <div className="mt-1 text-lg font-semibold text-white">
                        {Math.round(mixMetrics.mixProgress * 100)}%
                      </div>
                    </div>
                  ) : null}
                </div>
              </div>
            </motion.div>

            <motion.div
              initial={{ opacity: 0, y: 24 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ duration: 0.3, delay: 0.04, ease: [0.22, 1, 0.36, 1] }}
              className="px-2"
            >
              <div className="mx-auto flex w-full max-w-[460px] flex-col gap-3 sm:gap-4 shrink-0">
                <div className="space-y-1 sm:space-y-2">
                  <h2
                    className="text-pretty text-[clamp(1.9rem,4.6vw,3rem)] font-bold tracking-[-0.04em] text-white"
                    style={{ lineHeight: 1.02 }}
                  >
                    {currentSong.title}
                  </h2>
                  <div className="flex items-center justify-between gap-3">
                    <p
                      className="min-w-0 truncate text-[clamp(1rem,2.8vw,1.125rem)] font-medium"
                      style={{ color: mutedTextColor }}
                    >
                      {currentSong.artist || 'Unknown artist'}
                    </p>
                    {mixMetrics.nextSong ? (
                      <span className="max-w-[45%] truncate rounded-full border border-white/10 px-3 py-1.5 text-[11px] font-medium text-white/66 backdrop-blur-md">
                        Up next: {mixMetrics.nextSong.title}
                      </span>
                    ) : null}
                  </div>
                </div>

                <div className="grid grid-cols-3 gap-2">
                  {stats.map(({ icon: Icon, label, value }) => (
                    <div
                      key={label}
                      className="rounded-[20px] border border-white/10 px-2 py-2 sm:px-3 sm:py-3 backdrop-blur-xl flex flex-col justify-center min-h-0"
                      style={{ background: 'rgba(255,255,255,0.07)' }}
                    >
                      <div className="flex items-center gap-2 text-[11px] font-semibold uppercase tracking-[0.18em] text-white/42">
                        <Icon size={14} />
                        <span>{label}</span>
                      </div>
                      <div className="mt-2 text-sm font-semibold text-white/88">
                        {value}
                      </div>
                    </div>
                  ))}
                </div>

                <div
                  className="overflow-hidden rounded-[24px] border border-white/10 px-3 py-3 sm:px-4 sm:py-4 backdrop-blur-2xl"
                  style={{ background: 'rgba(10, 16, 28, 0.42)' }}
                >
                  <div className="flex items-center justify-between gap-3">
                    <span className="text-[11px] font-semibold uppercase tracking-[0.22em] text-white/48">
                      Playback progress
                    </span>
                    {mixMetrics.phaseOffset !== undefined && mixMetrics.phaseOffset !== null ? (
                      <span className="text-xs font-medium text-white/60">
                        Phase {Math.round(Number(mixMetrics.phaseOffset))}
                      </span>
                    ) : null}
                  </div>

                  <div className="mt-2 sm:mt-4">
                    <input
                      type="range"
                      min="0"
                      max={safeDuration || 0}
                      step="0.1"
                      value={safeCurrentTime}
                      onChange={handleSeek}
                      disabled={!hasSong || safeDuration <= 0 || isTransitioning}
                      aria-label="Progreso de reproducción"
                      className="fullplayer-slider"
                      style={{
                        '--player-progress': `${progressPercent}%`
                      }}
                    />
                  </div>

                  <div className="mt-2 flex items-center justify-between text-xs font-medium tabular-nums text-white/54">
                    <span>{formatTime(safeCurrentTime)}</span>
                    <span>{formatTime(safeDuration)}</span>
                  </div>

                  {mixMetrics.mixProgress !== null ? (
                    <div className="mt-4">
                      <div className="mb-2 flex items-center justify-between text-[11px] font-semibold uppercase tracking-[0.18em] text-white/40">
                        <span>Transition energy</span>
                        <span>{Math.round(mixMetrics.mixProgress * 100)}%</span>
                      </div>
                      <div className="h-2 overflow-hidden rounded-full bg-white/8">
                        <div
                          className="h-full rounded-full"
                          style={{
                            width: `${Math.round(mixMetrics.mixProgress * 100)}%`,
                            background: `linear-gradient(90deg, ${primaryColor} 0%, ${secondaryColor} 100%)`,
                            boxShadow: `0 0 24px ${glowColor}`,
                            transition: 'width 220ms cubic-bezier(0.22, 1, 0.36, 1)'
                          }}
                        />
                      </div>
                    </div>
                  ) : null}
                </div>
              </div>
            </motion.div>
          </div>

          <motion.div
            initial={{ opacity: 0, y: 22 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.28, delay: 0.08, ease: [0.22, 1, 0.36, 1] }}
            className="px-2 pt-1 pb-1 shrink-0"
          >
            <div
              className="mx-auto flex w-full max-w-[460px] items-center justify-between rounded-[28px] border border-white/10 px-4 py-3 backdrop-blur-[24px]"
              style={{ background: 'rgba(7, 12, 24, 0.46)' }}
            >
              <TransportButton
                onClick={previousSong}
                disabled={!canGoPrevious}
                aria-label="Canción anterior"
                style={{ width: '56px', height: '56px' }}
              >
                <SkipBack size={24} className="fill-current" />
              </TransportButton>

              <TransportButton
                primary
                onClick={togglePlay}
                disabled={!canPlayPause}
                aria-label={isPlaying ? 'Pausar' : 'Reproducir'}
                style={{ width: '78px', height: '78px' }}
              >
                {isPlaying ? (
                  <Pause size={34} className="fill-current" />
                ) : (
                  <Play size={34} className="fill-current" style={{ marginLeft: '3px' }} />
                )}
              </TransportButton>

              <TransportButton
                onClick={nextSong}
                disabled={!canGoNext}
                aria-label="Siguiente canción"
                style={{ width: '56px', height: '56px' }}
              >
                <SkipForward size={24} className="fill-current" />
              </TransportButton>
            </div>
          </motion.div>
        </div>
      </div>
    </motion.div>
  );
};
