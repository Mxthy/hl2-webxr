#!/usr/bin/env python3
"""Patch Emscripten-generated hl2_launcher.js with runtime safety fixes:
1. Fallback OffscreenCanvas in setCanvasElementSizeCallingThread (worker)
2. abort() made non-fatal
3. handleException catches RuntimeError + ESCAPE_EXIT
4. Worker onmessage: ESCAPE_SIGTRAP/ESCAPE_EXIT -> setMainLoop(Engine_RenderSingleFrame)
5. _proc_exit throws ESCAPE_EXIT directly (NO proxy)
6. wasmImports['raise'] override for side modules
7. em_loop_iteration stub -> no-op
8. setMainLoop logging
9. findCanvasEventTarget: #canvas -> first OffscreenCanvas (ID mismatch fix)
10. do_create_context: use transferred canvas instead of standalone
"""
import sys, re

js_path = sys.argv[1]
with open(js_path, 'r') as f:
    js = f.read()

patches_applied = 0

# ============================================================
# PATCH 1: Fallback OffscreenCanvas in setCanvasElementSizeCallingThread
# ============================================================
old_1 = """  var canvas = findCanvasEventTarget(target);
  if (!canvas) {
    return -4;
  }"""
new_1 = """  var canvas = findCanvasEventTarget(target);
  if (!canvas) {
    if (typeof OffscreenCanvas !== 'undefined') {
      canvas = new OffscreenCanvas(1280, 800);
      console.log('[GL] Fallback OffscreenCanvas for setCanvasElementSize');
    } else {
      return -4;
    }
  }"""
if old_1 in js:
    js = js.replace(old_1, new_1, 1)
    patches_applied += 1
    print("  + Fallback OffscreenCanvas in setCanvasElementSize")
else:
    print("  x setCanvasElementSize pattern not found")

# ============================================================
# PATCH 2: abort() made non-fatal
# ============================================================
old_2 = "  throw e;\n}\n\n// include: memoryprofiler.js"
new_2 = """  console.error('[ABORT-CAUGHT] ' + what);
  ABORT = false;
  EXITSTATUS = 0;
  return;
}

// include: memoryprofiler.js"""
if old_2 in js:
    js = js.replace(old_2, new_2, 1)
    patches_applied += 1
    print("  + abort() made non-fatal")
else:
    print("  x abort() pattern not found")

# ============================================================
# PATCH 3: handleException catches RuntimeError + ESCAPE_EXIT
# ============================================================
he_patched = False
# Pattern A: original emsdk
old_3a = """var handleException = e => {
  // Certain exception types we do not treat as errors since they are used for
  // internal control flow.
  // 1. ExitStatus, which is thrown by exit()
  // 2. "unwind", which is thrown by emscripten_unwind_to_js_event_loop() and others
  //    that wish to return to JS event loop.
  if (e instanceof ExitStatus || e == "unwind") {
    return EXITSTATUS;
  }
  checkStackCookie();
  if (e instanceof WebAssembly.RuntimeError) {
    if (_emscripten_stack_get_current() <= 0) {
      err("Stack overflow detected.  You can try increasing -sSTACK_SIZE (currently set to 67108864)");
    }
  }
  quit_(1, e);
};"""
new_3a = """var handleException = e => {
  if (e instanceof ExitStatus || e == "unwind") {
    return EXITSTATUS;
  }
  if (e === "ESCAPE_EXIT") {
    console.warn("[HANDLE-EXC] ESCAPE_EXIT caught -- keeping runtime alive");
    return EXITSTATUS || 0;
  }
  if (e instanceof WebAssembly.RuntimeError) {
    var msg = e.message || '';
    if (msg.includes('unreachable') || msg.includes('Aborted')) {
      console.error('[HANDLE-EXC] RuntimeError: ' + msg.substring(0, 100) + ' -- continuing');
      ABORT = false; EXITSTATUS = 0; return 0;
    }
    if (_emscripten_stack_get_current() <= 0) {
      err("Stack overflow detected.");
    }
  }
  checkStackCookie();
  quit_(1, e);
};"""
if old_3a in js:
    js = js.replace(old_3a, new_3a, 1)
    patches_applied += 1; he_patched = True
    print("  + handleException catches unreachable + ESCAPE_EXIT")

# Pattern B: already has RuntimeError catch, add ESCAPE_EXIT
if not he_patched:
    if 'e === "ESCAPE_EXIT"' in js and 'handleException' in js:
        patches_applied += 1; he_patched = True
        print("  + handleException: ESCAPE_EXIT already present")
    elif 'handleException' in js and 'unreachable' in js:
        # Insert ESCAPE_EXIT catch after the unwind check
        old_3b = 'if (e instanceof ExitStatus || e == "unwind") {\n    return EXITSTATUS;\n  }'
        new_3b = 'if (e instanceof ExitStatus || e == "unwind") {\n    return EXITSTATUS;\n  }\n  if (e === "ESCAPE_EXIT") {\n    console.warn("[HANDLE-EXC] ESCAPE_EXIT caught -- keeping runtime alive");\n    return EXITSTATUS || 0;\n  }'
        if old_3b in js:
            js = js.replace(old_3b, new_3b, 1)
            patches_applied += 1; he_patched = True
            print("  + handleException: added ESCAPE_EXIT catch")

if not he_patched:
    print("  x handleException pattern not found")

# ============================================================
# PATCH 4: Worker onmessage -> start main loop with Engine_RenderSingleFrame
# ============================================================
old_4 = """    } catch (ex) {
      err(`worker: onmessage() captured an uncaught exception: ${ex}`);
      if (ex?.stack) err(ex.stack);
      __emscripten_thread_crashed();
      throw ex;
    }"""
new_4 = """    } catch (ex) {
      if (ex === "ESCAPE_SIGTRAP") {
        console.warn("[WORKER] ESCAPE_SIGTRAP caught -- starting main loop");
        ABORT = false; EXITSTATUS = 0;
        try {
          var rFn = (Module.wasmExports && Module.wasmExports.Engine_RenderSingleFrame) ? Module.wasmExports.Engine_RenderSingleFrame : __Z17em_loop_iterationv;
          setMainLoop(rFn, 0, true);
          console.log("[POST-UNWIND] Main loop started with Engine_RenderSingleFrame");
        } catch(mlEx) {
          if (mlEx === "unwind") { console.log("[POST-UNWIND] Main loop started"); }
          else { console.error("[POST-UNWIND] Main loop failed: " + mlEx); }
        }
      } else if (ex === "ESCAPE_EXIT") {
        console.warn("[WORKER] ESCAPE_EXIT caught -- starting main loop");
        ABORT = false; EXITSTATUS = 0;
        try {
          var rFn = (Module.wasmExports && Module.wasmExports.Engine_RenderSingleFrame) ? Module.wasmExports.Engine_RenderSingleFrame : __Z17em_loop_iterationv;
          setMainLoop(rFn, 0, true);
          console.log("[POST-EXIT] Main loop started with Engine_RenderSingleFrame");
        } catch(mlEx) {
          if (mlEx === "unwind") { console.log("[POST-EXIT] Main loop started"); }
          else { console.error("[POST-EXIT] Main loop failed: " + mlEx); }
        }
      } else if (ex instanceof WebAssembly.RuntimeError && (ex.message?.includes('unreachable') || ex.message?.includes('Aborted'))) {
        err(`worker: non-fatal RuntimeError: ${ex.message?.substring(0, 80)}`);
        ABORT = false; EXITSTATUS = 0;
      } else {
        err(`worker: uncaught exception: ${ex}`);
        if (ex?.stack) err(ex.stack);
        __emscripten_thread_crashed();
        throw ex;
      }
    }"""
if old_4 in js:
    js = js.replace(old_4, new_4, 1)
    patches_applied += 1
    print("  + Worker onmessage: ESCAPE_EXIT -> setMainLoop(Engine_RenderSingleFrame)")
else:
    if 'ESCAPE_EXIT' in js and 'POST-EXIT' in js and 'Engine_RenderSingleFrame' in js:
        patches_applied += 1
        print("  + Worker onmessage: already patched")
    else:
        print("  x Worker onmessage pattern not found")

# ============================================================
# PATCH 5: _proc_exit throws ESCAPE_EXIT directly (NO proxy)
# ============================================================
pe_patched = False
old_5a = """function _proc_exit(code) {
  if (ENVIRONMENT_IS_PTHREAD) return proxyToMainThread(0, 0, 1, code);
  EXITSTATUS = code;
  if (!keepRuntimeAlive()) {
    PThread.terminateAllThreads();
    Module["onExit"]?.(code);
    ABORT = true;
  }
  quit_(code, new ExitStatus(code));
}"""
new_5a = """function _proc_exit(code) {
  console.warn('[PROC-EXIT] _proc_exit(' + code + ') -- ESCAPE_EXIT (thread: ' + (ENVIRONMENT_IS_PTHREAD ? 'worker' : 'main') + ')');
  EXITSTATUS = 0; ABORT = false;
  throw "ESCAPE_EXIT";
}"""
if old_5a in js:
    js = js.replace(old_5a, new_5a, 1)
    patches_applied += 1; pe_patched = True
    print("  + _proc_exit throws ESCAPE_EXIT (no proxy)")

if not pe_patched:
    # Check if already patched (no proxyToMainThread line)
    if '_proc_exit' in js and 'ESCAPE_EXIT' in js:
        proc_section = js[js.index('_proc_exit'):js.index('_proc_exit')+300]
        if 'proxyToMainThread' not in proc_section:
            patches_applied += 1; pe_patched = True
            print("  + _proc_exit: already has no proxy")
        else:
            # Remove the proxy line
            old_proxy = '  if (ENVIRONMENT_IS_PTHREAD) return proxyToMainThread(0, 0, 1, code);\n'
            if old_proxy in js:
                js = js.replace(old_proxy, '', 1)
                patches_applied += 1; pe_patched = True
                print("  + _proc_exit: removed proxy line")

if not pe_patched:
    print("  x _proc_exit pattern not found")

# ============================================================
# PATCH 6: wasmImports['raise'] override
# ============================================================
old_6 = 'mergeLibSymbols(wasmExports, "main");'
new_6 = """mergeLibSymbols(wasmExports, "main");
  wasmImports["raise"] = function(sig) {
    console.error('[RAISE-SIDE] raise(' + sig + ') -- ESCAPE_SIGTRAP');
    throw "ESCAPE_SIGTRAP";
  };
  console.log("[OVERRIDE] wasmImports['raise'] replaced");"""
if old_6 in js:
    js = js.replace(old_6, new_6, 1)
    patches_applied += 1
    print("  + wasmImports['raise'] override")
else:
    print("  x mergeLibSymbols not found")

# ============================================================
# PATCH 7: em_loop_iteration stub -> no-op
# ============================================================
old_7 = "abort(\"external symbol '_Z17em_loop_iterationv' is missing."
if old_7 in js:
    js = js.replace(js[js.index(old_7):js.index('");', js.index(old_7))+2],
                    "console.warn('[EM-LOOP] no-op fallback'); return 0;", 1)
    patches_applied += 1
    print("  + em_loop_iteration -> no-op")
else:
    print("  x em_loop_iteration stub not found")

# ============================================================
# PATCH 8: setMainLoop logging
# ============================================================
old_8 = '     */ var setMainLoop = (iterFunc, fps, simulateInfiniteLoop, arg, noSetTiming) => {\n  assert(!MainLoop.func'
new_8 = '     */ var setMainLoop = (iterFunc, fps, simulateInfiniteLoop, arg, noSetTiming) => {\n  console.log("[SET-MAIN-LOOP] fps=" + fps + " iterFunc=" + typeof iterFunc);\n  assert(!MainLoop.func'
if old_8 in js:
    js = js.replace(old_8, new_8, 1)
    patches_applied += 1
    print("  + setMainLoop logging")
else:
    print("  x setMainLoop logging not found")

# ============================================================
# PATCH 9: findCanvasEventTarget -- #canvas -> first OffscreenCanvas
# The engine asks for "#canvas" but transferred canvas is stored as "game-canvas"
# ============================================================
old_9 = """var findCanvasEventTarget = target => {
  target = maybeCStringToJsString(target);
  // When compiling with OffscreenCanvas support and looking up a canvas to target,
  // we first look up if the target Canvas has been transferred to OffscreenCanvas use.
  // These transfers are represented/tracked by GL.offscreenCanvases object, which contain
  // the OffscreenCanvas element for each regular Canvas element that has been transferred.
  // Note that each pthread/worker have their own set of GL.offscreenCanvases. That is,
  // when an OffscreenCanvas is transferred from a pthread/main thread to another pthread,
  // it will move in the GL.offscreenCanvases array between threads. Hence GL.offscreenCanvases
  // represents the set of OffscreenCanvases owned by the current calling thread.
  // First check out the list of OffscreenCanvases by CSS selector ID ('#myCanvasID')
  return GL.offscreenCanvases[target.substr(1)] || // Remove '#' prefix
  // If not found, if one is querying by using DOM tag name selector 'canvas', grab the first
  // OffscreenCanvas that we can find.
  (target == "canvas" && Object.keys(GL.offscreenCanvases)[0]) || // If that is not found either, query via the regular DOM selector.
  (typeof document != "undefined" && document.querySelector(target));
};"""
new_9 = """var findCanvasEventTarget = target => {
  target = maybeCStringToJsString(target);
  var found = GL.offscreenCanvases[target.substr(1)];
  if (found) return found;
  if ((target == "canvas" || target == "#canvas") && Object.keys(GL.offscreenCanvases)[0]) {
    return GL.offscreenCanvases[Object.keys(GL.offscreenCanvases)[0]];
  }
  if (typeof document != "undefined") return document.querySelector(target);
  return null;
};"""
if old_9 in js:
    js = js.replace(old_9, new_9, 1)
    patches_applied += 1
    print("  + findCanvasEventTarget: #canvas -> first OffscreenCanvas")
else:
    print("  x findCanvasEventTarget pattern not found (may already be patched)")

# ============================================================
# PATCH 10: do_create_context -- use transferred canvas, not standalone
# ============================================================
# Pattern A: forced OffscreenCanvas (our old patch)
old_10a = """  var canvas = findCanvasEventTarget(target);
  // PATCH: Always use OffscreenCanvas fallback — never create GL context on HTML canvas
  // This prevents transferControlToOffscreen() from failing later in pthread_create
  if (typeof OffscreenCanvas !== 'undefined') {
    canvas = new OffscreenCanvas(1280, 800);
    console.log('[GL] Forced OffscreenCanvas(1280,800) — preserving HTML canvas for pthread transfer');
  } else if (!canvas) {
    console.error('[GL] No canvas and no OffscreenCanvas available');
    return 0;
  }
  if (canvas.offscreenCanvas) canvas = canvas.offscreenCanvas;"""
new_10 = """  var canvas = findCanvasEventTarget(target);
  if (!canvas) {
    if (typeof OffscreenCanvas !== 'undefined') {
      canvas = new OffscreenCanvas(1280, 800);
      console.log('[GL] Fallback OffscreenCanvas -- no transferred canvas');
    } else {
      console.error('[GL] No canvas available');
      return 0;
    }
  } else {
    console.log('[GL] Using transferred canvas: ' + (canvas.id || 'unknown'));
  }
  if (canvas.offscreenCanvas) canvas = canvas.offscreenCanvas;"""
if old_10a in js:
    js = js.replace(old_10a, new_10, 1)
    patches_applied += 1
    print("  + do_create_context: use transferred canvas (was forced)")
else:
    # Pattern B: original emsdk (no fallback)
    old_10b = """  var canvas = findCanvasEventTarget(target);
  if (!canvas) {
    return 0;
  }
  if (canvas.offscreenCanvas) canvas = canvas.offscreenCanvas;"""
    if old_10b in js:
        js = js.replace(old_10b, new_10, 1)
        patches_applied += 1
        print("  + do_create_context: use transferred canvas (was original)")
    else:
        print("  x do_create_context pattern not found (may already be patched)")

with open(js_path, 'w') as f:
    f.write(js)

print(f"\n{patches_applied}/10 patches applied successfully")
if patches_applied < 6:
    print("WARNING: Critical patches missing -- render loop may not work!")
    sys.exit(1)
