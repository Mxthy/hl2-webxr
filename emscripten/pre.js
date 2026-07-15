// pre.js — Globale Variablen + SharedArrayBuffer Layout
// Wird von emcc --pre-js eingebunden (vor dem generierten Emscripten-Code)

// DOM-Referenzen (werden von index.html gesetzt, hier als Fallback)
var canvasElement = window.canvasElement || document.getElementById('canvas');
var statusElement = window.statusElement || document.getElementById('status');
var progressElement = window.progressElement || document.getElementById('progress');
var spinnerElement = window.spinnerElement || document.getElementById('spinner');

// Emscripten Module-Objekt initialisieren
var Module = Module || {};

// SharedArrayBuffer Layout-Konstanten für XR-Bridge
// Struktur (512 Bytes):
// [0]   Int32   FRAME_READY (0=Engine wartet, 1=neue Pose bereit)
// [4]   Float32[7]  HMD Pose: pos(x,y,z) + rot(x,y,z,w)
// [32]  Float32[16] Left Eye View Matrix
// [96]  Float32[16] Left Eye Projection Matrix
// [160] Float32[16] Right Eye View Matrix
// [224] Float32[16] Right Eye Projection Matrix
// [288] Float32[7]  Controller Left Pose: pos(x,y,z) + rot(x,y,z,w)
// [320] Float32[8]  Controller Left Data: stickX,stickY,trigger,grip,A,B,thumbClick,menu
// [352] Float32[7]  Controller Right Pose
// [384] Float32[8]  Controller Right Data
// [416] Int32   CONTROLLERS_ACTIVE Bitmaske (bit0=left, bit1=right)
var FRAME_READY_OFFSET    = 0;
var HMD_POSE_OFFSET       = 4;
var LEFT_VIEW_OFFSET      = 32;
var LEFT_PROJ_OFFSET      = 96;
var RIGHT_VIEW_OFFSET     = 160;
var RIGHT_PROJ_OFFSET     = 224;
var CONTROLLER_L_POSE     = 288;
var CONTROLLER_L_DATA     = 320;
var CONTROLLER_R_POSE     = 352;
var CONTROLLER_R_DATA     = 384;
var CONTROLLER_ACTIVE_OFFSET = 416;

// Feature-Check
(function() {
  var sab = typeof SharedArrayBuffer !== 'undefined';
  var wgl2 = !!document.createElement('canvas').getContext('webgl2');
  var coi = window.crossOriginIsolated === true;
  console.log('[PRE] SAB:', sab ? 'OK' : 'FEHLT', '| WebGL2:', wgl2 ? 'OK' : 'FEHLT', '| crossOriginIsolated:', coi ? 'JA' : 'NEIN');
  if (!sab || !coi) {
    console.warn('[PRE] WARNUNG: SharedArrayBuffer benötigt COOP/COEP-Header!');
  }
})();
