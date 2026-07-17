// webxr_bridge.cpp — Phase 2 WebXR Bridge for Source Engine
// EMSCRIPTEN_KEEPALIVE exports are called from JavaScript (xr_wrapper.js).
// The extern functions are implemented in webxr_hooks.cpp.

#include <emscripten.h>

// These functions are implemented in webxr_hooks.cpp
extern "C" {
    void Engine_DisableAutoRender();
    void Engine_RenderSingleFrame();
    void Engine_SetCameraMatrix(float* mat);
    void Engine_SetProjectionMatrix(float* mat);
    void Engine_ResetCameraMatrix();
}

extern "C" {

EMSCRIPTEN_KEEPALIVE
void DisableAutoRenderLoop() {
    Engine_DisableAutoRender();
}

EMSCRIPTEN_KEEPALIVE
void SetCameraMatrices(float* viewMatrix, float* projMatrix) {
    Engine_SetCameraMatrix(viewMatrix);
    if (projMatrix) {
        Engine_SetProjectionMatrix(projMatrix);
    }
}

EMSCRIPTEN_KEEPALIVE
void RenderXRFrame() {
    Engine_RenderSingleFrame();
}

EMSCRIPTEN_KEEPALIVE
void EnableAutoRenderLoop() {
    Engine_ResetCameraMatrix();
}

} // extern "C"
