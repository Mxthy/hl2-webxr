#!/usr/bin/env python3
"""Patch Emscripten-generated hl2_launcher.js with runtime safety fixes:
1. Fallback OffscreenCanvas in do_create_context (worker GL)
2. abort() made non-fatal (log + return instead of throw)
3. handleException catches RuntimeError: unreachable gracefully
4. Worker onmessage catches non-fatal RuntimeErrors
"""
import sys, re

js_path = sys.argv[1]
with open(js_path, 'r') as f:
    js = f.read()

patches_applied = 0

# ============================================================
# PATCH 3: Fallback OffscreenCanvas in do_create_context
# When the engine worker can't find the canvas via findCanvasEventTarget
# (workers have no DOM), create a standalone OffscreenCanvas for GL.
# ============================================================
# Find the do_create_context function and add fallback
old_create_context = """    var canvas = findCanvasEventTarget(target);
    if (!canvas) {
      return 0;
    }"""
new_create_context = """    var canvas = findCanvasEventTarget(target);
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
# PATCH 7: abort() made non-fatal
# Log and return instead of throwing WebAssembly.RuntimeError
# ============================================================
# Find the throw e at the end of abort function
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
# PATCH 8: handleException catches RuntimeError: unreachable
# ============================================================
old_handle_exc = """var handleException = e => {
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
# PATCH 9: Worker onmessage catches non-fatal RuntimeErrors
# ============================================================
old_worker_catch = """    } catch (ex) {
      err(`worker: onmessage() captured an uncaught exception: ${ex}`);
      if (ex?.stack) err(ex.stack);
      __emscripten_thread_crashed();
      throw ex;
    }"""
new_worker_catch = """    } catch (ex) {
      if (ex instanceof WebAssembly.RuntimeError && (ex.message?.includes('unreachable') || ex.message?.includes('Aborted'))) {
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
    print("  ✓ Worker onmessage catches non-fatal errors")
else:
    print("  ✗ Worker onmessage pattern not found")

with open(js_path, 'w') as f:
    f.write(js)

print(f"\n{patches_applied}/4 runtime patches applied to {js_path}")
