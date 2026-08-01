// post.js - Wird nach dem generierten Emscripten-Code ausgeführt
// Konfigurationen und Anpassungen für die HL2-Engine

// Keep Module.dynamicLibraries from the shell/index.
// Clearing it here breaks the required tier0 -> vstdlib -> engine order.

// 2. Canvas-Element Zuweisung
if (window.canvasElement) {
  Module.canvas = window.canvasElement;
} else {
  Module.canvas = document.getElementById('canvas');
}

// 3. Engine-Startargumente (1280x800 für Worker OffscreenCanvas)
Module.arguments = [
  '-game', 'hl2',
  '-windowed',
  '-w', '1280',
  '-h', '800',
  '-novid',
  '-noip',
  '+mat_hdr_level', '0',
  '+mat_colorcorrection', '1',
  '+mat_picmip', '1',
  '-nosteam'
];

console.log('[POST-INIT] Engine-Argumente gesetzt:', Module.arguments.join(' '));

// 4. WebXR Bridge Integration
const __previousRuntimeInitialized = Module.onRuntimeInitialized;
Module.onRuntimeInitialized = function() {
  if (typeof __previousRuntimeInitialized === 'function') {
    __previousRuntimeInitialized();
  }
  console.log('[POST-INIT] WASM Runtime initialisiert! Engine startet...');
  if (window.xrWrapper && typeof window.xrWrapper.onEngineInitialized === 'function') {
    window.xrWrapper.onEngineInitialized();
  }
};
