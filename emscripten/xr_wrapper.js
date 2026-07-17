/**
* HL2 WebXR - JavaScript / WASM Bridge
* Verbindet die WebXR API (Headset-Posen) mit den C++ Hooks der Source Engine.
*/

class HL2WebXR {
   constructor(glContext, canvas) {
       this.gl = glContext;
       this.canvas = canvas;
       this.session = null;
       this.refSpace = null;
       
       // WASM Memory Pointer für die 4x4 Matrix (16 Floats = 64 Bytes)
       this.matrixPtr = null;
       this.projPtr = null;
       
       this.onXRFrame = this.onXRFrame.bind(this);
   }

   async init() {
       if (!navigator.xr) {
           console.error("WebXR wird vom Browser nicht unterstützt.");
           return false;
       }

       const supported = await navigator.xr.isSessionSupported('immersive-vr');
       if (!supported) {
           console.warn("VR Headset nicht gefunden oder nicht unterstützt.");
           return false;
       }

       console.log("WebXR VR wird unterstützt. Bereit.");
       return true;
   }

   async enterVR() {
       try {
           console.log("Beantrage WebXR Session...");
           this.session = await navigator.xr.requestSession('immersive-vr');
           this.session.addEventListener('end', () => this.onSessionEnded());

           // Reference Space anfordern (lokal, für seated/standing VR)
           this.refSpace = await this.session.requestReferenceSpace('local');

           // WebGL-Layer in die XR-Session einklinken
           this.session.updateRenderState({
               baseLayer: new XRWebGLLayer(this.session, this.gl)
           });

           // WASM Speicher für die Matrizen allokieren (16 floats * 4 bytes each)
           if (window.Module && Module._malloc) {
               this.matrixPtr = Module._malloc(16 * 4);
               this.projPtr = Module._malloc(16 * 4);
               console.log(`WASM Matrix Pointer: view=${this.matrixPtr}, proj=${this.projPtr}`);
           } else {
               console.error("Kritischer Fehler: Module._malloc ist nicht verfügbar! Ist MAIN_MODULE=1 gesetzt?");
               return;
           }

           // Engine anweisen: Stoppe den automatischen 2D-Renderloop!
           if (window.Module && Module._DisableAutoRenderLoop) {
               Module._DisableAutoRenderLoop();
               console.log("Source Engine Auto-Renderloop deaktiviert.");
           } else if (window.Module && Module._Engine_DisableAutoRender) {
               // Fallback: direct C function (MAIN_MODULE=1 auto-export)
               Module._Engine_DisableAutoRender();
               console.log("Source Engine Auto-Renderloop deaktiviert (direct hook).");
           } else {
               console.warn("Engine_DisableAutoRender nicht gefunden — VR rendering wird nicht korrekt funktionieren.");
           }

           // WebXR Render-Loop starten
           this.session.requestAnimationFrame(this.onXRFrame);
           console.log("WebXR Session läuft.");

       } catch (error) {
           console.error("Fehler beim Starten von WebXR:", error);
       }
   }

   onXRFrame(time, frame) {
       const session = frame.session;
       session.requestAnimationFrame(this.onXRFrame);

       const pose = frame.getViewerPose(this.refSpace);
       if (!pose || !window.Module) return;

       const glLayer = session.renderState.baseLayer;
       this.gl.bindFramebuffer(this.gl.FRAMEBUFFER, glLayer.framebuffer);

       // Wir iterieren über jedes Auge (linkes & rechtes Auge)
       for (const view of pose.views) {
           const viewport = glLayer.getViewport(view);
           this.gl.viewport(viewport.x, viewport.y, viewport.width, viewport.height);

           // 1. Hole die View-Matrix (Kamera Position/Rotation) für dieses Auge
           // WebXR gibt uns die Inverse-Matrix (transform.inverse.matrix), 
           // die wir direkt in OpenGL/SourceEngine nutzen können.
           const viewMatrix = view.transform.inverse.matrix;
           const projMatrix = view.projectionMatrix;

           // 2. Kopiere die Matrizen in den WASM-Heap
           if (this.matrixPtr) {
               // HEAPF32 nutzt Float-Indizes (Byte-Adresse / 4)
               Module.HEAPF32.set(viewMatrix, this.matrixPtr / 4);
               
               // 3. Sag C++: Hier ist die neue Kamera-Matrix!
               // Versuche zuerst die Bridge-Funktion (SetCameraMatrices(view, proj))
               if (Module._SetCameraMatrices) {
                   if (this.projPtr) {
                       Module.HEAPF32.set(projMatrix, this.projPtr / 4);
                       Module._SetCameraMatrices(this.matrixPtr, this.projPtr);
                   } else {
                       Module._SetCameraMatrices(this.matrixPtr, 0);
                   }
               } else if (Module._Engine_SetCameraMatrix) {
                   // Fallback: direct C function
                   Module._Engine_SetCameraMatrix(this.matrixPtr);
                   if (this.projPtr && Module._Engine_SetProjectionMatrix) {
                       Module.HEAPF32.set(projMatrix, this.projPtr / 4);
                       Module._Engine_SetProjectionMatrix(this.projPtr);
                   }
               }
           }

           // 4. Erzwinge das Rendern EINES Frames in der Source Engine
           if (Module._RenderXRFrame) {
               Module._RenderXRFrame();
           } else if (Module._Engine_RenderSingleFrame) {
               // Fallback: direct C function
               Module._Engine_RenderSingleFrame();
           }
       }
   }

   onSessionEnded() {
       console.log("WebXR Session beendet.");
       this.session = null;
       
       // Engine wieder in den Normalmodus versetzen
       if (window.Module && Module._EnableAutoRenderLoop) {
           Module._EnableAutoRenderLoop();
       } else if (window.Module && Module._Engine_ResetCameraMatrix) {
           Module._Engine_ResetCameraMatrix();
       }
       
       // WASM Speicher freigeben
       if (this.matrixPtr && window.Module) {
           Module._free(this.matrixPtr);
           this.matrixPtr = null;
       }
       if (this.projPtr && window.Module) {
           Module._free(this.projPtr);
           this.projPtr = null;
       }
   }
}

// Global verfügbar machen
window.HL2WebXR = HL2WebXR;
