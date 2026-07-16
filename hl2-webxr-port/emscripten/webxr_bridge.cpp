// webxr_bridge.cpp — Phase 2 WebXR Bridge for Source Engine
// Compiles as part of the main WASM module (MAIN_MODULE=1 auto-exports)
// The extern functions (Engine_SetViewMatrix etc.) are resolved at runtime
// via dlopen side-modules. With -sERROR_ON_UNDEFINED_SYMBOLS=0 this links
// without errors even before the real engine implementations exist.

#include <emscripten.h>
#include <GLES3/gl3.h> // WebGL2 / WebXR compatible

// These functions must be linked in the engine later (e.g. in view.cpp or gl_rmain.cpp)
// For now they are extern — resolved at runtime via dlopen.
// With -sERROR_ON_UNDEFINED_SYMBOLS=0 the linker does NOT error on these.
extern void Engine_SetViewMatrix(const float* viewMatrix);
extern void Engine_SetProjectionMatrix(const float* projMatrix);
extern void Engine_RenderSingleFrame();

extern "C" {

// Called per eye from the onXRFrame loop in index.html
EMSCRIPTEN_KEEPALIVE
void SetCameraMatrices(float* viewMatrix, float* projMatrix) {
    // Forward VR head pose from Quest 3 into the engine
    Engine_SetViewMatrix(viewMatrix);
    Engine_SetProjectionMatrix(projMatrix);
}

// Forces the engine to render exactly ONE frame for the current eye
EMSCRIPTEN_KEEPALIVE
void RenderXRFrame() {
    Engine_RenderSingleFrame();
}

// Stops the normal 2D render loop when entering VR mode
EMSCRIPTEN_KEEPALIVE
void DisableAutoRenderLoop() {
    // Pauses the emscripten_set_main_loop started render loop
    emscripten_pause_main_loop();
}

} // extern "C"
