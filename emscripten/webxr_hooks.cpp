// webxr_hooks.cpp — Source Engine hooks for WebXR Phase 2
// Compiled with emcc -O0 and linked into main WASM module.
// These functions are called from webxr_bridge.cpp (EMSCRIPTEN_KEEPALIVE exports)
// to control the engine's render loop from JavaScript (WebXR XRSession).
//
// Build: emcc -O0 -fPIC -D__EMSCRIPTEN__ -c webxr_hooks.cpp -o webxr_hooks.o
// Link:  included in emcc link step alongside webxr_bridge.o

#ifdef __EMSCRIPTEN__

#include <emscripten.h>
#include <string.h>

// ============================================================================
// Global state — shared between hooks and engine rendering code
// ============================================================================

// Set to true when WebXR takes over the render loop
bool g_bWebXRManualLoop = false;

// 4x4 view matrix (column-major, as provided by WebXR XRView.transform.matrix)
float g_WebXRViewMatrix[16] = {0};

// 4x4 projection matrix (column-major, from XRView.projectionMatrix)
float g_WebXRProjectionMatrix[16] = {0};

// When true, ComputeViewMatrix() in gl_rmain.cpp uses g_WebXRViewMatrix
// instead of computing from origin+angles
bool g_bWebXRMatrixActive = false;

// When true, the projection matrix is also overridden
bool g_bWebXRProjectionActive = false;

// ============================================================================
// Step 1: DisableAutoRender — stop the Emscripten-managed 2D main loop
// ============================================================================
// em_loop_iteration() is defined in sys_dll2.cpp inside #ifdef __EMSCRIPTEN__.
// It has external linkage (not static), so we can declare it extern here.
// It calls s_EngineAPI.MainLoopIter() → eng->Frame() → full engine tick.
extern void em_loop_iteration();

extern "C" void Engine_DisableAutoRender() {
    emscripten_cancel_main_loop();
    g_bWebXRManualLoop = true;
    EM_ASM_({ console.log('[WebXR] Engine_DisableAutoRender — main loop cancelled, manual mode active'); });
}

// ============================================================================
// Step 2: RenderSingleFrame — manually drive one engine frame
// ============================================================================
// Called from index.html onXRFrame() at the XR session's frame rate (72Hz on Quest 3).
// We call em_loop_iteration() which is the same function Emscripten's main loop
// was calling — this ensures identical behavior (pump messages, engine frame, etc.)
extern "C" void Engine_RenderSingleFrame() {
    em_loop_iteration();
}

// ============================================================================
// Step 3: SetCameraMatrix — override the engine's view matrix with WebXR pose
// ============================================================================
// WebXR provides a 4x4 view matrix per eye via XRView.transform.matrix.
// We store it here; ComputeViewMatrix() in gl_rmain.cpp checks g_bWebXRMatrixActive
// and copies it into the VMatrix output instead of computing from angles.
extern "C" void Engine_SetCameraMatrix(float* mat) {
    memcpy(g_WebXRViewMatrix, mat, 16 * sizeof(float));
    g_bWebXRMatrixActive = true;
}

// Set the projection matrix override (from XRView.projectionMatrix)
extern "C" void Engine_SetProjectionMatrix(float* mat) {
    memcpy(g_WebXRProjectionMatrix, mat, 16 * sizeof(float));
    g_bWebXRProjectionActive = true;
}

// Reset the overrides (return to engine-controlled camera + projection)
extern "C" void Engine_ResetCameraMatrix() {
    g_bWebXRMatrixActive = false;
    g_bWebXRProjectionActive = false;
    g_bWebXRManualLoop = false;
}

#endif // __EMSCRIPTEN__
