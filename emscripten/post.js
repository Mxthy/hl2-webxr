// post.js — Engine-Konfiguration (nach dem generierten Emscripten-Code)
// slqnt-Ansatz: dynamicLibraries=[] → Emscripten liest neededDynlibs aus WASM-Metadata

// 1. dynamicLibraries LEER — Emscripten-Dylink-System übernimmt aus WASM-Metadata
//    (Verhindert vtable-Reihenfolge-Probleme wie _ZTV11IVP_Mindist als GOT.mem-Import)
Module.dynamicLibraries = [];

// 2. Canvas — korrekte Referenz
Module.canvas = window.canvasElement || document.getElementById('canvas');
if (Module.canvas) {
  Module.canvas.width = window.screen.availWidth || 1920;
  Module.canvas.height = window.screen.availHeight || 1080;
}

// 3. Engine-Startargumente (Quest 3 optimiert)
Module.arguments = [
  '-game', 'hl2',
  '-windowed',
  '-w', String(Module.canvas ? Module.canvas.width : 1920),
  '-h', String(Module.canvas ? Module.canvas.height : 1080),
  '-novid',
  '-noip',
  '-nosteam',
  '+mat_hdr_level', '0',
  '+mat_colorcorrection', '1',
  '+mat_picmip', '1',
];

// 4. Status-Callbacks
Module.setStatus = function(text) {
  if (Module.setStatus.last !== text) {
    Module.setStatus.last = text;
    if (window.statusElement) window.statusElement.textContent = text || '';
    var m = text && text.match(/([^(]+)\((\d+)\/(\d+)\)/);
    if (m && window.progressElement) {
      window.progressElement.hidden = false;
      window.progressElement.value = parseInt(m[2]);
      window.progressElement.max   = parseInt(m[3]);
    } else if (window.progressElement && !text) {
      window.progressElement.hidden = true;
      if (window.spinnerElement) window.spinnerElement.style.display = 'none';
    }
  }
};

Module.totalDependencies = 0;
Module.monitorRunDependencies = function(left) {
  this.totalDependencies = Math.max(this.totalDependencies, left);
  Module.setStatus(left ? 'Vorbereitung... (' + (this.totalDependencies - left) + '/' + this.totalDependencies + ')' : '');
};

// 5. Nach Runtime-Init: XR-Wrapper benachrichtigen
Module.onRuntimeInitialized = function() {
  console.log('[POST] WASM Runtime initialisiert!');
  if (window.xrWrapper && typeof window.xrWrapper.onEngineInitialized === 'function') {
    window.xrWrapper.onEngineInitialized();
  }
};

// 6. Fehler-Handler
window.onerror = function(e) {
  Module.setStatus('Fehler — siehe Browser-Konsole');
  if (window.spinnerElement) window.spinnerElement.style.display = 'none';
  Module.setStatus = function(t) { if (t) console.error('[post-exception] ' + t); };
};

// 7. __gameChoice Promise (Engine wartet auf Spielauswahl)
Module.__gameChoice = Module.__gameChoice || new Promise(function(resolve) {
  Module.__resolveGame = resolve;
  window.__resolveGame = resolve; // auch global verfügbar für index.html
});

console.log('[POST] Engine-Konfiguration geladen. dynamicLibraries=[], Canvas gesetzt.');
