// webxr_hooks.cpp — Source Engine hooks for WebXR Phase 2
// EMSCRIPTEN_KEEPALIVE ensures functions survive dead-code elimination
// and are exported in the WASM binary.

#ifdef __EMSCRIPTEN__

#include <emscripten.h>
#include <string.h>

// ============================================================================
// Global state — shared between hooks and engine rendering code
// ============================================================================

bool g_bWebXRManualLoop = false;
float g_WebXRViewMatrix[16] = {0};
float g_WebXRProjectionMatrix[16] = {0};
bool g_bWebXRMatrixActive = false;
bool g_bWebXRProjectionActive = false;

// extern declaration — implemented in sys_dll2.cpp
extern void em_loop_iteration();

// ============================================================================
// Hook functions — each has EMSCRIPTEN_KEEPALIVE to prevent stripping
// ============================================================================

EMSCRIPTEN_KEEPALIVE
extern "C" void Engine_DisableAutoRender() {
    emscripten_cancel_main_loop();
    g_bWebXRManualLoop = true;
    EM_ASM_({ console.log('[WebXR] Engine_DisableAutoRender — main loop cancelled, manual mode active'); });
}

EMSCRIPTEN_KEEPALIVE
extern "C" void Engine_RenderSingleFrame() {
    em_loop_iteration();
}

EMSCRIPTEN_KEEPALIVE
extern "C" void Engine_SetCameraMatrix(float* mat) {
    memcpy(g_WebXRViewMatrix, mat, 16 * sizeof(float));
    g_bWebXRMatrixActive = true;
}

EMSCRIPTEN_KEEPALIVE
extern "C" void Engine_SetProjectionMatrix(float* mat) {
    memcpy(g_WebXRProjectionMatrix, mat, 16 * sizeof(float));
    g_bWebXRProjectionActive = true;
}

EMSCRIPTEN_KEEPALIVE
extern "C" void Engine_ResetCameraMatrix() {
    g_bWebXRMatrixActive = false;
    g_bWebXRProjectionActive = false;
    g_bWebXRManualLoop = false;
}

#endif // __EMSCRIPTEN__
