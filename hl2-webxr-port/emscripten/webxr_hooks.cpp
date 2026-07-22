// webxr_hooks.cpp — Source Engine hooks for WebXR Phase 2
// extern "C" EMSCRIPTEN_KEEPALIVE ensures functions survive dead-code
// elimination and are exported in the WASM binary.

#ifdef __EMSCRIPTEN__

#include <emscripten.h>
#include <string.h>
#include <stdlib.h>
#include <stdio.h>

// ============================================================================
// Global state — shared between hooks and engine rendering code
// ============================================================================

bool g_bWebXRManualLoop = false;
float g_WebXRViewMatrix[16] = {0};
float g_WebXRProjectionMatrix[16] = {0};
bool g_bWebXRMatrixActive = false;
bool g_bWebXRProjectionActive = false;

// extern declaration — implemented in sys_dll2.cpp
// This is the engine's main loop iteration (calls Host_Frame internally)
extern void em_loop_iteration();

// ============================================================================
// Engine function declarations — resolved from libengine.so at link time
// These functions are patched with EMSCRIPTEN_KEEPALIVE in the CI build
// so they're exported from the side module and merged via mergeLibSymbols
// ============================================================================

// Host_Frame — the main engine frame function
// Defined in host.cpp, processes Cbuf, updates game state, renders
extern void Host_Frame(float time);

// Cbuf_AddText — adds text to the command buffer
// Defined in cbuf.cpp
extern void Cbuf_AddText(const char* text);

// Cbuf_Execute — executes all queued commands
// Defined in cbuf.cpp
extern void Cbuf_Execute();

// Host_Init — initializes the host system
// Defined in host.cpp
extern bool Host_Init();

// ============================================================================
// Hook functions — extern "C" EMSCRIPTEN_KEEPALIVE (correct order!)
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
// NEW: Engine_Init — initializes the engine host system
// Call this after main() exits and before the render loop starts
// ============================================================================
extern "C" EMSCRIPTEN_KEEPALIVE int Engine_Init() {
    EM_ASM_({ console.log('[Engine_Init] Calling Host_Init()...'); });
    bool result = Host_Init();
    EM_ASM_({ console.log('[Engine_Init] Host_Init returned: ' + $0); }, result);
    return result ? 0 : -1;
}

// ============================================================================
// NEW: Engine_LoadMap — queues a map load command and runs a frame
// ============================================================================
extern "C" EMSCRIPTEN_KEEPALIVE int Engine_LoadMap(const char* mapName) {
    char cmd[256];
    snprintf(cmd, sizeof(cmd), "map_background %s\n", mapName);
    EM_ASM_({ console.log('[Engine_LoadMap] Queuing: ' + UTF8ToString($0)); }, cmd);
    
    Cbuf_AddText(cmd);
    Cbuf_Execute();
    em_loop_iteration();
    
    EM_ASM_({ console.log('[Engine_LoadMap] Done'); });
    return 0;
}

// ============================================================================
// NEW: Engine_RunFrame — calls em_loop_iteration with C++ exception handling
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
// NEW: Engine_QueueCommand — adds a command to the engine command buffer
// ============================================================================
extern "C" EMSCRIPTEN_KEEPALIVE int Engine_QueueCommand(const char* cmd) {
    Cbuf_AddText(cmd);
    Cbuf_Execute();
    EM_ASM_({ console.log('[Engine_QueueCommand] ' + UTF8ToString($0)); }, cmd);
    return 0;
}

#endif // __EMSCRIPTEN__
