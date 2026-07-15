// pre.js - Globale Variablen vor dem Emscripten-Bundle initialisieren
var canvasElement = null;
var statusElement = null;
var progressElement = null;
var spinnerElement = null;

// Initialzuweisung des Emscripten Module-Objekts
var Module = Module || {};

// SharedArrayBuffer Layout-Konstanten für die WebXR-Engine-Brücke
// Dieses SharedArrayBuffer-Layout wird zwischen dem Main-Thread (XR-Session)
// und dem Engine-Worker (Emscripten Pthreads) geteilt.
//
// Struktur des Buffers:
// [0]   (Int32)  - FRAME_READY Flag (0 = Engine rendert/schläft, 1 = Neue Pose bereit)
// [4]   (Float32) - HMD-Pose: Position (x, y, z) + Orientierung (x, y, z, w) -> 7 Floats (28 Bytes)
// [32]  (Float32) - Left Eye View Matrix (16 Floats -> 64 Bytes)
// [96]  (Float32) - Left Eye Projection Matrix (16 Floats -> 64 Bytes)
// [160] (Float32) - Right Eye View Matrix (16 Floats -> 64 Bytes)
// [224] (Float32) - Right Eye Projection Matrix (16 Floats -> 64 Bytes)
// [288] (Float32) - Controller Left: Position (3), Orientierung (4) -> 7 Floats (28 Bytes)
// [320] (Float32) - Controller Left: Achsen/Tasten (Gamepad-Daten: 2 Trigger/Grip + 2 Stick x/y + 4 Tasten/Zustände) -> 8 Floats (32 Bytes)
// [352] (Float32) - Controller Right: Position (3), Orientierung (4) -> 7 Floats (28 Bytes)
// [384] (Float32) - Controller Right: Achsen/Tasten (Gamepad-Daten) -> 8 Floats (32 Bytes)
// [416] (Int32)  - CONTROLLERS_ACTIVE Flag (Bitmaske für aktiven linken [bit 0] und rechten [bit 1] Controller)
// Gesamtgröße des zugewiesenen Bereichs: 512 Bytes (aufgerundet für Alignment)

var FRAME_READY_OFFSET = 0;       // Int32 (4 Bytes)
var HMD_POSE_OFFSET = 4;          // Float32[7] (28 Bytes)
var LEFT_VIEW_OFFSET = 32;        // Float32[16] (64 Bytes)
var LEFT_PROJ_OFFSET = 96;        // Float32[16] (64 Bytes)
var RIGHT_VIEW_OFFSET = 160;      // Float32[16] (64 Bytes)
var RIGHT_PROJ_OFFSET = 224;      // Float32[16] (64 Bytes)
var CONTROLLER_L_POSE = 288;      // Float32[7] (28 Bytes)
var CONTROLLER_L_DATA = 320;      // Float32[8] (32 Bytes)
var CONTROLLER_R_POSE = 352;      // Float32[7] (28 Bytes)
var CONTROLLER_R_DATA = 384;      // Float32[8] (32 Bytes)
var CONTROLLER_ACTIVE_OFFSET = 416; // Int32 (4 Bytes)

// Kompatibilitäts- und Featurecheck
(function() {
  var isSabSupported = typeof SharedArrayBuffer !== 'undefined';
  var isWebGL2Supported = !!document.createElement('canvas').getContext('webgl2');
  var isCrossIsolated = window.crossOriginIsolated === true;

  console.log('[PRE-INIT] SharedArrayBuffer Support:', isSabSupported ? 'OK' : 'FEHLT');
  console.log('[PRE-INIT] WebGL2 Support:', isWebGL2Supported ? 'OK' : 'FEHLT');
  console.log('[PRE-INIT] crossOriginIsolated:', isCrossIsolated ? 'JA' : 'NEIN');

  if (!isSabSupported || !isCrossIsolated) {
    console.warn('[PRE-INIT] WARNUNG: COOP/COEP Header oder SharedArrayBuffer fehlen! Der Engine-Worker benötigt diese Features.');
  }
})();
