#!/usr/bin/env python3
"""Inject GL stubs, dlsym/dlopen intercept, GL version spoof, chunk URL fix,
and canvas size enforcement into hl2_launcher.js"""
import sys, re

js_path = sys.argv[1]
with open(js_path, 'r') as f:
    js = f.read()

# ============================================================
# 0. Centralized asset origin + chunkUrl() + load telemetry
# ============================================================
# Replace ad-hoc chunk URL string with a single immutable config source.
# The loader gets a dedicated chunkUrl() function + fetchChunk telemetry.

ASSET_ORIGIN = 'https://hl2-assets-proxy.hl2-webxr.workers.dev'
CHUNK_PREFIX = ASSET_ORIGIN + '/chunks'

asset_config_block = """
// === ASSET CONFIG: Single immutable source for chunk URLs ===
const ASSET_ORIGIN = '""" + ASSET_ORIGIN + """';
const CHUNK_PREFIX = ASSET_ORIGIN + '/chunks';

function chunkUrl(mapName) {
  if (!/^[a-z0-9_]+$/i.test(mapName)) {
    console.error('[asset:error] Invalid map chunk name: ' + mapName);
    throw new Error('Invalid map chunk name: ' + mapName);
  }
  return CHUNK_PREFIX + '/' + mapName + '.data';
}

// Fetch a chunk with full telemetry — one log per stage
async function fetchChunk(mapName) {
  const url = chunkUrl(mapName);
  const started = performance.now();
  console.info('[asset:start]', { mapName, url });
  const response = await fetch(url, {
    mode: 'cors',
    credentials: 'omit',
    headers: { Range: 'bytes=0-' }
  });
  console.info('[asset:headers]', {
    mapName,
    status: response.status,
    contentType: response.headers.get('content-type'),
    contentLength: response.headers.get('content-length'),
    acceptRanges: response.headers.get('accept-ranges')
  });
  if (!(response.ok || response.status === 206)) {
    throw new Error('Chunk ' + mapName + ': HTTP ' + response.status + ' (' + url + ')');
  }
  const buffer = await response.arrayBuffer();
  console.info('[asset:done]', {
    mapName,
    bytes: buffer.byteLength,
    duration_ms: Math.round(performance.now() - started)
  });
  return buffer;
}
"""

# Also inject Module.locateFile for Emscripten-managed files (.wasm, .data)
locate_file_block = """
// === LOCATEFILE: Redirect Emscripten runtime files to CDN ===
var _orig_locateFile = Module.locateFile;
Module.locateFile = function(path, prefix) {
  if (path.endsWith('.wasm') || path.endsWith('.data')) {
    return ASSET_ORIGIN + '/hl2-runtime/' + path;
  }
  if (_orig_locateFile) return _orig_locateFile(path, prefix);
  return prefix + path;
};
"""

# Find the insertion point — right after the pre.js inlined section
pre_js_end = '// end include:'
if pre_js_end in js:
    idx = js.index(pre_js_end)
    line_end = js.index('\n', idx)
    js = js[:line_end+1] + asset_config_block + '\n' + locate_file_block + '\n' + js[line_end+1:]
    print('Asset config + locateFile + chunk telemetry injected')
elif 'Module.__glStubs' not in js:
    # Prepend before GL stubs
    js = asset_config_block + '\n' + locate_file_block + '\n' + js
    print('Asset config injected at top (pre.js marker not found)')
else:
    print('WARNING: Could not find insertion point for asset config')

# Replace any existing chunk URL patterns with chunkUrl() calls
# Pattern: `chunks/${mapName}.data` or https://...workers.dev/chunks/${mapName}.data
old_patterns = [
    '`chunks/${mapName}.data`',
    '`' + ASSET_ORIGIN + '/chunks/${mapName}.data`',
    '`https://hl2-assets-proxy.hl2-webxr.workers.dev/chunks/${mapName}.data`',
]
for old_pat in old_patterns:
    if old_pat in js:
        # Don't replace inside the chunkUrl function definition itself
        # Only replace the actual XHR.open call
        js = js.replace(
            old_pat,
            'chunkUrl(mapName)',
        )
        print('Replaced chunk URL pattern: ' + old_pat[:30] + '...')

# Remove the old canvas_fix block (will be replaced by GL telemetry)
old_canvas_fix = """
// === CANVAS SIZE FIX: Ensure canvas has non-zero dimensions ===
if (typeof canvasElement !== 'undefined' && canvasElement) {
  if (!canvasElement.width || canvasElement.width === 0) {
    canvasElement.width = canvasElement.widthNative || 1280;
    console.log('[CANVAS] width set to ' + canvasElement.width);
  }
  if (!canvasElement.height || canvasElement.height === 0) {
    canvasElement.height = canvasElement.heightNative || 720;
    console.log('[CANVAS] height set to ' + canvasElement.height);
  }
}
"""
if old_canvas_fix in js:
    js = js.replace(old_canvas_fix, '', 1)
    print('Removed old canvas fix (will be replaced by GL telemetry)')

# ============================================================
# 0b. GL Frame Heartbeat — isolated render gate telemetry
# ============================================================
# Four gates: G1 (context exists), G2 (clear produces color),
# G3 (Source GL call reaches stub), G4 (glDraw* called)
gl_telemetry_block = """
// === GL TELEMETRY: Frame heartbeat with clear/draw counters ===
const glTelemetry = {
  frames: 0,
  clearCalls: 0,
  drawCalls: 0,
  sourceGlCalls: 0,
  lastReport: performance.now(),
  gates: { g1: false, g2: false, g3: false, g4: false }
};

// G1: Verify WebGL2 context exists
if (typeof canvasElement !== 'undefined' && canvasElement) {
  var _gl_ctx = canvasElement.getContext('webgl2');
  if (_gl_ctx) {
    glTelemetry.gates.g1 = true;
    console.info('[gl:g1] WebGL2 context exists');
    // G2: Isolated clear test — if this produces color, canvas composition works
    try {
      _gl_ctx.clearColor(0.2, 0.15, 0.1, 1.0);
      _gl_ctx.clear(_gl_ctx.COLOR_BUFFER_BIT);
      glTelemetry.gates.g2 = true;
      console.info('[gl:g2] clearColor + clear succeeded');
    } catch(e) {
      console.warn('[gl:g2] clear test failed: ' + e.message);
    }
  } else {
    console.error('[gl:g1] WebGL2 context creation failed');
  }
}

// Wrap dlsym stub resolution to count Source GL calls (G3)
var _orig_dlsym_count = 0;
var _wrapped_dlsym = false;

// Heartbeat reporter — runs every 1s, logs only if there was activity
function reportGlTelemetry() {
  var now = performance.now();
  if (now - glTelemetry.lastReport >= 1000) {
    var hasActivity = glTelemetry.frames > 0 || glTelemetry.clearCalls > 0 || glTelemetry.drawCalls > 0 || glTelemetry.sourceGlCalls > 0;
    if (hasActivity) {
      console.info('[gl:telemetry]', {
        frames: glTelemetry.frames,
        clearCalls: glTelemetry.clearCalls,
        drawCalls: glTelemetry.drawCalls,
        sourceGlCalls: glTelemetry.sourceGlCalls,
        gates: glTelemetry.gates
      });
    }
    glTelemetry.frames = 0;
    glTelemetry.clearCalls = 0;
    glTelemetry.drawCalls = 0;
    glTelemetry.sourceGlCalls = 0;
    glTelemetry.lastReport = now;
  }
  requestAnimationFrame(reportGlTelemetry);
}

// Start the heartbeat after a short delay (let engine init first)
setTimeout(function() {
  requestAnimationFrame(reportGlTelemetry);
  console.info('[gl:telemetry] heartbeat started');
}, 3000);
"""

# Insert GL telemetry right after the asset config block
# (which was already injected above in section 0)
if 'glTelemetry' not in js:
    pre_js_end = '// end include:'
    if pre_js_end in js:
        idx = js.index(pre_js_end)
        line_end = js.index('\n', idx)
        js = js[:line_end+1] + gl_telemetry_block + '\n' + js[line_end+1:]
        print('GL frame heartbeat telemetry injected')
    else:
        js = gl_telemetry_block + '\n' + js
        print('GL telemetry injected at top')
else:
    print('GL telemetry already present')

# ============================================================
# 1. GL stubs table (desktop GL functions not in WebGL)
# ============================================================
gl_stubs_block = """
// === GL STUBS: Desktop GL function stubs for WebGL2 compatibility ===
Module.__glStubs = {
  'glAlphaFunc': { fn: function(f, r) {}, sig: 'vif' },
  'glColor4f': { fn: function(r, g, b, a) {}, sig: 'vffff' },
  'glClientActiveTexture': { fn: function(t) {}, sig: 'vi' },
  'glGetTexLevelParameteriv': { fn: function(t, l, p, params) {}, sig: 'viiii' },
  'glDrawRangeElementsBaseVertex': { fn: function(m, s, e, c, t, i, bv) {}, sig: 'viiiiiii' },
  'glDrawElementsBaseVertex': { fn: function(m, c, t, i, bv) {}, sig: 'viiiii' },
  'glBegin': { fn: function(m) {}, sig: 'vi' },
  'glEnd': { fn: function() {}, sig: 'v' },
  'glVertex3f': { fn: function(x, y, z) {}, sig: 'vfff' },
  'glVertex2f': { fn: function(x, y) {}, sig: 'vff' },
  'glTexCoord2f': { fn: function(s, t) {}, sig: 'vff' },
  'glTexCoord3f': { fn: function(s, t, r) {}, sig: 'vfff' },
  'glNormal3f': { fn: function(x, y, z) {}, sig: 'vfff' },
  'glColor3f': { fn: function(r, g, b) {}, sig: 'vfff' },
  'glColor4ub': { fn: function(r, g, b, a) {}, sig: 'viiii' },
  'glMatrixMode': { fn: function(m) {}, sig: 'vi' },
  'glLoadIdentity': { fn: function() {}, sig: 'v' },
  'glOrtho': { fn: function(l, r, b, t, n, f) {}, sig: 'vdddddd' },
  'glFrustum': { fn: function(l, r, b, t, n, f) {}, sig: 'vdddddd' },
  'glPushMatrix': { fn: function() {}, sig: 'v' },
  'glPopMatrix': { fn: function() {}, sig: 'v' },
  'glTranslatef': { fn: function(x, y, z) {}, sig: 'vfff' },
  'glRotatef': { fn: function(a, x, y, z) {}, sig: 'vffff' },
  'glScalef': { fn: function(x, y, z) {}, sig: 'vfff' },
  'glEnableClientState': { fn: function(c) {}, sig: 'vi' },
  'glDisableClientState': { fn: function(c) {}, sig: 'vi' },
  'glVertexPointer': { fn: function(s, t, st, p) {}, sig: 'viiii' },
  'glTexCoordPointer': { fn: function(s, t, st, p) {}, sig: 'viiii' },
  'glNormalPointer': { fn: function(t, st, p) {}, sig: 'viii' },
  'glColorPointer': { fn: function(s, t, st, p) {}, sig: 'viiii' },
  'glShadeModel': { fn: function(m) {}, sig: 'vi' },
  'glLightfv': { fn: function(l, p, v) {}, sig: 'viii' },
  'glLightf': { fn: function(l, p, v) {}, sig: 'viif' },
  'glLighti': { fn: function(l, p, v) {}, sig: 'viii' },
  'glMaterialfv': { fn: function(f, p, v) {}, sig: 'viii' },
  'glMaterialf': { fn: function(f, p, v) {}, sig: 'viif' },
  'glFogf': { fn: function(p, v) {}, sig: 'vif' },
  'glFogfv': { fn: function(p, v) {}, sig: 'vii' },
  'glFogi': { fn: function(p, v) {}, sig: 'vii' },
  'glHint': { fn: function(t, m) {}, sig: 'vii' },
  'glTexImage1D': { fn: function() {}, sig: 'viiiiiiii' },
  'glTexSubImage1D': { fn: function() {}, sig: 'viiiiiii' },
  'glGetTexImage': { fn: function() {}, sig: 'viiiii' },
  'glRectf': { fn: function(x1, y1, x2, y2) {}, sig: 'vffff' },
  'glRecti': { fn: function(x1, y1, x2, y2) {}, sig: 'viiii' },
  'glClearDepth': { fn: function(d) {}, sig: 'vd' },
  'glPolygonMode': { fn: function(f, m) {}, sig: 'vii' },
  'glInitNames': { fn: function() {}, sig: 'v' },
  'glLoadName': { fn: function(n) {}, sig: 'vi' },
  'glPushName': { fn: function(n) {}, sig: 'vi' },
  'glPopName': { fn: function() {}, sig: 'v' },
  'glRenderMode': { fn: function(m) { return 0; }, sig: 'ii' },
  'glSelectBuffer': { fn: function(s, b) {}, sig: 'vii' },
  'glFeedbackBuffer': { fn: function(s, t, b) {}, sig: 'viii' },
  'glPassThrough': { fn: function(t) {}, sig: 'vf' },
  'glEdgeFlag': { fn: function(f) {}, sig: 'vi' },
  'glIndexi': { fn: function(i) {}, sig: 'vi' },
  'glIndexf': { fn: function(f) {}, sig: 'vf' },
  'glLogicOp': { fn: function(o) {}, sig: 'vi' },
  'glAccum': { fn: function(o, v) {}, sig: 'vif' },
  'glClearAccum': { fn: function(r, g, b, a) {}, sig: 'vffff' },
  'glPixelTransferf': { fn: function(p, v) {}, sig: 'vif' },
  'glPixelTransferi': { fn: function(p, v) {}, sig: 'vii' },
  'glPixelMapfv': { fn: function(m, s, v) {}, sig: 'viii' },
  'glPixelZoom': { fn: function(x, y) {}, sig: 'vff' },
  'glCopyPixels': { fn: function() {}, sig: 'viiiii' },
  'glDrawPixels': { fn: function() {}, sig: 'viiiii' },
  'glBitmap': { fn: function() {}, sig: 'viiffiffi' },
  'glListBase': { fn: function(b) {}, sig: 'vi' },
  'glCallList': { fn: function(l) {}, sig: 'vi' },
  'glCallLists': { fn: function(n, t, l) {}, sig: 'viii' },
  'glNewList': { fn: function(l, m) {}, sig: 'vii' },
  'glEndList': { fn: function() {}, sig: 'v' },
  'glDeleteLists': { fn: function(l, r) {}, sig: 'vii' },
  'glGenLists': { fn: function(s) { return 0; }, sig: 'ii' },
  'glIsList': { fn: function(l) { return 0; }, sig: 'ii' },
  'glAreTexturesResident': { fn: function(n, t, r) { return 1; }, sig: 'iiii' },
  'glPrioritizeTextures': { fn: function(n, t, p) {}, sig: 'viii' },
  'glColorMaterial': { fn: function(f, m) {}, sig: 'vii' },
  'glGetPointerv': { fn: function(p, ptr) {}, sig: 'vii' },
  'glPushAttrib': { fn: function(m) {}, sig: 'vi' },
  'glPopAttrib': { fn: function() {}, sig: 'v' },
  'glPushClientAttrib': { fn: function(m) {}, sig: 'vi' },
  'glPopClientAttrib': { fn: function() {}, sig: 'v' },
  'glClipPlane': { fn: function(p, eq) {}, sig: 'vii' },
  'glGetClipPlane': { fn: function(p, eq) {}, sig: 'vii' },
  'glGetLightfv': { fn: function(l, p, v) {}, sig: 'viii' },
  'glGetLightiv': { fn: function(l, p, v) {}, sig: 'viii' },
  'glGetMaterialfv': { fn: function(f, p, v) {}, sig: 'viii' },
  'glGetMaterialiv': { fn: function(f, p, v) {}, sig: 'viii' },
  'glMultiTexCoord1f': { fn: function(t, s) {}, sig: 'vif' },
  'glMultiTexCoord2f': { fn: function(t, s, t2) {}, sig: 'viff' },
  'glMultiTexCoord3f': { fn: function(t, s, t2, r) {}, sig: 'vifff' },
  'glMultiTexCoord4f': { fn: function(t, s, t2, r, q) {}, sig: 'viffff' },
  'glMultiTexCoord1i': { fn: function(t, s) {}, sig: 'vii' },
  'glMultiTexCoord2i': { fn: function(t, s, t2) {}, sig: 'viii' },
  'glMultiTexCoord3i': { fn: function(t, s, t2, r) {}, sig: 'viiii' },
  'glMultiTexCoord4i': { fn: function(t, s, t2, r, q) {}, sig: 'viiiii' },
  'glActiveTextureARB': { fn: function(t) {}, sig: 'vi' },
  'glClientActiveTextureARB': { fn: function(t) {}, sig: 'vi' },
  'glPointParameterf': { fn: function(p, v) {}, sig: 'vif' },
  'glPointParameterfv': { fn: function(p, v) {}, sig: 'vii' },
  'glPointParameteri': { fn: function(p, v) {}, sig: 'vii' },
  'glFogCoordf': { fn: function(c) {}, sig: 'vf' },
  'glFogCoordfv': { fn: function(c) {}, sig: 'vi' },
  'glSecondaryColor3f': { fn: function(r, g, b) {}, sig: 'vfff' },
  'glSecondaryColor3ub': { fn: function(r, g, b) {}, sig: 'viii' },
  'glSecondaryColorPointer': { fn: function(s, t, st, p) {}, sig: 'viiii' },
  'glWindowPos2f': { fn: function(x, y) {}, sig: 'vff' },
  'glWindowPos3f': { fn: function(x, y, z) {}, sig: 'vfff' },
  'glBlendFuncSeparate': { fn: function(s, d, sa, da) {}, sig: 'viiii' },
  'glMultiDrawArrays': { fn: function(m, f, s, c) {}, sig: 'viiii' },
  'glActiveTexture': { fn: function(t) {}, sig: 'vi' },
  'glSampleCoverage': { fn: function(v, i) {}, sig: 'vii' },
  'glFogCoordfEXT': { fn: function(c) {}, sig: 'vf' },
  'glFogCoordfvEXT': { fn: function(c) {}, sig: 'vi' },
  'glSecondaryColor3fEXT': { fn: function(r, g, b) {}, sig: 'vfff' },
  'glSecondaryColor3ubEXT': { fn: function(r, g, b) {}, sig: 'viii' },
  'glSecondaryColorPointerEXT': { fn: function(s, t, st, p) {}, sig: 'viiii' },
  'glWindowPos2fARB': { fn: function(x, y) {}, sig: 'vff' },
  'glWindowPos3fARB': { fn: function(x, y, z) {}, sig: 'vfff' },
  'glBlendFuncSeparateEXT': { fn: function(s, d, sa, da) {}, sig: 'viiii' },
  'glMultiDrawArraysEXT': { fn: function(m, f, s, c) {}, sig: 'viiii' },
  'glPointParameterfEXT': { fn: function(p, v) {}, sig: 'vif' },
  'glPointParameterfvEXT': { fn: function(p, v) {}, sig: 'vii' },
  'glStencilOpSeparate': { fn: function(f, sf, df, sm) {}, sig: 'viiii' },
  'glStencilFuncSeparate': { fn: function(f, ff, r, m) {}, sig: 'viiii' },
  'glStencilMaskSeparate': { fn: function(f, m) {}, sig: 'vii' },
  'glProgramStringARB': { fn: function() {}, sig: 'viiii' },
  'glBindProgramARB': { fn: function(t, p) {}, sig: 'vii' },
  'glDeleteProgramsARB': { fn: function(n, p) {}, sig: 'vii' },
  'glGenProgramsARB': { fn: function(n, p) { return 0; }, sig: 'vii' },
  'glGetProgramivARB': { fn: function(t, p, v) {}, sig: 'viii' },
  'glGetProgramStringARB': { fn: function(t, p, l, s) {}, sig: 'viiii' },
  'glIsProgramARB': { fn: function(p) { return 0; }, sig: 'ii' },
  'glGenQueries': { fn: function(n, q) {}, sig: 'vii' },
  'glDeleteQueries': { fn: function(n, q) {}, sig: 'vii' },
  'glIsQuery': { fn: function(q) { return 0; }, sig: 'ii' },
  'glBeginQuery': { fn: function(t, q) {}, sig: 'vii' },
  'glEndQuery': { fn: function(t) {}, sig: 'vi' },
  'glGetQueryiv': { fn: function(t, p, v) {}, sig: 'viii' },
  'glGetQueryObjectiv': { fn: function(q, p, v) {}, sig: 'viii' },
  'glGetQueryObjectuiv': { fn: function(q, p, v) {}, sig: 'viii' },
  'glBindBuffer': { fn: function(t, b) {}, sig: 'vii' },
  'glDeleteBuffers': { fn: function(n, b) {}, sig: 'vii' },
  'glGenBuffers': { fn: function(n, b) {}, sig: 'vii' },
  'glIsBuffer': { fn: function(b) { return 0; }, sig: 'ii' },
  'glBufferData': { fn: function(t, s, d, u) {}, sig: 'viiii' },
  'glBufferSubData': { fn: function(t, o, s, d) {}, sig: 'viiii' },
  'glGetBufferSubData': { fn: function(t, o, s, d) {}, sig: 'viiii' },
  'glMapBuffer': { fn: function(t, a) { return 0; }, sig: 'iii' },
  'glUnmapBuffer': { fn: function(t) { return 1; }, sig: 'ii' },
  'glGetBufferParameteriv': { fn: function(t, p, v) {}, sig: 'viii' },
  'glGetBufferPointerv': { fn: function(t, p, v) {}, sig: 'viii' },
  'glMapBufferRange': { fn: function(t, o, l, a) { return 0; }, sig: 'iiiii' },
  'glFlushMappedBufferRange': { fn: function(t, o, l) {}, sig: 'viii' },
  'glBindBufferBase': { fn: function(t, i, b) {}, sig: 'viii' },
  'glBindBufferRange': { fn: function(t, i, b, o, sz) {}, sig: 'viiiii' },
  'glDeleteVertexArrays': { fn: function(n, a) {}, sig: 'vii' },
  'glGenVertexArrays': { fn: function(n, a) {}, sig: 'vii' },
  'glIsVertexArray': { fn: function(a) { return 0; }, sig: 'ii' },
  'glFenceSync': { fn: function(c, f) { return 0; }, sig: 'iii' },
  'glIsSync': { fn: function(s) { return 0; }, sig: 'ii' },
  'glDeleteSync': { fn: function(s) {}, sig: 'vi' },
  'glClientWaitSync': { fn: function(s, f, t) { return 0; }, sig: 'iiii' },
  'glWaitSync': { fn: function(s, f, t) {}, sig: 'viii' },
  'glGetSynciv': { fn: function(s, p, l, v) {}, sig: 'viiii' },
};
"""

# ============================================================
# 2. dlsym/dlopen intercept
# ============================================================
dlsym_patch = """
// === DLSYM/DLOPEN INTERCEPT: Resolve GL functions via __glStubs ===
var _orig_dlopen_js = __dlopen_js;
__dlopen_js = function(handle) {
  // Intercept dlopen for GL libraries — return fake handle
  if (handle === 0) return 0;
  var name = UTF8ToString(handle);
  var glLibs = ['libGL.so', 'libGLESv2.so', 'libGLESv3.so', 'libEGL.so', 'libGLU.so', 'libglut.so', 'libtogl.so'];
  for (var i = 0; i < glLibs.length; i++) {
    if (name && name.indexOf(glLibs[i]) >= 0) {
      console.log('[DLOPEN] Intercepted GL library: ' + name + ' -> fake handle 999');
      return 999;
    }
  }
  return _orig_dlopen_js(handle);
};

var _orig_dlsym_js = __dlsym_js;
__dlsym_js = function(handle, symbol, symbolIndex) {
  // Check GL stubs table first
  var name = UTF8ToString(symbol);
  if (Module.__glStubs && Module.__glStubs[name]) {
    var stub = Module.__glStubs[name];
    var ptr = addFunction(stub.fn, stub.sig);
    console.log('[DLSYM] GL stub resolved: ' + name + ' -> ' + ptr);
    return ptr;
  }
  return _orig_dlsym_js(handle, symbol, symbolIndex);
};
"""

# ============================================================
# 3. GL version spoof
# ============================================================
gl_version_spoof = """
// === GL VERSION SPOOF: Report desktop GL 3.3.0 instead of OpenGL ES 3.0 ===
"""

# ============================================================
# Apply patches
# ============================================================

# Check if already patched (GL stubs is the sentinel)
if 'Module.__glStubs' in js:
    print('GL stubs already present — updating chunk URL only')
    # Still apply chunk URL fix and canvas fix even if GL stubs exist
    with open(js_path, 'w') as f:
        f.write(js)
    sys.exit(0)

# Find insertion point for GL stubs: right before "var _emscripten_GetProcAddress"
insert_marker = 'var _emscripten_GetProcAddress'
if insert_marker not in js:
    insert_marker = 'function assignWasmImports'

if insert_marker in js:
    idx = js.index(insert_marker)
    js = js[:idx] + gl_stubs_block + '\n' + js[idx:]
    print('GL stubs table injected')
else:
    js = js + '\n' + gl_stubs_block
    print('GL stubs table appended at end')

# Inject dlsym/dlopen intercept after __dlsym_js definition
dlsym_marker = '__dlsym_js.sig = "pppp";'
if dlsym_marker in js:
    idx = js.index(dlsym_marker) + len(dlsym_marker)
    js = js[:idx] + '\n' + dlsym_patch + '\n' + js[idx:]
    print('dlsym/dlopen intercept injected')
else:
    print('WARNING: Could not find dlsym insertion point')

# GL version spoof — replace OpenGL ES version strings with 3.3.0
patterns_replaced = 0

old_es3 = 'glVersion = `OpenGL ES 3.0 (${webGLVersion})`'
new_es3 = 'glVersion = `3.3.0 (${webGLVersion})`'
if old_es3 in js:
    js = js.replace(old_es3, new_es3)
    patterns_replaced += 1
    print('GL version spoofed: OpenGL ES 3.0 -> 3.3.0')

old_es2 = 'glVersion = `OpenGL ES 2.0 (${webGLVersion})`'
new_es2 = 'glVersion = `3.3.0 (${webGLVersion})`'
if old_es2 in js:
    js = js.replace(old_es2, new_es2)
    patterns_replaced += 1
    print('GL version spoofed: OpenGL ES 2.0 -> 3.3.0')

old_300 = 'var glVersion = `3.0.0'
if old_300 in js:
    js = js.replace(old_300, 'var glVersion = `3.3.0')
    patterns_replaced += 1
    print('GL version spoofed: 3.0.0 -> 3.3.0')

if patterns_replaced == 0:
    m = re.search(r'(glVersion\s*=\s*["`])OpenGL ES (\d+\.\d+)', js)
    if m:
        js = js[:m.start(2)] + '3.3.0' + js[m.end(2):]
        patterns_replaced += 1
        print(f'GL version spoofed via regex: OpenGL ES {m.group(2)} -> 3.3.0')

if patterns_replaced == 0:
    m = re.search(r'(glVersion\s*=\s*["`])(\d+\.\d+\.\d+)', js)
    if m:
        js = js[:m.start(2)] + '3.3.0' + js[m.end(2):]
        patterns_replaced += 1
        print(f'GL version spoofed via regex: {m.group(2)} -> 3.3.0')

if patterns_replaced == 0:
    print('WARNING: Could not find glVersion to spoof')
else:
    print(f'Total GL version patterns replaced: {patterns_replaced}')

with open(js_path, 'w') as f:
    f.write(js)

print('Done! All patches applied to ' + js_path)
