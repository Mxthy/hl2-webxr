// post.js - Wird nach dem generierten Emscripten-Code ausgeführt
// Konfigurationen und Anpassungen für die HL2-Engine

// 1. dynamicLibraries explizit leer setzen, damit Emscripten die neededDynlibs
// selbstständig aus den WASM-Metadaten parst (slqnt.dev-Ansatz)
Module.dynamicLibraries = [];

// 2. Korrekte Zuweisung des Canvas-Elements
if (window.canvasElement) {
  Module.canvas = window.canvasElement;
} else {
  Module.canvas = document.getElementById('canvas');
}

// 3. Engine-Startargumente festlegen (Quest 3 optimiert)
// -game hl2: Lädt HL2 Mod/Assets
// -windowed -w 1920 -h 1080: Standardauflösung
// -novid: Intro-Videos überspringen (wichtig bei WebXR, da keine VR-Wiedergabe des Intro-Videos möglich)
// -noip: Kein TCP/IP-Binding-Fehler
// +mat_hdr_level 0 +mat_colorcorrection 1 +mat_picmip 1: Performance-Optimierungen für Quest 3 Standalone
// -nosteam: Deaktiviert Steam-Verbindung
Module.arguments = [
  '-game', 'hl2',
  '-windowed',
  '-w', '1920',
  '-h', '1080',
  '-novid',
  '-noip',
  '+mat_hdr_level', '0',
  '+mat_colorcorrection', '1',
  '+mat_picmip', '1',
  '-nosteam'
];

console.log('[POST-INIT] Engine-Argumente gesetzt:', Module.arguments.join(' '));

// 4. Integration mit xr_wrapper.js SharedArrayBuffer Bridge
// Sobald das WASM-Memory zur Verfügung steht, initialisieren wir den SAB-Zeiger in WASM, falls benötigt
Module.onRuntimeInitialized = function() {
  console.log('[POST-INIT] WASM Runtime initialisiert! Engine startet...');
  if (window.xrWrapper && typeof window.xrWrapper.onEngineInitialized === 'function') {
    window.xrWrapper.onEngineInitialized();
  }
};
