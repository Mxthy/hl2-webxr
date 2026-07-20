#!/usr/bin/env python3
"""Patch Emscripten-generated hl2_launcher.js with runtime safety fixes:
1. Fallback OffscreenCanvas in do_create_context (worker GL)
2. abort() made non-fatal (log + return instead of throw)
3. handleException catches RuntimeError: unreachable gracefully
4. Worker onmessage: ESCAPE_SIGTRAP → setMainLoop + non-fatal errors
5. _proc_exit throws ESCAPE_EXIT (skip unreachable after exit)
6. wasmImports['raise'] override for side modules (ESCAPE_SIGTRAP)
7. em_loop_iteration stub → no-op fallback (won't abort if missing)
8. setMainLoop logging for debugging
"""
import sys, re

js_path = sys.argv[1]
with open(js_path, 'r') as f:
    js = f.read()

patches_applied = 0

# ============================================================
# PATCH 1: Fallback OffscreenCanvas in do_create_context
# ============================================================
old_create_context = """  var canvas = findCanvasEventTarget(target);
  if (!canvas) {
    return 0;
  }"""
new_create_context = """  var canvas = findCanvasEventTarget(target);
  if (!canvas) {
    // FALLBACK: Worker has no DOM access — create standalone OffscreenCanvas
    if (typeof OffscreenCanvas !== 'undefined') {
      canvas = new OffscreenCanvas(1280, 800);
      console.log('[GL] Fallback OffscreenCanvas(1280,800) created for worker');
    } else {
      console.error('[GL] No canvas and no OffscreenCanvas available');
      return 0;
    }
  }"""
if old_create_context in js:
    js = js.replace(old_create_context, new_create_context, 1)
    patches_applied += 1
    print("  ✓ Fallback OffscreenCanvas in do_create_context")
else:
    print("  ✗ Fallback OffscreenCanvas pattern not found")

# ============================================================
# PATCH 2: abort() made non-fatal
# ============================================================
old_abort_throw = "  throw e;\n}\n\n// include: memoryprofiler.js"
new_abort_throw = """  // Non-fatal abort: log and continue
  console.error('[ABORT-CAUGHT] ' + what);
  ABORT = false;
  EXITSTATUS = 0;
  return;
}

// include: memoryprofiler.js"""
if old_abort_throw in js:
    js = js.replace(old_abort_throw, new_abort_throw, 1)
    patches_applied += 1
    print("  ✓ abort() made non-fatal")
else:
    print("  ✗ abort() pattern not found")

# ============================================================
# PATCH 3: handleException catches RuntimeError: unreachable
# Original pattern (from emsdk 3.1.72 Build 93):
# ============================================================
old_handle_exc = """var handleException = e => {
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
new_handle_exc = """var handleException = e => {
  if (e instanceof ExitStatus || e == "unwind") {
    return EXITSTATUS;
  }
  if (e instanceof WebAssembly.RuntimeError) {
    var msg = e.message || '';
    if (msg.includes('unreachable') || msg.includes('Aborted')) {
      console.error('[HANDLE-EXC] Caught RuntimeError: ' + msg.substring(0, 100) + ' — continuing');
      ABORT = false;
      EXITSTATUS = 0;
      return 0;
    }
    if (_emscripten_stack_get_current() <= 0) {
      err("Stack overflow detected.  You can try increasing -sSTACK_SIZE (currently set to 67108864)");
    }
  }
  checkStackCookie();
  quit_(1, e);
};"""
if old_handle_exc in js:
    js = js.replace(old_handle_exc, new_handle_exc, 1)
    patches_applied += 1
    print("  ✓ handleException catches unreachable")
else:
    print("  ✗ handleException pattern not found")

# ============================================================
# PATCH 4: Worker onmessage catches ESCAPE_SIGTRAP + ESCAPE_EXIT + non-fatal RuntimeErrors
# ============================================================
old_worker_catch = """    } catch (ex) {
      err(`worker: onmessage() captured an uncaught exception: ${ex}`);
      if (ex?.stack) err(ex.stack);
      __emscripten_thread_crashed();
      throw ex;
    }"""
new_worker_catch = """    } catch (ex) {
      if (ex === "ESCAPE_SIGTRAP") {
        console.warn("[WORKER] ESCAPE_SIGTRAP caught — stack unwound, starting main loop");
        ABORT = false;
        EXITSTATUS = 0;
        try {
          setMainLoop(__Z17em_loop_iterationv, 0, true);
          console.log("[POST-UNWIND] Main loop started (unwind exception is normal)");
        } catch(mlEx) {
          if (mlEx === "unwind") {
            console.log("[POST-UNWIND] Main loop started (unwind exception is normal)");
          } else {
            console.error("[POST-UNWIND] Failed to start main loop: " + mlEx);
          }
        }
      } else if (ex === "ESCAPE_EXIT") {
        console.warn("[WORKER] ESCAPE_EXIT caught — _proc_exit bypassed, continuing");
        ABORT = false;
        EXITSTATUS = 0;
      } else if (ex instanceof WebAssembly.RuntimeError && (ex.message?.includes('unreachable') || ex.message?.includes('Aborted'))) {
        err(`worker: caught non-fatal RuntimeError (continuing): ${ex.message?.substring(0, 80)}`);
        ABORT = false;
        EXITSTATUS = 0;
      } else {
        err(`worker: onmessage() captured an uncaught exception: ${ex}`);
        if (ex?.stack) err(ex.stack);
        __emscripten_thread_crashed();
        throw ex;
      }
    }"""
if old_worker_catch in js:
    js = js.replace(old_worker_catch, new_worker_catch, 1)
    patches_applied += 1
    print("  ✓ Worker onmessage: ESCAPE_SIGTRAP → setMainLoop + ESCAPE_EXIT handler")
else:
    print("  ✗ Worker onmessage pattern not found")

# ============================================================
# PATCH 5: _proc_exit throws ESCAPE_EXIT (skip unreachable after exit)
# Original pattern (from emsdk 3.1.72 Build 93):
# ============================================================
old_proc_exit = """function _proc_exit(code) {
  if (ENVIRONMENT_IS_PTHREAD) return proxyToMainThread(0, 0, 1, code);
  EXITSTATUS = code;
  if (!keepRuntimeAlive()) {
    PThread.terminateAllThreads();
    Module["onExit"]?.(code);
    ABORT = true;
  }
  quit_(code, new ExitStatus(code));
}"""
new_proc_exit = """function _proc_exit(code) {
  if (ENVIRONMENT_IS_PTHREAD) return proxyToMainThread(0, 0, 1, code);
  console.warn('[PROC-EXIT] _proc_exit(' + code + ') — throwing ESCAPE_EXIT to skip unreachable');
  EXITSTATUS = 0;
  ABORT = false;
  throw "ESCAPE_EXIT";
}"""
if old_proc_exit in js:
    js = js.replace(old_proc_exit, new_proc_exit, 1)
    patches_applied += 1
    print("  ✓ _proc_exit throws ESCAPE_EXIT")
else:
    print("  ✗ _proc_exit pattern not found")

# ============================================================
# PATCH 6: Override raise in wasmImports for side modules
# raise is a WASM export (idx=6001) in the main module.
# Side modules import raise from env (wasmImports).
# After mergeLibSymbols, wasmImports["raise"] = main module's raise export.
# We override it to throw ESCAPE_SIGTRAP, unwinding the stack on Sys_Error.
# ============================================================
old_merge = 'mergeLibSymbols(wasmExports, "main");'
new_merge = """mergeLibSymbols(wasmExports, "main");
  // Override raise for side modules — throw ESCAPE_SIGTRAP to unwind stack
  wasmImports["raise"] = function(sig) {
    console.error('[RAISE-SIDE] raise(' + sig + ') from side module — throwing ESCAPE_SIGTRAP');
    throw "ESCAPE_SIGTRAP";
  };
  console.log("[OVERRIDE] wasmImports['raise'] replaced with ESCAPE_SIGTRAP throw");"""
if old_merge in js:
    js = js.replace(old_merge, new_merge, 1)
    patches_applied += 1
    print("  ✓ wasmImports['raise'] override for side modules")
else:
    print("  ✗ mergeLibSymbols pattern not found (side module raise override)")

# ============================================================
# PATCH 7: em_loop_iteration stub → no-op fallback
# If Build #98's EMSCRIPTEN_KEEPALIVE works, no stub is generated.
# If it fails, the stub would abort. We make it a no-op instead.
# ============================================================
old_em_loop = "abort(\"external symbol '_Z17em_loop_iterationv' is missing. perhaps a side module was not linked in? if this function was expected to arrive from a system library, try to build the MAIN_MODULE with EMCC_FORCE_STDLIBS=1 in the environment\");"
new_em_loop = "console.warn('[EM-LOOP] em_loop_iteration not found — using JS no-op fallback'); return 0;"
if old_em_loop in js:
    js = js.replace(old_em_loop, new_em_loop, 1)
    patches_applied += 1
    print("  ✓ em_loop_iteration stub → no-op fallback (won't abort)")
else:
    print("  ✗ em_loop_iteration stub pattern not found (may already be resolved by KEEPALIVE)")

# ============================================================
# PATCH 8: setMainLoop logging (debugging aid)
# ============================================================
old_set_main = """     */ var setMainLoop = (iterFunc, fps, simulateInfiniteLoop, arg, noSetTiming) => {
  assert(!MainLoop.func, "emscripten_set_main_loop: there can only be one main loop function at once: call emscripten_cancel_main_loop to cancel the previous one before setting a new one with different parameters.");"""
new_set_main = """     */ var setMainLoop = (iterFunc, fps, simulateInfiniteLoop, arg, noSetTiming) => {
  console.log("[SET-MAIN-LOOP] setMainLoop called! fps=" + fps + " simulateInfinite=" + simulateInfiniteLoop + " iterFunc=" + typeof iterFunc);
  assert(!MainLoop.func, "emscripten_set_main_loop: there can only be one main loop function at once: call emscripten_cancel_main_loop to cancel the previous one before setting a new one with different parameters.");"""
if old_set_main in js:
    js = js.replace(old_set_main, new_set_main, 1)
    patches_applied += 1
    print("  ✓ setMainLoop logging added")
else:
    print("  ✗ setMainLoop pattern not found")

with open(js_path, 'w') as f:
    f.write(js)

print(f"\n{patches_applied}/8 runtime patches applied to {js_path}")
