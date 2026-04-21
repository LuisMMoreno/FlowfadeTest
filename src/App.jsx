import React, { useEffect } from 'react';
import { Sidebar } from './components/Sidebar';
import { LibraryView } from './components/LibraryView';
import { Player } from './components/Player';
import { FullPlayerView } from './components/FullPlayerView';
import { usePlayback } from './hooks/usePlayback';
import { AnimatePresence } from 'framer-motion';

function App() {
  const { isPlayerExpanded, currentSong, setIsPlayerExpanded } = usePlayback();

  useEffect(() => {
    if (!isPlayerExpanded) return undefined;

    const handleEscape = (event) => {
      if (event.key === 'Escape') {
        setIsPlayerExpanded(false);
      }
    };

    window.addEventListener('keydown', handleEscape);
    return () => {
      window.removeEventListener('keydown', handleEscape);
    };
  }, [isPlayerExpanded, setIsPlayerExpanded]);

  return (
    <div className="app-shell flex min-h-dvh bg-black overflow-hidden select-none">
      <a
        href="#main-content"
        className="sr-only focus:not-sr-only focus:absolute focus:left-4 focus:top-4 focus:z-[100] focus:rounded-full focus:bg-white focus:px-4 focus:py-2 focus:text-black"
      >
        Saltar al contenido
      </a>

      {/* Sidebar - Oculto en móviles para simplificar MVP */}
      <div
        className={`hidden md:block ${isPlayerExpanded ? 'pointer-events-none' : ''}`}
        aria-hidden={isPlayerExpanded}
      >
        <Sidebar />
      </div>

      {/* Main Content Area */}
      <main
        id="main-content"
        className={`app-main-region flex-1 flex flex-col min-w-0 bg-surface ${isPlayerExpanded ? 'pointer-events-none' : ''}`}
        aria-hidden={isPlayerExpanded}
      >
        <LibraryView />
      </main>

      {/* Persistent MiniPlayer */}
      <Player />

      {/* Full Player Overlay */}
      <AnimatePresence>
        {isPlayerExpanded && currentSong && (
          <FullPlayerView key="full-player" />
        )}
      </AnimatePresence>
    </div>
  );
}

export default App;
