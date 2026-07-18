// pre.js - Globale Variablen vor dem Emscripten-Bundle initialisieren
// PATCH 1: Safe globals with typeof guards — prevents ReferenceError in worker
var canvasElement = null;
var statusElement = null;
var progressElement = null;
var spinnerElement = null;

// PATCH 2: Canvas transfer config — don't transfer canvas via pthread_create
// The fallback OffscreenCanvas in do_create_context handles GL in worker
var __allowCanvasTransfer = true;
var transferredCanvasNames = ""; // empty = don't attempt canvas transfer via pthread

// Initialzuweisung des Emscripten Module-Objekts
var Module = Module || {};

// SharedArrayBuffer Layout-Konstanten für die WebXR-Engine-Brücke
var FRAME_READY_OFFSET = 0;
var HMD_POSE_OFFSET = 4;
var LEFT_VIEW_OFFSET = 32;
var LEFT_PROJ_OFFSET = 96;
var RIGHT_VIEW_OFFSET = 160;
var RIGHT_PROJ_OFFSET = 224;
var CONTROLLER_L_POSE = 288;
var CONTROLLER_L_DATA = 320;
var CONTROLLER_R_POSE = 352;
var CONTROLLER_R_DATA = 384;
var CONTROLLER_ACTIVE_OFFSET = 416;

// Kompatibilitäts- und Featurecheck
// WICHTIG: Kein canvas.getContext('webgl2') Aufruf im Main-Thread!
// PROXY_TO_PTHREAD benötigt transferControlToOffscreen(), was fehlschlägt
// sobald *irgendein* Code im Main-Thread einen GL-Kontext auf dem Canvas erstellt.
(function() {
  var isSabSupported = typeof SharedArrayBuffer !== 'undefined';
  var isCrossIsolated = typeof self !== 'undefined' && self.crossOriginIsolated === true;

  console.log('[PRE-INIT] SharedArrayBuffer Support:', isSabSupported ? 'OK' : 'FEHLT');
  console.log('[PRE-INIT] crossOriginIsolated:', isCrossIsolated ? 'JA' : 'NEIN');

  if (!isSabSupported || !isCrossIsolated) {
    console.warn('[PRE-INIT] WARNUNG: COOP/COEP Header oder SharedArrayBuffer fehlen!');
  }
})();
