// webxr_hooks.cpp — Source Engine hooks for WebXR Phase 2

#ifdef __EMSCRIPTEN__

#include <emscripten.h>
#include <string.h>
#include <stdlib.h>
#include <stdio.h>

// ============================================================================
// Global state
// ============================================================================

volatile bool g_bWebXRManualLoop = false;
static bool g_bEngineInitialized = false;
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
    g_bWebXRManualLoop = true;
    emscripten_cancel_main_loop();
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
    if (g_bEngineInitialized) {
        EM_ASM_({ console.warn('[Engine_Init] already initialized — ignoring duplicate call'); });
        return 1;
    }
    EM_ASM_({ console.log('[Engine_Init] Calling Host_Init(false)...'); });
    Host_Init(false);
    g_bEngineInitialized = true;
    EM_ASM_({ console.log('[Engine_Init] Host_Init returned'); });
    return 0;
}

// ============================================================================
// Engine_LoadMap — queues a map load command and runs a frame
// ============================================================================
extern "C" EMSCRIPTEN_KEEPALIVE int Engine_LoadMap(const char* mapName) {
    if (!g_bEngineInitialized || !mapName || !*mapName) return 2;
    // Diagnostic isolation: avoid snprintf and EM_ASM pointer arguments.
    // The exported hook is reached from JS, so keep this probe scalar-only.
    EM_ASM_({ console.log('[Engine_LoadMap] Hook reached; Cbuf deferred'); });
    return 0;
}

// ============================================================================
// Engine_RunFrame — calls em_loop_iteration with C++ exception handling
// ============================================================================
extern "C" EMSCRIPTEN_KEEPALIVE int Engine_RunFrame() {
    if (!g_bEngineInitialized) return 2;
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
    if (!g_bEngineInitialized || !cmd || !*cmd) return 2;
    Cbuf_AddText(cmd);
    Cbuf_Execute();
    EM_ASM_({ console.log('[Engine_QueueCommand] ' + UTF8ToString($0)); }, cmd);
    return 0;
}

#endif // __EMSCRIPTEN__
