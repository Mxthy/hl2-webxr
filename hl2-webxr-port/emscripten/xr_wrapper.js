/**
 * xr_wrapper.js - Native WebXR-Schnittstelle & Asset-Pipeline für den Half-Life 2 Quest 3 Port.
 * 
 * Behandelt:
 * 1. WebXR-Session Lifecycle (immersive-vr)
 * 2. SharedArrayBuffer Bridge zur Übertragung von Sensor- & Controller-Daten in Echtzeit an den Worker
 * 3. OPFS (Origin Private File System) Speicherzugriff & Custom Binary Chunk-Unpacking
 * 4. Engine-Klick Start-Promise Pattern
 */

(function() {
  'use strict';

  // Globale Wrapper-Instanz registrieren
  const xrWrapper = {
    session: null,
    gl: null,
    xrRefSpace: null,
    sab: null,
    sharedIntView: null,
    sharedFloatView: null,
    isXRAvailable: false,
    engineChoiceResolver: null,
    gamePromise: null
  };

  // Promise-Pattern für die Spieleauswahl. Die Engine blockiert bis hier resolve aufgerufen wird.
  xrWrapper.gamePromise = new Promise((resolve) => {
    xrWrapper.resolveGameChoice = function(gameName) {
      console.log(`[XR-WRAPPER] Spiel-Entscheidung getroffen: ${gameName}`);
      // Setzt die globale Variable, die Emscripten auswertet
      Module.__gameChoice = gameName;
      resolve(gameName);
    };
  });

  // ==========================================
  // WebXR Check & Button Setup
  // ==========================================
  async function initWebXRCheck() {
    if (navigator.xr) {
      try {
        const isSupported = await navigator.xr.isSessionSupported('immersive-vr');
        xrWrapper.isXRAvailable = isSupported;
        if (isSupported) {
          console.log('[XR-WRAPPER] WebXR "immersive-vr" wird von diesem Browser unterstützt!');
          const btnXR = document.getElementById('btn-enter-xr');
          if (btnXR) {
            btnXR.style.display = 'block';
            btnXR.addEventListener('click', () => enterVR());
          }
        } else {
          console.log('[XR-WRAPPER] WebXR "immersive-vr" wird nicht unterstützt.');
        }
      } catch (err) {
        console.error('[XR-WRAPPER] Fehler beim WebXR Support-Check:', err);
      }
    } else {
      console.log('[XR-WRAPPER] WebXR API (navigator.xr) fehlt in diesem Browser.');
    }
  }

  // ==========================================
  // SharedArrayBuffer (SAB) Setup
  // ==========================================
  function initSharedArrayBuffer() {
    // 512 Bytes Puffer für Pose, Matrizen und Controllereingaben
    xrWrapper.sab = new SharedArrayBuffer(512);
    xrWrapper.sharedIntView = new Int32Array(xrWrapper.sab);
    xrWrapper.sharedFloatView = new Float32Array(xrWrapper.sab);

    // Initialisieren des Frame-Ready Flags auf 0
    Atomics.store(xrWrapper.sharedIntView, FRAME_READY_OFFSET / 4, 0);
    // Controller-Aktivitätsflag auf 0 (beide inaktiv)
    Atomics.store(xrWrapper.sharedIntView, CONTROLLER_ACTIVE_OFFSET / 4, 0);

    console.log('[XR-WRAPPER] SharedArrayBuffer für HMD & Controller-Bridge erstellt.');
    
    // Lege den Puffer global auf window ab, damit der Engine-Worker / Emscripten-Code darauf zugreifen kann.
    window.xrSharedBuffer = xrWrapper.sab;
  }

  // ==========================================
  // WebXR Session starten
  // ==========================================
  async function enterVR() {
    if (!xrWrapper.isXRAvailable) {
      alert('WebXR ist auf diesem Gerät nicht verfügbar.');
      return;
    }

    try {
      console.log('[XR-WRAPPER] Fordere immersive-vr WebXR-Sitzung an...');
      const session = await navigator.xr.requestSession('immersive-vr', {
        requiredFeatures: ['local-floor']
      });

      xrWrapper.session = session;
      session.addEventListener('end', onXRSessionEnded);

      // WebGL2 Context für das Rendering vorbereiten
      const canvas = window.canvasElement || document.getElementById('canvas');
      const gl = canvas.getContext('webgl2', { xrCompatible: true });
      xrWrapper.gl = gl;

      // XR-GLES Framebuffer-Layer anlegen
      const xrLayer = new XRWebGLLayer(session, gl);
      await session.updateRenderState({ baseLayer: xrLayer });

      // Lokalen Boden-Referenzraum anfordern
      const refSpace = await session.requestReferenceSpace('local-floor');
      xrWrapper.xrRefSpace = refSpace;

      console.log('[XR-WRAPPER] WebXR Session erfolgreich gestartet und konfiguriert.');

      // Start der WebXR Render-Loop im Main-Thread
      session.requestAnimationFrame(onXRFrame);

    } catch (err) {
      console.error('[XR-WRAPPER] Fehler beim Starten der WebXR-Session:', err);
      alert('Konnte WebXR-Session nicht starten: ' + err.message);
    }
  }

  function onXRSessionEnded() {
    console.log('[XR-WRAPPER] WebXR Session wurde beendet.');
    xrWrapper.session = null;
    // Fallback auf die reguläre Canvas-Render-Loop (falls vorhanden)
  }

  // ==========================================
  // Haupt-WebXR Frame-Loop
  // ==========================================
  function onXRFrame(time, frame) {
    const session = xrWrapper.session;
    if (!session) return;

    // Fordere direkt den nächsten Frame an
    session.requestAnimationFrame(onXRFrame);

    const pose = frame.getViewerPose(xrWrapper.xrRefSpace);
    if (pose) {
      const gl = xrWrapper.gl;
      const layer = session.renderState.baseLayer;
      gl.bindFramebuffer(gl.FRAMEBUFFER, layer.framebuffer);

      // 1. HMD Pose extrahieren und in den SAB schreiben (Position + Orientierung)
      const hmdPos = pose.transform.position;
      const hmdRot = pose.transform.orientation;

      xrWrapper.sharedFloatView[HMD_POSE_OFFSET / 4]     = hmdPos.x;
      xrWrapper.sharedFloatView[(HMD_POSE_OFFSET / 4) + 1] = hmdPos.y;
      xrWrapper.sharedFloatView[(HMD_POSE_OFFSET / 4) + 2] = hmdPos.z;

      xrWrapper.sharedFloatView[(HMD_POSE_OFFSET / 4) + 3] = hmdRot.x;
      xrWrapper.sharedFloatView[(HMD_POSE_OFFSET / 4) + 4] = hmdRot.y;
      xrWrapper.sharedFloatView[(HMD_POSE_OFFSET / 4) + 5] = hmdRot.z;
      xrWrapper.sharedFloatView[(HMD_POSE_OFFSET / 4) + 6] = hmdRot.w;

      // 2. Augen Matrizen (View- und Projektions-Matrizen) in SAB übertragen
      let hasLeftEye = false;
      let hasRightEye = false;

      for (const view of pose.views) {
        if (view.eye === 'left') {
          hasLeftEye = true;
          // View-Matrix & Projektions-Matrix kopieren (jeweils Float32Array[16])
          // Die View-Matrix entspricht der inversen Transform-Matrix des Auges
          const viewMat = view.transform.inverse.matrix;
          const projMat = view.projectionMatrix;
          for (let i = 0; i < 16; i++) {
            xrWrapper.sharedFloatView[(LEFT_VIEW_OFFSET / 4) + i] = viewMat[i];
            xrWrapper.sharedFloatView[(LEFT_PROJ_OFFSET / 4) + i] = projMat[i];
          }
        } else if (view.eye === 'right') {
          hasRightEye = true;
          const viewMat = view.transform.inverse.matrix;
          const projMat = view.projectionMatrix;
          for (let i = 0; i < 16; i++) {
            xrWrapper.sharedFloatView[(RIGHT_VIEW_OFFSET / 4) + i] = viewMat[i];
            xrWrapper.sharedFloatView[(RIGHT_PROJ_OFFSET / 4) + i] = projMat[i];
          }
        }
      }

      // 3. Controller Inputs auslesen
      let controllersActiveMask = 0;
      const inputSources = session.inputSources;

      for (const input of inputSources) {
        if (input.gripSpace && input.gamepad) {
          const isLeft = input.handedness === 'left';
          const offsetPose = isLeft ? CONTROLLER_L_POSE : CONTROLLER_R_POSE;
          const offsetData = isLeft ? CONTROLLER_L_DATA : CONTROLLER_R_DATA;

          // Controller-Pose im Raum holen
          const ctrlPose = frame.getPose(input.gripSpace, xrWrapper.xrRefSpace);
          if (ctrlPose) {
            controllersActiveMask |= isLeft ? 1 : 2;

            const cPos = ctrlPose.transform.position;
            const cRot = ctrlPose.transform.orientation;

            xrWrapper.sharedFloatView[offsetPose / 4]       = cPos.x;
            xrWrapper.sharedFloatView[(offsetPose / 4) + 1] = cPos.y;
            xrWrapper.sharedFloatView[(offsetPose / 4) + 2] = cPos.z;

            xrWrapper.sharedFloatView[(offsetPose / 4) + 3] = cRot.x;
            xrWrapper.sharedFloatView[(offsetPose / 4) + 4] = cRot.y;
            xrWrapper.sharedFloatView[(offsetPose / 4) + 5] = cRot.z;
            xrWrapper.sharedFloatView[(offsetPose / 4) + 6] = cRot.w;
          }

          // Gamepad / Button- / Achsendaten auslesen
          const gp = input.gamepad;
          if (gp && gp.buttons.length >= 2 && gp.axes.length >= 2) {
            // Layout im SAB:
            // [0] = Trigger (Button 0 Wert)
            // [1] = Grip (Button 1 Wert)
            // [2] = Thumbstick X (-1 links, +1 rechts)
            // [3] = Thumbstick Y (-1 oben, +1 unten)
            // [4] = Button A / X gedrückt (0 oder 1)
            // [5] = Button B / Y gedrückt (0 oder 1)
            // [6] = Thumbstick Klick (0 oder 1)
            // [7] = System/Menu Button (0 oder 1)
            
            xrWrapper.sharedFloatView[offsetData / 4]       = gp.buttons[0].value; // Trigger
            xrWrapper.sharedFloatView[(offsetData / 4) + 1] = gp.buttons[1].value; // Grip
            xrWrapper.sharedFloatView[(offsetData / 4) + 2] = gp.axes[2] || gp.axes[0] || 0.0; // Thumbstick X
            xrWrapper.sharedFloatView[(offsetData / 4) + 3] = gp.axes[3] || gp.axes[1] || 0.0; // Thumbstick Y
            
            // Buttons A/X (Index 4) und B/Y (Index 5)
            xrWrapper.sharedFloatView[(offsetData / 4) + 4] = gp.buttons[4] && gp.buttons[4].pressed ? 1.0 : 0.0;
            xrWrapper.sharedFloatView[(offsetData / 4) + 5] = gp.buttons[5] && gp.buttons[5].pressed ? 1.0 : 0.0;
            
            // Thumbstick-Button (meistens Index 3 oder 10)
            xrWrapper.sharedFloatView[(offsetData / 4) + 6] = gp.buttons[3] && gp.buttons[3].pressed ? 1.0 : 0.0;
            // Menu-Button (Index 2 oder 6)
            xrWrapper.sharedFloatView[(offsetData / 4) + 7] = gp.buttons[2] && gp.buttons[2].pressed ? 1.0 : 0.0;
          }
        }
      }

      // Aktualisiere das Aktivitäts-Flag der Controller im SAB
      Atomics.store(xrWrapper.sharedIntView, CONTROLLER_ACTIVE_OFFSET / 4, controllersActiveMask);

      // 4. Benachrichtige den Engine-Worker, dass neue Pose-Daten vorliegen
      Atomics.store(xrWrapper.sharedIntView, FRAME_READY_OFFSET / 4, 1);
      Atomics.notify(xrWrapper.sharedIntView, FRAME_READY_OFFSET / 4, 1);
    }
  }

  // ==========================================
  // OPFS DataLoader & Custom Binary Unpacker (slqnt.dev-style)
  // ==========================================
  
  /**
   * Lädt Asset-Chunks herunter, cacht diese im OPFS und entpackt sie ins Emscripten MEMFS.
   * Format des slqnt-Asset-Packers:
   * [pathLen: int32][dataLen: int32][path: UTF-8 string][data: binary]
   */
  async function loadAndUnpackAssets(gameName, progressCallback) {
    console.log(`[OPFS] Starte Laden der Asset-Pakete für ${gameName}...`);

    // Manifest anfordern
    const manifestResp = await fetch(`chunks/manifest.json`);
    if (!manifestResp.ok) throw new Error('Manifest-Datei chunks/manifest.json konnte nicht geladen werden.');
    const manifest = await manifestResp.json();

    const gameAssets = manifest[gameName] || [];
    if (gameAssets.length === 0) {
      throw new Error(`Keine Assets für Spiel '${gameName}' im Manifest gefunden.`);
    }

    // OPFS Directory Handle abfragen
    const root = await navigator.storage.getDirectory();
    
    let totalBytes = gameAssets.reduce((sum, asset) => sum + asset.size, 0);
    let bytesLoaded = 0;

    for (const asset of gameAssets) {
      const fileName = asset.file;
      const fileSize = asset.size;
      
      console.log(`[OPFS] Verarbeite Paket: ${fileName} (${(fileSize/1024/1024).toFixed(1)}MB)`);
      
      let fileData;
      try {
        // Prüfe ob bereits lokal im OPFS gecacht
        const fileHandle = await root.getFileHandle(fileName);
        const file = await fileHandle.getFile();
        if (file.size === fileSize) {
          console.log(`[OPFS] ${fileName} ist bereits vollständig im Cache.`);
          fileData = await file.arrayBuffer();
          bytesLoaded += fileSize;
          if (progressCallback) progressCallback(bytesLoaded, totalBytes);
        } else {
          throw new Error('Größe ungleich, lade neu herunter');
        }
      } catch (e) {
        // Nicht im Cache oder unvollständig -> neu herunterladen via Chunked Transfer
        console.log(`[OPFS] Lade ${fileName} herunter...`);
        fileData = await downloadInChunks(`chunks/${fileName}`, 50 * 1024 * 1024, (chunkLoaded) => {
          if (progressCallback) progressCallback(bytesLoaded + chunkLoaded, totalBytes);
        });

        // Im OPFS wegspeichern
        const newFileHandle = await root.getFileHandle(fileName, { create: true });
        const writable = await newFileHandle.createWritable();
        await writable.write(fileData);
        await writable.close();
        console.log(`[OPFS] ${fileName} erfolgreich in OPFS gespeichert.`);
        bytesLoaded += fileSize;
      }

      // In das virtuelle Emscripten-MEMFS entpacken
      unpackIntoMemfs(fileData);
    }
  }

  /**
   * Lädt eine Datei in Segmenten herunter (HTTP Range-Header)
   */
  async function downloadInChunks(url, chunkSize, chunkCallback) {
    const head = await fetch(url, { method: 'HEAD' });
    const totalSize = parseInt(head.headers.get('content-length'));
    
    const chunks = [];
    let loaded = 0;

    for (let start = 0; start < totalSize; start += chunkSize) {
      const end = Math.min(start + chunkSize - 1, totalSize - 1);
      const resp = await fetch(url, {
        headers: { Range: `bytes=${start}-${end}` }
      });

      if (!resp.ok && resp.status !== 206) {
        throw new Error(`Fehler beim Laden von Segment ${start}-${end}. Status: ${resp.status}`);
      }

      const buf = await resp.arrayBuffer();
      chunks.push(buf);
      loaded += buf.byteLength;
      if (chunkCallback) chunkCallback(loaded);
    }

    const merged = new Uint8Array(totalSize);
    let offset = 0;
    for (const c of chunks) {
      merged.set(new Uint8Array(c), offset);
      offset += c.byteLength;
    }
    return merged.buffer;
  }

  /**
   * Entpackt das Custom-Binary-Format ins Emscripten MEMFS
   * [pathLen: int32][dataLen: int32][path: string][data: binary]
   */
  function unpackIntoMemfs(buffer) {
    const view = new DataView(buffer);
    let offset = 0;
    const totalLen = buffer.byteLength;
    const decoder = new TextDecoder('utf-8');

    console.log(`[MEMFS] Entpacke Binärpaket in MEMFS...`);

    while (offset < totalLen) {
      if (offset + 8 > totalLen) break;

      const pathLen = view.getInt32(offset, true);
      const dataLen = view.getInt32(offset + 4, true);
      offset += 8;

      if (offset + pathLen + dataLen > totalLen) {
        console.error('[MEMFS] Paket beschädigt! Offset-Overflow beim Entpacken.');
        break;
      }

      const pathBytes = new Uint8Array(buffer, offset, pathLen);
      const path = decoder.decode(pathBytes);
      offset += pathLen;

      const dataBytes = new Uint8Array(buffer, offset, dataLen);
      offset += dataLen;

      // Verzeichnispfad extrahieren und im MEMFS anlegen
      const pathParts = path.split('/');
      let currentPath = '';
      for (let i = 0; i < pathParts.length - 1; i++) {
        currentPath += (i === 0 ? '' : '/') + pathParts[i];
        try {
          FS.mkdir(currentPath);
        } catch (e) {
          // FS.mkdir wirft einen Fehler, wenn der Ordner bereits existiert, das können wir ignorieren
        }
      }

      // Datei im MEMFS schreiben (FS ist das globale Emscripten-Dateisystem)
      try {
        FS.writeFile(path, dataBytes, { encoding: 'binary' });
      } catch (err) {
        console.error(`[MEMFS] Fehler beim Schreiben der Datei ${path}:`, err);
      }
    }
    console.log('[MEMFS] Paket erfolgreich entpackt.');
  }

  // Engine Initialisierungsbrücke
  function onEngineInitialized() {
    console.log('[XR-WRAPPER] Engine ist bereit und wartet auf Shared Array Buffer.');
  }

  // ==========================================
  // Expose an Window
  // ==========================================
  xrWrapper.onEngineInitialized = onEngineInitialized;
  xrWrapper.loadAndUnpackAssets = loadAndUnpackAssets;
  window.xrWrapper = xrWrapper;

  // Initialisierung anstoßen
  initWebXRCheck();
  initSharedArrayBuffer();

})();
