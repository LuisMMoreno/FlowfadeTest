import React, { useMemo, useCallback } from 'react';
import { usePlayback } from '../hooks/usePlayback';
import { Play, Pause, SkipBack, SkipForward, Volume2, Music, ChevronUp } from 'lucide-react';

/**
 * MiniPlayer fijo en la parte inferior.
 * En móvil: tap para expandir al FullPlayerView.
 * En desktop: controles completos con slider de progreso y volumen.
 */
export const Player = () => {
  const {
    currentSong,
    isPlaying,
    queue,
    currentTime,
    duration,
    volume,
    isTransitioning,
    isPlayerExpanded,
    mixState,
    setIsPlayerExpanded,
    togglePlay,
    nextSong,
    previousSong,
    seekTo,
    setVolume
  } = usePlayback();

  const currentIndex = useMemo(() => {
    if (!currentSong || !Array.isArray(queue)) return -1;
    return queue.findIndex((song) => song.id === currentSong.id);
  }, [currentSong, queue]);

  const hasSong = Boolean(currentSong);
  const canPlayPause = hasSong && !isTransitioning;
  const canGoPrevious = currentIndex > 0 && !isTransitioning;
  const canGoNext = currentIndex !== -1 && currentIndex < queue.length - 1 && !isTransitioning;
  const safeDuration = duration || 0;
  const safeCurrentTime = Math.min(currentTime || 0, safeDuration || 0);
  const safeVolume = Number.isFinite(volume) ? volume : 1;
  const progressPercent = safeDuration > 0 ? (safeCurrentTime / safeDuration) * 100 : 0;
  const analyserActive = Boolean(mixState?.analyser?.isActive);
  const mixSummary = analyserActive
    ? 'Visualizador reactivo activo'
    : 'Motor preparado para sincronizacion y mezcla automatica';

  const formatTime = (timeInSeconds) => {
    const totalSeconds = Math.max(0, Math.floor(timeInSeconds));
    const minutes = Math.floor(totalSeconds / 60);
    const seconds = totalSeconds % 60;
    return `${minutes}:${seconds.toString().padStart(2, '0')}`;
  };

  const handleSeek = (event) => {
    seekTo(Number(event.target.value));
  };

  const handleVolumeChange = (event) => {
    setVolume(Number(event.target.value));
  };

  const handleExpand = useCallback(() => {
    if (currentSong) {
      setIsPlayerExpanded(true);
    }
  }, [currentSong, setIsPlayerExpanded]);

  const handleMobileClick = useCallback((e) => {
    // En móvil, si no se clickeó un botón, expandir
    if (e.target.closest('button') || e.target.closest('input')) return;
    handleExpand();
  }, [handleExpand]);

  // No mostrar cuando el FullPlayer está abierto
  if (isPlayerExpanded) return null;

  return (
    <div
      className="player-surface player-shell-transition fixed bottom-0 left-0 right-0 z-50 safe-pb safe-px"
      style={{ touchAction: 'manipulation' }}
      role="region"
      aria-label="Reproductor actual"
      aria-live="polite"
    >
      {/* Mini progress bar (visible en móvil) */}
      {hasSong && (
        <div className="mini-progress-bar" style={{ width: `${progressPercent}%` }} />
      )}

      <div
        className="relative min-h-[84px] md:min-h-[96px] px-3 md:px-4 flex items-center justify-between gap-2 cursor-pointer md:cursor-default"
        onClick={handleMobileClick}
      >
        {hasSong && (
          <div className="mini-player-expand-hint md:hidden" aria-hidden="true" />
        )}

        {/* Información de canción actual */}
        <div className="flex items-center w-[48%] md:w-1/3 min-w-0 mr-1 md:mr-2">
          <div className="w-12 h-12 md:w-14 md:h-14 bg-accent/20 rounded-xl shadow-2xl flex-shrink-0 flex items-center justify-center overflow-hidden border border-white/10">
             {currentSong?.cover ? (
               <img src={currentSong.cover} alt={`Portada de ${currentSong.title}`} className="w-full h-full object-cover" />
             ) : (
               <Music size={20} className="text-accent" />
             )}
          </div>
          <div className="ml-3 min-w-0">
            <h4 className="text-[13px] md:text-sm font-bold text-white truncate">
              {currentSong ? currentSong.title : 'Sin reproducción'}
            </h4>
            <p className="text-[11px] md:text-xs text-white/70 truncate">
              {currentSong ? currentSong.artist : 'Selecciona una canción'}
            </p>
            {currentSong && (
              <p className="player-supporting-text hidden sm:block truncate">
                {mixSummary}
              </p>
            )}
          </div>
        </div>

        {/* Controles centrales */}
        <div className="flex flex-col items-center justify-center flex-1 max-w-[600px] md:w-1/3 min-w-0">
          <div className="flex items-center space-x-3 md:space-x-4">
            {/* Skip Back — solo desktop */}
            <button
              type="button"
              onClick={(event) => {
                event.stopPropagation();
                previousSong();
              }}
              disabled={!canGoPrevious}
              aria-label="Canción anterior"
              className="player-icon-button player-control-transition hidden md:flex text-white/80 hover:text-white disabled:opacity-40 disabled:cursor-not-allowed"
            >
              <SkipBack size={20} className="fill-current" />
            </button>

            {/* Play/Pause — siempre visible */}
            <button
              type="button"
              onClick={(e) => {
                e.stopPropagation();
                togglePlay();
              }}
              disabled={!canPlayPause}
              aria-label={isPlaying ? 'Pausar' : 'Reproducir'}
              className="player-primary-button player-control-transition shadow-lg disabled:bg-white/70 disabled:text-black/60 disabled:cursor-not-allowed"
            >
              {isPlaying ? (
                <Pause size={22} className="fill-current" />
              ) : (
                <Play size={22} className="fill-current ml-0.5" />
              )}
            </button>

            {/* Skip Forward — siempre visible en móvil también */}
            <button
              type="button"
              onClick={(e) => {
                e.stopPropagation();
                nextSong();
              }}
              disabled={!canGoNext}
              aria-label="Siguiente canción"
              className="player-icon-button player-control-transition text-white/80 hover:text-white disabled:opacity-40 disabled:cursor-not-allowed"
            >
              <SkipForward size={20} className="fill-current" />
            </button>
          </div>
          
          {/* Progress bar — solo desktop */}
          <div className="w-full mt-2 hidden md:flex items-center space-x-2 text-[10px] text-white/65 font-medium">
            <span className="w-9 text-right tabular-nums">{formatTime(safeCurrentTime)}</span>
            <input
              type="range"
              min="0"
              max={safeDuration || 0}
              step="0.1"
              value={safeCurrentTime}
              onChange={handleSeek}
              disabled={!hasSong || safeDuration <= 0 || isTransitioning}
              aria-label="Progreso de reproducción"
              className="player-slider player-slider-progress flex-1"
              style={{
                '--player-progress': safeDuration > 0 ? `${(safeCurrentTime / safeDuration) * 100}%` : '0%'
              }}
            />
            <span className="w-9 tabular-nums">{formatTime(safeDuration)}</span>
          </div>
        </div>

        {/* Controles adicionales */}
        <div className="flex items-center justify-end w-[20%] md:w-1/3">
          {/* Expand button — solo móvil */}
          {hasSong && (
            <button
              type="button"
              onClick={(e) => {
                e.stopPropagation();
                handleExpand();
              }}
              className="player-icon-button player-control-transition md:hidden text-white/70 hover:text-white"
              aria-label="Expandir reproductor"
              aria-controls="full-player-view"
              aria-expanded={isPlayerExpanded}
            >
              <ChevronUp size={22} />
            </button>
          )}

          {/* Volume — solo desktop */}
          <div className="items-center space-x-2 w-32 hidden lg:flex">
            <Volume2 size={16} className="text-white/65" aria-hidden="true" />
            <input
              type="range"
              min="0"
              max="1"
              step="0.01"
              value={safeVolume}
              onChange={handleVolumeChange}
              disabled={!hasSong}
              aria-label="Volumen"
              className="player-slider flex-1"
              style={{ '--player-progress': `${safeVolume * 100}%` }}
            />
          </div>
        </div>
      </div>
    </div>
  );
};
