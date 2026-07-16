#!/usr/bin/env python3
"""Inject GL stubs, dlsym/dlopen intercept, GL version spoof, chunk URL fix,
and canvas size enforcement into hl2_launcher.js"""
import sys, re

js_path = sys.argv[1]
with open(js_path, 'r') as f:
    js = f.read()

# ============================================================
# 0. Chunk URL fix — redirect chunk loading to R2 proxy
# ============================================================
R2_PROXY_BASE = 'https://hl2-assets-proxy.hl2-webxr.workers.dev/chunks/'

# Replace relative chunk URL with R2 proxy URL
old_chunk_url = '`chunks/${mapName}.data`'
new_chunk_url = '`' + R2_PROXY_BASE + '${mapName}.data`'
if old_chunk_url in js:
    js = js.replace(old_chunk_url, new_chunk_url)
    print('Chunk URL redirected to R2 proxy: ' + R2_PROXY_BASE)
elif R2_PROXY_BASE in js:
    print('Chunk URL already pointing to R2 proxy')
else:
    # Try alternative patterns
    alt_pattern = r'["\']chunks/\$\{mapName\}\.data["\']'
    if re.search(alt_pattern, js):
        js = re.sub(alt_pattern, '`' + R2_PROXY_BASE + '${mapName}.data`', js)
        print('Chunk URL redirected to R2 proxy (via regex)')
    else:
        print('WARNING: Could not find chunk URL pattern to patch')

# ============================================================
# 0b. Canvas size enforcement — ensure canvas has non-zero dimensions
# ============================================================
canvas_fix = """
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

# Insert canvas fix right after the pre.js section (after Module setup)
# Find the end of the inlined pre.js
pre_js_end = '// end include:'
if pre_js_end in js:
    idx = js.index(pre_js_end)
    # Find the end of that line
    line_end = js.index('\n', idx)
    js = js[:line_end+1] + canvas_fix + '\n' + js[line_end+1:]
    print('Canvas size enforcement injected after pre.js')
else:
    print('WARNING: Could not find pre.js end marker for canvas fix')

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
