;(() => {
  if(typeof window === 'undefined') return;
  window.addEventListener('beforeunload', function (event) { event.preventDefault() })
  if (typeof canvasElement !== 'undefined') {
    canvasElement.onkeypress = e => e.preventDefault()
  }

  // Nur background1 (korrekte Map-ID, nicht background01) beim Start laden.
  // materials + models werden lazy via Module.downloadMap geladen wenn die Engine sie anfordert.
  addRunDependency('load_game_data')
  dataLoader.loadMapWithDeps('background1')
    .then(() => {
      console.log('[hl2] background1 OK — Engine startet')
      removeRunDependency('load_game_data')
    })
    .catch(err => {
      console.warn('[hl2] background1 Fehler (ignoriert, Engine startet trotzdem):', err.message)
      removeRunDependency('load_game_data')
    })
})();
