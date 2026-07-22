// post.js - Wird nach dem generierten Emscripten-Code ausgeführt
// Konfigurationen und Anpassungen für die HL2-Engine

// 1. dynamicLibraries explizit leer setzen — neededDynlibs werden aus WASM-Metadaten geladen
Module.dynamicLibraries = [];

// 2. Korrekte Zuweisung des Canvas-Elements
if (window.canvasElement) {
  Module.canvas = window.canvasElement;
} else {
  Module.canvas = document.getElementById('game-canvas');
}

// 3. Engine-Startargumente werden von index.html gesetzt — NICHT hier überschreiben!
// Module.arguments wird in index.html mit +map_background background01 etc. gesetzt.
console.log('[POST-INIT] Arguments from index.html:', (Module.arguments || []).join(' '));

// 4. Integration mit xr_wrapper.js
Module.onRuntimeInitialized = (function() {
  var orig = Module.onRuntimeInitialized;
  return function() {
    if (orig) orig();
    console.log('[POST-INIT] WASM Runtime initialisiert! Engine startet...');
    if (window.xrWrapper && typeof window.xrWrapper.onEngineInitialized === 'function') {
      window.xrWrapper.onEngineInitialized();
    }
  };
})();
