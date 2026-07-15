// xr_wrapper.js — WebXR Session Manager & SharedArrayBuffer Bridge
// Verbindet den WebXR Main-Thread mit dem Emscripten Engine-Worker (PROXY_TO_PTHREAD)
// Keine Frameworks — native WebXR API direkt

(function () {
  'use strict';

  // ============================================================
  // SharedArrayBuffer Layout (512 Bytes) — Konstanten aus pre.js
  // FRAME_READY_OFFSET=0, HMD_POSE_OFFSET=4,
  // LEFT_VIEW_OFFSET=32, LEFT_PROJ_OFFSET=96,
  // RIGHT_VIEW_OFFSET=160, RIGHT_PROJ_OFFSET=224,
  // CONTROLLER_L_POSE=288, CONTROLLER_L_DATA=320,
  // CONTROLLER_R_POSE=352, CONTROLLER_R_DATA=384,
  // CONTROLLER_ACTIVE_OFFSET=416
  // ============================================================
  var SAB_SIZE = 512;

  var state = {
    session:    null,
    refSpace:   null,
    glCtx:      null,
    baseLayer:  null,
    xrSAB:      null,  // SharedArrayBuffer
    xrI32:      null,  // Int32Array view
    xrF32:      null,  // Float32Array view
    isVR:       false,
    frames:     0,
  };

  // ============================================================
  // Init (wird sofort beim Laden ausgeführt)
  // ============================================================
  function init() {
    if (!navigator.xr) {
      console.log('[XR] WebXR nicht verfügbar — Desktop-Modus');
      return;
    }
    navigator.xr.isSessionSupported('immersive-vr')
      .then(function (ok) {
        console.log('[XR] immersive-vr unterstützt:', ok);
      })
      .catch(function (e) {
        console.warn('[XR] isSessionSupported Fehler:', e);
      });
  }

  // ============================================================
  // enterVR — durch Nutzer-Geste ausgelöst
  // ============================================================
  async function enterVR() {
    if (state.session) { console.log('[XR] Session läuft bereits'); return; }

    try {
      var session = await navigator.xr.requestSession('immersive-vr', {
        requiredFeatures: ['local-floor'],
        optionalFeatures: ['bounded-floor', 'hand-tracking'],
      });

      state.session = session;
      state.isVR    = true;
      console.log('[XR] Session gestartet');

      // WebGL2-Kontext vom Canvas
      var canvas = window.canvasElement || document.getElementById('canvas');
      var gl = canvas.getContext('webgl2', {
        xrCompatible:        true,
        antialias:           false,
        powerPreference:     'high-performance',
        preserveDrawingBuffer: false,
      });
      if (!gl) { console.error('[XR] Kein WebGL2-Kontext!'); return; }
      state.glCtx = gl;

      await gl.makeXRCompatible();

      // XRWebGLLayer als Render-Target
      var baseLayer = new XRWebGLLayer(session, gl, {
        antialias:               false,
        depth:                   true,
        stencil:                 false,
        alpha:                   false,
        framebufferScaleFactor:  1.0,
      });
      session.updateRenderState({ baseLayer: baseLayer });
      state.baseLayer = baseLayer;

      // Reference Space
      state.refSpace = await session.requestReferenceSpace('local-floor');

      session.addEventListener('end', function () {
        console.log('[XR] Session beendet');
        state.session  = null;
        state.isVR     = false;
        state.refSpace = null;
        state.baseLayer= null;
      });

      initSAB();
      session.requestAnimationFrame(onXRFrame);
      console.log('[XR] Frame Loop gestartet!');

    } catch (e) {
      console.error('[XR] enterVR Fehler:', e);
    }
  }

  // ============================================================
  // SharedArrayBuffer initialisieren
  // ============================================================
  function initSAB() {
    if (state.xrSAB) return;
    try {
      state.xrSAB = new SharedArrayBuffer(SAB_SIZE);
      state.xrI32 = new Int32Array(state.xrSAB);
      state.xrF32 = new Float32Array(state.xrSAB);
      Atomics.store(state.xrI32, 0, 0); // FRAME_READY = 0
      console.log('[XR] SAB initialisiert (' + SAB_SIZE + ' Bytes)');
    } catch (e) {
      console.warn('[XR] SharedArrayBuffer nicht verfügbar:', e);
    }
  }

  // ============================================================
  // XR Frame Loop
  // ============================================================
  function onXRFrame(time, frame) {
    frame.session.requestAnimationFrame(onXRFrame);
    state.frames++;

    var pose = frame.getViewerPose(state.refSpace);
    if (!pose) return;

    if (state.xrF32 && state.xrI32) {
      var f   = state.xrF32;
      var i32 = state.xrI32;
      var t   = pose.transform;

      // HMD Pose (Float32-Index 1 = Byte-Offset 4)
      f[1] = t.position.x;
      f[2] = t.position.y;
      f[3] = t.position.z;
      f[4] = t.orientation.x;
      f[5] = t.orientation.y;
      f[6] = t.orientation.z;
      f[7] = t.orientation.w;

      // Augen-Matrizen (View + Projection)
      for (var vi = 0; vi < pose.views.length; vi++) {
        var view    = pose.views[vi];
        var isLeft  = view.eye === 'left';
        var vBase   = isLeft ?  8 : 40;   // LEFT_VIEW=32/idx8,  RIGHT_VIEW=160/idx40
        var pBase   = isLeft ? 24 : 56;   // LEFT_PROJ=96/idx24, RIGHT_PROJ=224/idx56
        var vm = view.transform.inverse.matrix;
        var pm = view.projectionMatrix;
        for (var i = 0; i < 16; i++) {
          f[vBase + i] = vm[i];
          f[pBase + i] = pm[i];
        }
      }

      writeControllers(frame);

      // Engine wecken
      Atomics.store(i32, 0, 1);
      Atomics.notify(i32, 0, 1);
    }

    // XR-Framebuffer binden (Engine rendert selbst hinein)
    if (state.baseLayer && state.glCtx) {
      state.glCtx.bindFramebuffer(state.glCtx.FRAMEBUFFER, state.baseLayer.framebuffer);
    }
  }

  // ============================================================
  // Controller Input
  // ============================================================
  function writeControllers(frame) {
    if (!state.xrF32 || !state.xrI32) return;
    var f   = state.xrF32;
    var i32 = state.xrI32;
    var active = 0;

    var sources = Array.from(frame.session.inputSources);
    for (var si = 0; si < sources.length; si++) {
      var src    = sources[si];
      var isLeft = src.handedness === 'left';
      var pBase  = isLeft ? 72 : 88;   // L_POSE=288/idx72, R_POSE=352/idx88
      var dBase  = isLeft ? 80 : 96;   // L_DATA=320/idx80, R_DATA=384/idx96

      if (src.targetRaySpace) {
        var cp = frame.getPose(src.targetRaySpace, state.refSpace);
        if (cp) {
          var ct = cp.transform;
          f[pBase+0] = ct.position.x;
          f[pBase+1] = ct.position.y;
          f[pBase+2] = ct.position.z;
          f[pBase+3] = ct.orientation.x;
          f[pBase+4] = ct.orientation.y;
          f[pBase+5] = ct.orientation.z;
          f[pBase+6] = ct.orientation.w;
          active |= isLeft ? 1 : 2;
        }
      }

      if (src.gamepad) {
        var gp = src.gamepad;
        f[dBase+0] = gp.axes[0]  || 0;                                        // Stick X
        f[dBase+1] = gp.axes[1]  || 0;                                        // Stick Y
        f[dBase+2] = gp.buttons[0] ? gp.buttons[0].value : 0;                 // Trigger
        f[dBase+3] = gp.buttons[1] ? gp.buttons[1].value : 0;                 // Grip
        f[dBase+4] = (gp.buttons[4] && gp.buttons[4].pressed) ? 1 : 0;       // A/X
        f[dBase+5] = (gp.buttons[5] && gp.buttons[5].pressed) ? 1 : 0;       // B/Y
        f[dBase+6] = (gp.buttons[3] && gp.buttons[3].pressed) ? 1 : 0;       // Thumbstick-Klick
        f[dBase+7] = (gp.buttons[6] && gp.buttons[6].pressed) ? 1 : 0;       // Menu
      }
    }

    // CONTROLLERS_ACTIVE (Int32-Index 104 = Byte-Offset 416)
    Atomics.store(i32, 104, active);
  }

  // ============================================================
  // OPFS DataLoader (wie slqnt — Assets aus chunks/ laden)
  // ============================================================
  var OPFS_DIR = 'hl2_chunks';

  function DataLoader() {
    this._opfsDir       = null;
    this.loadedMaps     = {};
    this._reconcileP    = null;
  }

  DataLoader.prototype.getOpfsDir = async function () {
    if (!this._opfsDir) {
      var root = await navigator.storage.getDirectory();
      this._opfsDir = await root.getDirectoryHandle(OPFS_DIR, { create: true });
    }
    return this._opfsDir;
  };

  DataLoader.prototype.opfsRead = async function (name) {
    try {
      var dir = await this.getOpfsDir();
      var fh  = await dir.getFileHandle(name);
      return await (await fh.getFile()).arrayBuffer();
    } catch (e) { return null; }
  };

  DataLoader.prototype.opfsWrite = async function (name, data) {
    try {
      var dir = await this.getOpfsDir();
      var tmp = name + '.tmp';
      var fh  = await dir.getFileHandle(tmp, { create: true });
      var w   = await fh.createWritable();
      await w.write(data);
      await w.close();
      try { await fh.move(name); }
      catch {
        var final = await dir.getFileHandle(name, { create: true });
        var fw = await final.createWritable();
        await fw.write(data); await fw.close();
        await dir.removeEntry(tmp).catch(function(){});
      }
      return true;
    } catch (e) {
      console.warn('[DataLoader] opfsWrite fehlgeschlagen:', name, e);
      return false;
    }
  };

  DataLoader.prototype.reconcileManifest = function () {
    return this._reconcileP || (this._reconcileP = this._doReconcile());
  };

  DataLoader.prototype._doReconcile = async function () {
    var newMf = null;
    try {
      var res = await fetch('chunks/manifest.json', { cache: 'no-store' });
      if (res.ok) newMf = await res.json();
    } catch (e) {}
    if (!newMf) return;

    var oldMf = {};
    var saved = await this.opfsRead('manifest.json');
    if (saved) { try { oldMf = JSON.parse(new TextDecoder().decode(saved)); } catch(e){} }

    for (var name in newMf) {
      if (oldMf[name] !== newMf[name]) {
        try { var d = await this.getOpfsDir(); await d.removeEntry(name + '.data'); } catch(e) {}
      }
    }
    await this.opfsWrite('manifest.json', new TextEncoder().encode(JSON.stringify(newMf)));
    console.log('[DataLoader] Manifest synchronisiert');
  };

  DataLoader.prototype.loadMap = function (mapName) {
    if (!this.loadedMaps[mapName]) {
      this.loadedMaps[mapName] = this._loadImpl(mapName);
    }
    return this.loadedMaps[mapName];
  };

  DataLoader.prototype._loadImpl = async function (mapName) {
    await this.reconcileManifest();
    var fileName = mapName + '.data';
    var buffer = await this.opfsRead(fileName);
    if (!buffer) {
      if (window.statusElement) window.statusElement.textContent = 'Lädt: ' + mapName;
      buffer = await this._fetchMap(mapName);
      await this.opfsWrite(fileName, buffer);
    }
    this._unpack(buffer);
    console.log('[DataLoader] Geladen:', mapName);
  };

  DataLoader.prototype._fetchMap = function (mapName) {
    return new Promise(function (resolve, reject) {
      var xhr = new XMLHttpRequest();
      xhr.responseType = 'arraybuffer';
      xhr.onprogress = function (e) {
        if (e.lengthComputable && window.progressElement) {
          window.progressElement.hidden = false;
          window.progressElement.value  = (e.loaded / e.total) * 100;
        }
      };
      xhr.onerror  = function () { reject(new Error('Fetch fehlgeschlagen: ' + mapName)); };
      xhr.onload   = function () {
        if (xhr.status >= 200 && xhr.status < 300) resolve(xhr.response);
        else reject(new Error('HTTP ' + xhr.status + ': ' + mapName));
      };
      xhr.open('GET', 'chunks/' + mapName + '.data', true);
      xhr.send();
    });
  };

  // Custom Binary Format: [pathLen int32][dataLen int32][path UTF-8][data bytes]
  DataLoader.prototype._unpack = function (buffer) {
    if (typeof FS === 'undefined') { console.warn('[DataLoader] FS nicht verfügbar'); return; }
    var dv = new DataView(buffer);
    var off = 0;
    while (off < dv.byteLength) {
      var pathLen = dv.getInt32(off, true);
      var dataLen = dv.getInt32(off + 4, true);
      var path    = new TextDecoder().decode(new DataView(buffer, off + 8, pathLen));
      var data    = new Uint8Array(buffer, off + 8 + pathLen, dataLen);
      off += 8 + pathLen + dataLen;
      var dir = path.replace(/\/[^/]+$/, '');
      if (dir) FS.mkdirTree(dir);
      FS.writeFile(path, data);
    }
  };

  // ============================================================
  // onEngineInitialized — von post.js aufgerufen
  // ============================================================
  function onEngineInitialized() {
    console.log('[XR] Engine initialisiert — SAB aktiv');
    initSAB();
  }

  // ============================================================
  // Public API
  // ============================================================
  window.xrWrapper = {
    enterVR:              enterVR,
    onEngineInitialized:  onEngineInitialized,
    getSession:           function () { return state.session; },
    isVRActive:           function () { return state.isVR; },
    getSharedBuffer:      function () { return state.xrSAB; },
    DataLoader:           DataLoader,
  };

  init();

})();
