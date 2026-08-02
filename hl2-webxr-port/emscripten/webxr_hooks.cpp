// webxr_hooks.cpp — Source Engine hooks for WebXR Phase 2

#ifdef __EMSCRIPTEN__

#include <emscripten.h>
#include <string.h>
#include <stdlib.h>
#include <stdio.h>

// ============================================================================
// Global state
// ============================================================================

bool g_bWebXRManualLoop = false;
float g_WebXRViewMatrix[16] = {0};
float g_WebXRProjectionMatrix[16] = {0};
bool g_bWebXRMatrixActive = false;
bool g_bWebXRProjectionActive = false;

// extern declaration — implemented in sys_dll2.cpp
extern void em_loop_iteration();

// ============================================================================
// Engine function declarations — resolved from libengine.so at link time
// These are patched with EMSCRIPTEN_KEEPALIVE in the CI build
// Correct signatures verified from source:
//   void Host_Init( bool bDedicated )  — engine/host.cpp
//   void Host_RunFrame( float time )    — engine/host.cpp
//   void Cbuf_AddText( const char *pText ) — engine/cmd.cpp
//   void Cbuf_Execute()                 — engine/cmd.cpp
// ============================================================================

extern void Host_Init(bool bDedicated);
extern void Host_RunFrame(float time);
extern void Cbuf_AddText(const char *pText);
extern void Cbuf_Execute();

// ============================================================================
// Hook functions — extern "C" EMSCRIPTEN_KEEPALIVE
// ============================================================================

extern "C" EMSCRIPTEN_KEEPALIVE void Engine_DisableAutoRender() {
    emscripten_cancel_main_loop();
    g_bWebXRManualLoop = true;
    EM_ASM_({ console.log('[WebXR] Engine_DisableAutoRender — main loop cancelled, manual mode active'); });
}

extern "C" EMSCRIPTEN_KEEPALIVE void Engine_RenderSingleFrame() {
    em_loop_iteration();
}

extern "C" EMSCRIPTEN_KEEPALIVE void Engine_SetCameraMatrix(float* mat) {
    memcpy(g_WebXRViewMatrix, mat, 16 * sizeof(float));
    g_bWebXRMatrixActive = true;
}

extern "C" EMSCRIPTEN_KEEPALIVE void Engine_SetProjectionMatrix(float* mat) {
    memcpy(g_WebXRProjectionMatrix, mat, 16 * sizeof(float));
    g_bWebXRProjectionActive = true;
}

extern "C" EMSCRIPTEN_KEEPALIVE void Engine_ResetCameraMatrix() {
    g_bWebXRMatrixActive = false;
    g_bWebXRProjectionActive = false;
    g_bWebXRManualLoop = false;
}

// ============================================================================
// Engine_Init — calls Host_Init to complete engine initialization
// Call this after main() exits and before the render loop starts
// ============================================================================
extern "C" EMSCRIPTEN_KEEPALIVE int Engine_Init() {
    EM_ASM_({ console.log('[Engine_Init] Calling Host_Init(false)...'); });
    Host_Init(false);
    EM_ASM_({ console.log('[Engine_Init] Host_Init returned'); });
    return 0;
}

// ============================================================================
// Engine_LoadMap — queues a map load command and runs a frame
// ============================================================================
extern "C" EMSCRIPTEN_KEEPALIVE int Engine_LoadMap(const char* mapName) {
    char cmd[256];
    snprintf(cmd, sizeof(cmd), "map_background %s\n", mapName);
    EM_ASM_({ console.log('[Engine_LoadMap] Queuing: ' + UTF8ToString($0)); }, cmd);
    
    // Queue only. The already-running render loop executes the command on its
    // next frame; executing here re-enters the engine during bootstrap and can
    // access uninitialized frame state (WASM memory OOB).
    Cbuf_AddText(cmd);
    EM_ASM_({ console.log('[Engine_LoadMap] Queued; waiting for render loop'); });
    return 0;
}

// ============================================================================
// Engine_RunFrame — calls em_loop_iteration with C++ exception handling
// ============================================================================
extern "C" EMSCRIPTEN_KEEPALIVE int Engine_RunFrame() {
    try {
        em_loop_iteration();
        return 0;
    } catch(...) {
        return 1;
    }
}

// ============================================================================
// Engine_QueueCommand — adds a command to the engine command buffer
// ============================================================================
extern "C" EMSCRIPTEN_KEEPALIVE int Engine_QueueCommand(const char* cmd) {
    Cbuf_AddText(cmd);
    Cbuf_Execute();
    EM_ASM_({ console.log('[Engine_QueueCommand] ' + UTF8ToString($0)); }, cmd);
    return 0;
}

#endif // __EMSCRIPTEN__
