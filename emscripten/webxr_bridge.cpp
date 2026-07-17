// webxr_bridge.cpp — Phase 2 WebXR Bridge for Source Engine
// Compiles as part of the main WASM module (MAIN_MODULE=1 auto-exports)
// The extern functions are implemented in webxr_hooks.cpp (compiled and linked
// alongside this file in the same emcc link step).

#include <emscripten.h>
#include <GLES3/gl3.h> // WebGL2 / WebXR compatible

// These functions are implemented in webxr_hooks.cpp
extern "C" {
    void Engine_DisableAutoRender();
    void Engine_RenderSingleFrame();
    void Engine_SetCameraMatrix(float* mat);
    void Engine_SetProjectionMatrix(float* mat);
    void Engine_ResetCameraMatrix();
}

extern "C" {

// Stops the normal 2D render loop when entering VR mode
EMSCRIPTEN_KEEPALIVE
void DisableAutoRenderLoop() {
    Engine_DisableAutoRender();
}

// Called per eye from the onXRFrame loop in index.html
// Sets both view and projection matrices for the current eye
EMSCRIPTEN_KEEPALIVE
void SetCameraMatrices(float* viewMatrix, float* projMatrix) {
    Engine_SetCameraMatrix(viewMatrix);
    if (projMatrix) {
        Engine_SetProjectionMatrix(projMatrix);
    }
}

// Forces the engine to render exactly ONE frame for the current eye
EMSCRIPTEN_KEEPALIVE
void RenderXRFrame() {
    Engine_RenderSingleFrame();
}

// Exit VR — restore normal 2D render loop
EMSCRIPTEN_KEEPALIVE
void EnableAutoRenderLoop() {
    Engine_ResetCameraMatrix();
    // Re-start the main loop (emscripten_set_main_loop with the same callback)
    // This is handled by the JS side via emscripten_resume_main_loop or re-entering
}

} // extern "C"
