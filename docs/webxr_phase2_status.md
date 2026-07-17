# WebXR Phase 2 — Engine Hooks Implementation Status

## Build #87 (commit 7e8b2b52) — IN PROGRESS

## What was implemented:

### 1. emscripten_set_main_loop location
**File:** `engine/sys_dll2.cpp`, lines 1502-1512
- `em_loop_iteration()` → calls `s_EngineAPI.MainLoopIter()` → `eng->Frame()` → full engine tick
- `CEngineAPI::MainLoop()` → `emscripten_set_main_loop(em_loop_iteration, 0, true)`

### 2. Engine hooks (webxr_hooks.cpp — compiled with emcc -O0)
- `Engine_DisableAutoRender()` → calls `emscripten_cancel_main_loop()`, sets `g_bWebXRManualLoop = true`
- `Engine_RenderSingleFrame()` → calls `em_loop_iteration()` (same function the auto loop used)
- `Engine_SetCameraMatrix(float* mat)` → copies 16 floats to `g_WebXRViewMatrix`, sets `g_bWebXRMatrixActive = true`
- `Engine_SetProjectionMatrix(float* mat)` → copies 16 floats to `g_WebXRProjectionMatrix`, sets `g_bWebXRProjectionActive = true`
- `Engine_ResetCameraMatrix()` → clears all override flags

### 3. gl_rmain.cpp patch (webxr_glmain_patch.py)
- Adds `extern float g_WebXRViewMatrix[]; extern bool g_bWebXRMatrixActive;` declarations
- Patches `ComputeViewMatrix()` to check `g_bWebXRMatrixActive` first
- If active: copies column-major [16] into VMatrix m[row][col] via `g_WebXRViewMatrix[col*4+row]`
- If inactive: falls through to original angle-based computation

### 4. CI integration (ci-build.sh)
- `apply_source_patches()`: runs `webxr_glmain_patch.py` on cloned `gl_rmain.cpp`
- `emcc_link()`: compiles `webxr_hooks.cpp` → `webxr_hooks.o` with emcc -O0
- Links `webxr_hooks.o` alongside `webxr_bridge.o` into main WASM module

### 5. Bridge alignment (webxr_bridge.cpp)
- `DisableAutoRenderLoop()` → calls `Engine_DisableAutoRender()`
- `SetCameraMatrices(view, proj)` → calls `Engine_SetCameraMatrix(view)` + `Engine_SetProjectionMatrix(proj)`
- `RenderXRFrame()` → calls `Engine_RenderSingleFrame()`
- `EnableAutoRenderLoop()` → calls `Engine_ResetCameraMatrix()`

## Key rendering pipeline references for Gemini:

### ComputeViewMatrix (gl_rmain.cpp:1080)
```cpp
void ComputeViewMatrix( VMatrix *pViewMatrix, const Vector &origin, const QAngle &angles )
{
    static VMatrix baseRotation;
    static bool bDidInit;
    if ( !bDidInit ) {
        MatrixBuildRotationAboutAxis( baseRotation, Vector( 1, 0, 0 ), -90 );
        MatrixRotate( baseRotation, Vector( 0, 0, 1 ), 90 );
        bDidInit = true;
    }
    *pViewMatrix = baseRotation;
    MatrixRotate( *pViewMatrix, Vector( 1, 0, 0 ), -angles[2] ); // roll
    MatrixRotate( *pViewMatrix, Vector( 0, 1, 0 ), -angles[0] ); // pitch
    MatrixRotate( *pViewMatrix, Vector( 0, 0, 1 ), -angles[1] ); // yaw
    MatrixTranslate( *pViewMatrix, -origin );
}
```

### ComputeViewMatrices caller (gl_rmain.cpp:553)
```cpp
float ComputeViewMatrices( VMatrix *pWorldToView, VMatrix *pViewToProjection,
                            VMatrix *pWorldToProjection, const CViewSetup &viewSetup )
{
    // ...
    ComputeViewMatrix( pWorldToView, viewSetup.origin, viewSetup.angles );
    
    if ( viewSetup.m_bOrtho ) { ... }
    else if ( viewSetup.m_bOffCenter ) { ... }
    else if ( viewSetup.m_bViewToProjectionOverride ) {
        *pViewToProjection = viewSetup.m_ViewToProjection;  // ← EXISTING proj override!
        MatrixBuildPerspectiveZRange( *pViewToProjection, viewSetup.zNear, viewSetup.zFar );
    }
    else {
        MatrixBuildPerspectiveX( *pViewToProjection, viewSetup.fov, flAspectRatio, 
                                  viewSetup.zNear, viewSetup.zFar );
    }
    MatrixMultiply( *pViewToProjection, *pWorldToView, *pWorldToProjection );
    return flAspectRatio;
}
```

### VMatrix layout (public/mathlib/vmatrix.h)
```cpp
class alignas(16) VMatrix {
public:
    vec_t m[4][4];  // row-major: m[row][col]
    inline float* operator[](int i) { return m[i]; }  // row access
    inline float *Base() { return &m[0][0]; }
};
```

### CViewSetup (public/view_shared.h)
```cpp
class CViewSetup {
public:
    int x, y, width, height;
    StereoEye_t m_eStereoEye;  // STEREO_EYE_LEFT=1, STEREO_EYE_RIGHT=2
    float fov;              // horizontal FOV in degrees
    Vector origin;          // 3D camera position
    QAngle angles;          // pitch, yaw, roll
    float zNear, zFar;
    float m_flAspectRatio;
    bool m_bOrtho;
    bool m_bViewToProjectionOverride;
    VMatrix m_ViewToProjection;  // existing projection override!
    // ...
};
```

## Projection matrix override note:
The engine ALREADY has `m_bViewToProjectionOverride` and `m_ViewToProjection` in CViewSetup.
This means Gemini could override the projection by setting `viewSetup.m_bViewToProjectionOverride = true`
and `viewSetup.m_ViewToProjection = webXRProjMatrix` in the view setup code.
However, our current hook approach (global flag + global matrix) is simpler and doesn't require
patching the view setup pipeline — just ComputeViewMatrix.

## Expected build result:
- `webxr_hooks.o` compiles successfully (emcc -O0, simple C++ with emscripten.h + string.h)
- `webxr_bridge.o` compiles successfully (now with matching extern declarations)
- Linker resolves all `Engine_*` symbols from `webxr_hooks.o` (no more undefined symbols!)
- `gl_rmain.cpp` patched by `webxr_glmain_patch.py` before waf build
- WASM contains: `DisableAutoRenderLoop`, `SetCameraMatrices`, `RenderXRFrame`, `EnableAutoRenderLoop` (KEEPALIVE)
- WASM contains: `Engine_DisableAutoRender`, `Engine_RenderSingleFrame`, `Engine_SetCameraMatrix`, etc. (auto-exported by MAIN_MODULE=1)
