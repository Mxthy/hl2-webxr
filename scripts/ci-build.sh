#!/usr/bin/env bash
# =============================================================================
#  ci-build.sh — Reproduzierbarer Build für HL2 WebXR (lokal & GitHub Actions)
#
#  Funktioniert auf Debian/Ubuntu x86_64.
#  Aufruf:
#    bash scripts/ci-build.sh           # Release
#    bash scripts/ci-build.sh debug     # Debug
#
#  Benötigte Umgebungsvariablen (optional, Defaults unten):
#    BUILDTYPE       release | debug   (default: release)
#    EMSDK_COMMIT    pinned emsdk commit hash
#    ENGINE_REPO     weliveinhell/source-engine clone-URL
#    ASSETS_ROOT     Pfad zu den HL2-Assets (hl2/ platform/ Ordner)
#    OUT_DIR         Zielordner für finale Outputs
# =============================================================================
set -euo pipefail

# ---------------------------------------------------------------------------
# 1. Konfiguration — alle variablen Pfade hier zentral
# ---------------------------------------------------------------------------
BUILDTYPE="${BUILDTYPE:-release}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

ENGINE_REPO="${ENGINE_REPO:-https://github.com/weliveinhell/source-engine}"
ENGINE_DIR="${ENGINE_DIR:-$REPO_ROOT/engine/portal-port}"

EMSDK_REPO="https://github.com/emscripten-core/emsdk.git"
EMSDK_COMMIT="${EMSDK_COMMIT:-2d480a1b7c7a34a354188d93f3e89190a44a1d21}"
EMSDK_DIR="${EMSDK_DIR:-$REPO_ROOT/tools/emsdk}"

# Assets: HL2 Retail-Verzeichnis — muss hl2/ und platform/ enthalten
ASSETS_ROOT="${ASSETS_ROOT:-$REPO_ROOT/assets/game/Half-Life 2}"

OUT_DIR="${OUT_DIR:-$REPO_ROOT/dist}"
LOG_DIR="${LOG_DIR:-$REPO_ROOT/logs}"

JOBS="${JOBS:-$(nproc 2>/dev/null || echo 4)}"

WAF_CONFIGURE_FLAGS="--togles --emscripten --notests -4 --disable-warns --build-games=portal"

# ---------------------------------------------------------------------------
# Hilfsfunktionen
# ---------------------------------------------------------------------------
log() { echo "[ci-build] $*"; }
die() { echo "[ci-build] ERROR: $*" >&2; exit 1; }

checkpoint_file="$REPO_ROOT/.build_checkpoint"
checkpoint_done() { grep -qxF "$1" "$checkpoint_file" 2>/dev/null; }
checkpoint_mark() { echo "$1" >> "$checkpoint_file"; log "✓ checkpoint: $1"; }

# ---------------------------------------------------------------------------
# 2. System-Dependencies
# ---------------------------------------------------------------------------
install_apt_deps() {
  checkpoint_done "apt_deps" && { log "apt_deps: skip"; return; }

  log "Installing apt dependencies..."
  export DEBIAN_FRONTEND=noninteractive
  sudo apt-get update -qq
  sudo apt-get install -y --no-install-recommends \
    git curl wget xz-utils python3 python3-dev python3-pip \
    cmake ninja-build build-essential \
    pkg-config \
    libsdl2-dev \
    libfreetype-dev \
    libfontconfig-dev \
    libopenal-dev \
    libjpeg-dev libpng-dev zlib1g-dev \
    libcurl4-openssl-dev libssl-dev \
    libgl1-mesa-dev libglu1-mesa-dev \
    libx11-dev libxext-dev libxi-dev \
    libbz2-dev \
    nodejs \
    2>/dev/null || true   # non-fatal: CI images often have these already

  checkpoint_mark "apt_deps"
}

# ---------------------------------------------------------------------------
# 3. emsdk installieren (gepinnter Commit)
# ---------------------------------------------------------------------------
install_emsdk() {
  checkpoint_done "emsdk_install" && { log "emsdk_install: skip"; return; }

  log "Cloning emsdk @ $EMSDK_COMMIT..."
  if [ ! -d "$EMSDK_DIR/.git" ]; then
    # Clone without depth limit so we can checkout arbitrary commits
    git clone "$EMSDK_REPO" "$EMSDK_DIR"
  fi

  cd "$EMSDK_DIR"
  git fetch origin
  git checkout "$EMSDK_COMMIT"

  log "Installing & activating emsdk 3.1.72 (prebuilt binaries)..."
  # Use a tagged release with prebuilt Clang binaries — avoids LLVM compile (~90 min)
  # 3.1.72 is the release closest to the pinned emsdk commit (2025-05-29)
  ./emsdk install 3.1.72
  ./emsdk activate 3.1.72

  checkpoint_mark "emsdk_install"
}

emsdk_env() {
  # shellcheck disable=SC1091
  # Save EMSDK_DIR before sourcing (emsdk_env.sh may alter the environment)
  local _saved_emsdk_dir="${EMSDK_DIR:-}"
  set +u  # emsdk_env.sh may reference unset variables internally
  source "$_saved_emsdk_dir/emsdk_env.sh" >/dev/null 2>&1
  set -u
  # Restore EMSDK_DIR in case it was modified
  EMSDK_DIR="$_saved_emsdk_dir"
  export EMSDK_DIR
}

# ---------------------------------------------------------------------------
# 4. Engine-Repo klonen
# ---------------------------------------------------------------------------
clone_engine() {
  checkpoint_done "repo_clone" && { log "repo_clone: skip"; return; }

  log "Cloning source-engine (weliveinhell fork)..."

  # Only a git repo with a valid HEAD counts as cloned source.
  # A restored build/ dir from the waf cache must NOT fool us.
  if [ -d "$ENGINE_DIR/.git" ] && \
     git -C "$ENGINE_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1 && \
     git -C "$ENGINE_DIR" rev-parse HEAD >/dev/null 2>&1; then
    local sha
    sha=$(git -C "$ENGINE_DIR" rev-parse --short HEAD)
    log "  source checkout exists: $sha"
  else
    log "  removing incomplete/stale source directory"
    # Stale dir (maybe build/ only from waf cache) — clear and clone fresh
    if [ -d "$ENGINE_DIR" ]; then
      find "$ENGINE_DIR" -mindepth 1 -maxdepth 1 ! -name build -exec rm -rf {} + 2>/dev/null || true
      # If build/ is all that remains and no source, remove it too
      if [ ! -f "$ENGINE_DIR/wscript" ]; then
        find "$ENGINE_DIR" -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>/dev/null || true
      fi
    fi
    git clone --depth=1 \
              --recurse-submodules \
              --shallow-submodules \
              "$ENGINE_REPO" \
              "$ENGINE_DIR"
  fi

  checkpoint_mark "repo_clone"
}

# 5. Source-Patches
# ---------------------------------------------------------------------------
apply_source_patches() {
  checkpoint_done "source_patches" && { log "source_patches: skip"; return; }

  log "Applying source patches..."

  # 5a: alloca.h für ivp_physics
  p="$ENGINE_DIR/ivp/ivp_physics/ivp_physics.hxx"
  if ! grep -q "alloca.h" "$p"; then
    sed -i 's/#include <stdio.h>/#include <stdio.h>\n#ifdef __EMSCRIPTEN__\n#include <alloca.h>\n#endif/' "$p"
    log "  patch: ivp_physics alloca.h"
  fi

  # 5b: alloca.h für hk_base
  p="$ENGINE_DIR/ivp/havana/havok/hk_base/base.h"
  if ! grep -q "alloca.h" "$p"; then
    sed -i 's/#include <stdlib.h>/#include <stdlib.h>\n#ifdef __EMSCRIPTEN__\n#include <alloca.h>\n#endif/' "$p"
    log "  patch: hk_base alloca.h"
  fi

  # 5c: ivp_mindist_minimize — alloca.h fix für Emscripten
  # Das File inkludiert alloca.h nur für LINUX/SUN/MWERKS
  # Emscripten braucht es auch (alloca() wird auf Zeile 644 genutzt)
  p="$ENGINE_DIR/ivp/ivp_collision/ivp_mindist_minimize.cxx"
  if ! grep -q "__EMSCRIPTEN__" "$p"; then
    sed -i 's/#if defined(LINUX) || defined(SUN) || (__MWERKS__ && __POWERPC__)/#if defined(LINUX) || defined(SUN) || (__MWERKS__ \&\& __POWERPC__) || defined(__EMSCRIPTEN__)/' "$p"
    log "  patch: ivp_mindist_minimize alloca.h emscripten fix"
  fi

  # 5d: emscripten_stubs.cpp
  p="$ENGINE_DIR/emscripten/emscripten_stubs.cpp"
  # Always overwrite — ensure all required symbols are present
  cat > "$p" << 'EOF'
#ifdef __EMSCRIPTEN__
#include <stdlib.h>
#include <stdio.h>
#include <sys/time.h>

unsigned long GetRam() { return 4096UL; }
int futimes(int fd, const struct timeval tv[2]) { return 0; }

// -----------------------------------------------------------------------
// IVP_Mindist vtable stubs
// -----------------------------------------------------------------------
// Emscripten MAIN_MODULE must provide these symbols so that SIDE_MODULEs
// (libvphysics.so) can resolve them via GOT at dlopen time.
// We declare them as C-linkage weak stubs so they don't conflict with
// the real definitions inside libvphysics.so's private TU.
// -----------------------------------------------------------------------
extern "C" {

// vtable + typeinfo: provided by defining the class with virtual methods
struct __attribute__((visibility("default"))) IVP_Mindist_Stub {
    virtual ~IVP_Mindist_Stub() {}
    virtual int recalc_mindist() { return 0; }
    virtual int recalc_invalid_mindist() { return 0; }
};

// Force-instantiate so the vtable symbol is emitted into main.wasm
static IVP_Mindist_Stub* __ivp_mindist_vtable_anchor = nullptr;
__attribute__((constructor)) static void __ivp_mindist_init() {
    (void)__ivp_mindist_vtable_anchor;
}

// init_mms_function_table weak stub
__attribute__((weak))
void _ZN27IVP_Mindist_Minimize_Solver23init_mms_function_tableEv(void* self) {
    (void)self;
}

// IVP_Mindist::recalc_mindist weak stub — (i32)->i32 matches libvphysics.so type[2]
__attribute__((weak))
int _ZN11IVP_Mindist14recalc_mindistEv(void* self) {
    (void)self;
    return 0;
}

// IVP_Mindist::recalc_invalid_mindist weak stub — (i32)->i32 matches libvphysics.so type[2]
__attribute__((weak))
int _ZN11IVP_Mindist22recalc_invalid_mindistEv(void* self) {
    (void)self;
    return 0;
}

} // extern "C"

#endif // __EMSCRIPTEN__
EOF
  log "  patch: emscripten_stubs.cpp (with IVP_Mindist weak stubs)"
  

  # Patch 6 (post): post.js — Shader + Asset Chunk Loading vor callMain()
  POST_JS="$ENGINE_DIR/emscripten/post.js"
  if [ -f "$POST_JS" ]; then
    cat > "$POST_JS" << 'POST_JS_EOF'
;(() => {
  if(typeof window === 'undefined') return;
  window.addEventListener('beforeunload', function (event) { event.preventDefault() })
  if (typeof canvasElement !== 'undefined') {
    canvasElement.onkeypress = e => e.preventDefault()
  }

  // ---- /MOD/ writable directory (IDBFS-backed) ----
  // Source Engine writes to /MOD/ — create real writable mount
  try {
    FS.mkdirTree('/MOD');
    FS.mkdirTree('/hl2');
    // Mount IDBFS at /MOD for persistent writes (savegames, configs, etc.)
    if (typeof IDBFS !== 'undefined') {
      FS.mount(IDBFS, {}, '/MOD');
      FS.syncfs(true, function(err) {
        if (err) console.warn('[hl2] IDBFS syncfs error:', err);
        else console.log('[hl2] /MOD/ IDBFS mount ready');
      });
    }
    // Symlink hl2 content into /MOD so engine can find gameinfo etc.
    var entries = FS.readdir('/hl2');
    for (var i = 0; i < entries.length; i++) {
      if (entries[i] === '.' || entries[i] === '..') continue;
      var src = '/hl2/' + entries[i];
      var dst = '/MOD/' + entries[i];
      if (!FS.analyzePath(dst).exists) {
        try { FS.symlink(src, dst); } catch(e) {}
      }
    }
    console.log('[hl2] /MOD/ write path initialized');
  } catch(e) { console.warn('[hl2] /MOD/ setup error:', e); }

  // ---- Shader + Asset chunk loading ----
  // Load order: shaders → background1 + materials → engine start
  // Shaders MUST be in MEMFS before callMain() — without them the engine aborts
  addRunDependency('load_game_data')

  // Load shaders chunk first (critical, non-optional)
  var loadShaders = (typeof dataLoader !== 'undefined' && dataLoader.loadMapCached)
    ? dataLoader.loadMapCached('shaders')
    : Promise.reject(new Error('dataLoader not available'))

  loadShaders.then(function() {
    console.log('[hl2] shaders.data loaded — ' +
      FS.readdir('/hl2/shaders').length + ' shader dirs in MEMFS')
    // Preflight: verify critical shader families exist
    var criticalShaders = [
      'vertexlit_and_unlit_generic_vs20',
      'vertexlit_and_unlit_generic_ps20b',
      'lightmappedgeneric_vs20',
      'lightmappedgeneric_ps20b',
    ]
    var missing = []
    try {
      var fxcDir = '/hl2/shaders/fxc'
      if (FS.analyzePath(fxcDir).exists) {
        var files = FS.readdir(fxcDir)
        for (var i = 0; i < criticalShaders.length; i++) {
          var found = false
          for (var j = 0; j < files.length; j++) {
            if (files[j].indexOf(criticalShaders[i]) >= 0) { found = true; break }
          }
          if (!found) missing.push(criticalShaders[i])
        }
      } else {
        console.warn('[hl2] /hl2/shaders/fxc not found — shaders may not be loaded')
      }
    } catch(e) { console.warn('[hl2] shader preflight error:', e) }
    if (missing.length > 0) {
      console.error('[hl2] MISSING SHADERS: ' + missing.join(', '))
      console.error('[hl2] Engine will crash on shader loading!')
    } else {
      console.log('[hl2] Shader preflight OK ✓')
    }

    // Now load background1 + materials in parallel
    return Promise.all([
      dataLoader.loadMap('background1'),
      dataLoader.loadMap('materials')
    ])
  }).then(function() {
    // Fix case-sensitive directory names (MEMFS is case-sensitive)
    var fixCase = function(dir, correctName) {
      try {
        var entries = FS.readdir(dir)
        for (var i = 0; i < entries.length; i++) {
          var e = entries[i]
          if (e.toLowerCase() === correctName && e !== correctName) {
            var src = dir + '/' + e
            var dst = dir + '/' + correctName
            if (!FS.analyzePath(dst).exists) {
              var stat = FS.stat(src)
              if (FS.isDir(stat.mode)) {
                FS.mkdir(dst)
                var subEntries = FS.readdir(src)
                for (var j = 0; j < subEntries.length; j++) {
                  if (subEntries[j] === '.' || subEntries[j] === '..') continue
                  FS.symlink(src + '/' + subEntries[j], dst + '/' + subEntries[j])
                }
              } else { FS.symlink(src, dst) }
              console.log('[hl2] Fixed case: ' + src + ' -> ' + dst)
            }
          }
        }
      } catch(e) { console.warn('[hl2] Case fix error: ' + e) }
    }
    fixCase('/hl2/materials', 'console')
    fixCase('/hl2/materials', 'debug')
    fixCase('/hl2/materials', 'dev')
    fixCase('/hl2/materials', 'engine')
    fixCase('/hl2/materials', 'effects')
    console.log('[hl2] All chunks loaded, starting engine...')
    removeRunDependency('load_game_data')
  }).catch(function(err) {
    console.error('[hl2] Chunk load error: ' + err + ' — starting with partial data')
    removeRunDependency('load_game_data')
  })
})();
POST_JS_EOF
    log "  patch: post.js shader+asset loading with preflight + /MOD/ IDBFS mount"
  fi


  # WebXR Phase 2: Patch gl_rmain.cpp — ComputeViewMatrix override
  local gl_rmain="$ENGINE_DIR/engine/gl_rmain.cpp"
  if [ -f "$gl_rmain" ]; then
    python3 "$REPO_ROOT/scripts/webxr_glmain_patch.py" "$gl_rmain" || true
    log "  patch: gl_rmain.cpp WebXR matrix override"
  fi

  checkpoint_mark "source_patches"
}

# ---------------------------------------------------------------------------
# 6. SDL2 Emscripten-Cache + Audio-Patch
# ---------------------------------------------------------------------------
build_sdl2() {
  checkpoint_done "sdl2_build" && { log "sdl2_build: skip"; return; }
  emsdk_env

  log "Building emscripten SDL2 cache..."
  embuilder --pic build sdl2 sdl2-mt

  # SDL_emscriptenaudio.c: EM_ASM_INT → MAIN_THREAD_EM_ASM_INT
  SDL_AUDIO=$(find "$EMSDK_DIR/upstream/emscripten/cache" \
                   -name "SDL_emscriptenaudio.c" 2>/dev/null | head -1 || true)
  if [ -n "${SDL_AUDIO:-}" ] && \
     grep -q "freq = EM_ASM_INT" "$SDL_AUDIO" 2>/dev/null; then
    sed -Ei 's/freq = EM_ASM_INT/freq = MAIN_THREAD_EM_ASM_INT/' "$SDL_AUDIO"
    embuilder --force --pic build sdl2 sdl2-mt
    log "  SDL2 audio patch applied: $SDL_AUDIO"
  else
    log "  SDL2 audio patch: not needed or already applied"
  fi

  checkpoint_mark "sdl2_build"
}

# ---------------------------------------------------------------------------
# 7. libwebgl.patch anwenden
# ---------------------------------------------------------------------------
patch_libwebgl() {
  checkpoint_done "libwebgl_patch" && { log "libwebgl_patch: skip"; return; }
  emsdk_env

  LIBWEBGL=$(find "$EMSDK_DIR/upstream/emscripten/src/lib" \
                  -name "libwebgl.js" 2>/dev/null | head -1 || true)
  if [ -z "${LIBWEBGL:-}" ]; then
    log "  libwebgl.js not found — skip patch"
    checkpoint_mark "libwebgl_patch"
    return
  fi

  PATCH_FILE="$ENGINE_DIR/emscripten/libwebgl.patch"
  if [ -f "$PATCH_FILE" ]; then
    patch --forward --reject-file=/dev/null "$LIBWEBGL" "$PATCH_FILE" \
      && log "  libwebgl.patch applied" \
      || log "  libwebgl.patch: already applied or hunk failed (continuing)"
  fi

  checkpoint_mark "libwebgl_patch"
}

# ---------------------------------------------------------------------------
# 8. waf configure
# ---------------------------------------------------------------------------
waf_configure() {
  checkpoint_done "waf_configure" && { log "waf_configure: skip"; return; }
  emsdk_env
  cd "$ENGINE_DIR"

  export CC=emcc
  export CXX=em++
  export PKG_CONFIG_PATH=/usr/lib/x86_64-linux-gnu/pkgconfig:/usr/share/pkgconfig

  log "Running: waf configure ($BUILDTYPE)..."
  python3 waf configure \
    -T "$BUILDTYPE" \
    --prefix=build/install \
    $WAF_CONFIGURE_FLAGS \
    2>&1 | tee "$LOG_DIR/waf_configure.log"

  checkpoint_mark "waf_configure"
}

# ---------------------------------------------------------------------------
# 9. waf build + install
# ---------------------------------------------------------------------------
waf_build() {
  checkpoint_done "waf_build" && { log "waf_build: skip"; return; }
  emsdk_env
  cd "$ENGINE_DIR"

  export CC=emcc
  export CXX=em++
  log "Running: waf install -j$JOBS ..."
  python3 waf install -j"$JOBS" \
    2>&1 | tee "$LOG_DIR/waf_build.log"

  local WAF_EXIT=$?
  [ "$WAF_EXIT" -eq 0 ] || die "waf install failed (exit $WAF_EXIT)"

  checkpoint_mark "waf_build"
}


# ---------------------------------------------------------------------------
# 9b. IVP_Mindist vtable stub — erzwingt vtable in main.wasm
# ---------------------------------------------------------------------------
# Hintergrund: Emscripten SIDE_MODULEs (libvphysics.so) importieren _ZTV11IVP_Mindist
# via GOT.mem. Das vtable-Symbol muss im MAIN_MODULE (main.wasm) definiert sein.
# Lösung: ivp_mindist_minimize.cxx wird ZUSÄTZLICH als main-module .o kompiliert
# und in den emcc-Link-Schritt eingebunden → vtable landet in main.wasm.
compile_ivp_vtable_stub() {
  checkpoint_done "ivp_vtable_stub" && { log "ivp_vtable_stub: skip"; return; }
  emsdk_env
  cd "$ENGINE_DIR"

  local main_src="ivp/ivp_collision/ivp_mindist.cxx"
  if [ ! -f "$main_src" ]; then
    log "WARNING: $main_src nicht gefunden — ivp_vtable_stub übersprungen"
    checkpoint_mark "ivp_vtable_stub"
    return
  fi
  log "Compiling IVP_Mindist files für main.wasm vtable..."

  # Kompiliere ALLE ivp_mindist*.cxx files in main.wasm
  # ivp_mindist.cxx enthält IVP_Mindist::recalc_mindist + recalc_invalid_mindist
  # ohne diese Methoden gibt es KEINE vtable in main.wasm
  mkdir -p build/ivp_vtable_stub

  # Include-Pfade identisch zu waf-Build für ivp-Targets
  IVP_INCS="-Iivp/ivp_physics -Iivp/ivp_collision -Iivp/ivp_utility -Iivp/ivp_intern -Iivp/ivp_surface_manager -Iivp/ivp_controller -Iivp/havana/havok -Iivp/havana"
  COMMON_INCS="-Ipublic -Ipublic/tier0 -Ipublic/tier1 -Itier1 -Icommon"
  IVP_FLAGS="-std=c++14 -O2 -DNDEBUG -D__EMSCRIPTEN__ -DPOSIX -DLINUX -D_LINUX -DTOGLES -DUSE_SDL -fPIC"

  ivp_objs=""
  # Kompiliere alle IVP_Mindist-relevanten Dateien
  for src_file in     ivp/ivp_collision/ivp_mindist.cxx     ivp/ivp_collision/ivp_mindist_minimize.cxx     ivp/ivp_collision/ivp_mindist_recursive.cxx     ivp/ivp_collision/ivp_mindist_event.cxx     ivp/ivp_intern/ivp_mindist_friction.cxx; do
    if [ ! -f "$src_file" ]; then
      log "  SKIP (nicht gefunden): $src_file"
      continue
    fi
    local obj="build/ivp_vtable_stub/$(basename ${src_file%.cxx}).o"
    log "  compiling: $src_file"
    em++ $IVP_FLAGS $IVP_INCS $COMMON_INCS -c "$src_file" -o "$obj"       2>>"$LOG_DIR/ivp_vtable_stub.log" && {
        log "    OK: $obj"
        ivp_objs="$ivp_objs $obj"
      } || log "    WARN: compile failed for $src_file"
  done

  if [ -z "$ivp_objs" ]; then
    log "WARNING: keine ivp_vtable objs erzeugt — _ZTV11IVP_Mindist fehlt!"
    checkpoint_mark "ivp_vtable_stub"
    return
  fi

  # Merge alle .o zu einem einzelnen .o via emcc partial link
  em++ -r $ivp_objs -o build/ivp_vtable_stub/ivp_mindist_vtable.o     2>>"$LOG_DIR/ivp_vtable_stub.log" &&     log "  ivp_mindist vtable stub merged OK: build/ivp_vtable_stub/ivp_mindist_vtable.o" || {
      # Fallback: erstes .o nutzen
      first_obj=$(echo $ivp_objs | awk '{print $1}')
      cp "$first_obj" build/ivp_vtable_stub/ivp_mindist_vtable.o
      log "  WARNING: merge failed, using first obj: $first_obj"
    }
  checkpoint_mark "ivp_vtable_stub"
}

# ---------------------------------------------------------------------------
# 10. emcc link (Haupt-WASM-Bundle)
# ---------------------------------------------------------------------------
emcc_link() {
  # Force re-link if webxr_bridge.cpp exists but was never compiled (e.g. checkpoint from older build)
  if [ -f "$REPO_ROOT/emscripten/webxr_bridge.cpp" ] && [ ! -f "$ENGINE_DIR/build/webxr_bridge.o" ]; then
    log "webxr_bridge.cpp present but not compiled — clearing emcc_link checkpoint"
    sed -i '/emcc_link/d' "$checkpoint_file" 2>/dev/null || true
  fi
  # Force re-link if webxr_hooks.cpp exists but was never compiled
  if [ -f "$REPO_ROOT/emscripten/webxr_hooks.cpp" ] && [ ! -f "$ENGINE_DIR/build/webxr_hooks.o" ]; then
    log "webxr_hooks.cpp present but not compiled — clearing emcc_link checkpoint"
    sed -i '/emcc_link/d' "$checkpoint_file" 2>/dev/null || true
  fi

  # Force re-link if EXPORTED_RUNTIME_METHODS doesn't match (cache bust)
  _erm_hash=$(grep "EXPORTED_RUNTIME_METHODS" "$REPO_ROOT/scripts/ci-build.sh" | md5sum | cut -c1-8)
  _erm_cache="$ENGINE_DIR/build/.erm_hash"
  if [ -f "$_erm_cache" ] && [ "$(cat "$_erm_cache")" != "$_erm_hash" ]; then
    log "EXPORTED_RUNTIME_METHODS changed — forcing emcc_link re-run"
    sed -i '/emcc_link/d' "$checkpoint_file" 2>/dev/null || true
  fi
  echo "$_erm_hash" > "$_erm_cache" 2>/dev/null || true

  checkpoint_done "emcc_link" && { log "emcc_link: skip"; return; }
  log "EXPORTED_RUNTIME_METHODS: $(grep "EXPORTED_RUNTIME_METHODS" "$REPO_ROOT/scripts/ci-build.sh" | head -1 | tr -s ' ')"
  emsdk_env
  cd "$ENGINE_DIR"

  log "Building .so map files..."
  find build/ -name '*.map' -exec cp {} build/install/ \; 2>/dev/null || true

  log "Collecting link libraries..."
  link_libs=""
  for lib in build/install/*.so; do
    libname=$(echo "$lib" | sed -E 's/^.+\/lib(.+)\.so/\1/g')
    link_libs="$link_libs -l$libname"
  done

  # Compile stubs (GetRam, futimes) — these are not part of waf build output
  log "Compiling emscripten_stubs.cpp..."
  local stubs_src="$ENGINE_DIR/emscripten/emscripten_stubs.cpp"
  local stubs_obj="$ENGINE_DIR/build/emscripten_stubs.o"

  # IVP vtable stub — sorgt dafür dass _ZTV11IVP_Mindist in main.wasm landet
  local ivp_vtable_obj="$ENGINE_DIR/build/ivp_vtable_stub/ivp_mindist_vtable.o"
  if [ ! -f "$ivp_vtable_obj" ]; then
    ivp_vtable_obj=""
    log "  WARNING: ivp_vtable_stub nicht vorhanden — _ZTV11IVP_Mindist fehlt in main.wasm!"
  else
    log "  ivp vtable stub gefunden: $ivp_vtable_obj"
  fi
  if [ -f "$stubs_src" ]; then
    emcc -O2 -fPIC -D__EMSCRIPTEN__ -c "$stubs_src" -o "$stubs_obj"
    log "  stubs compiled: $stubs_obj"
  else
    stubs_obj=""
    log "  stubs not found, skipping"
  fi

  # WebXR Bridge — EMSCRIPTEN_KEEPALIVE functions for VR rendering loop
  local webxr_bridge_src="$REPO_ROOT/emscripten/webxr_bridge.cpp"
  local webxr_bridge_obj="$ENGINE_DIR/build/webxr_bridge.o"
  if [ -f "$webxr_bridge_src" ]; then
    log "Compiling webxr_bridge.cpp..."
    emcc -O0 -fPIC -D__EMSCRIPTEN__ -c "$webxr_bridge_src" -o "$webxr_bridge_obj"
    log "  webxr_bridge compiled: $webxr_bridge_obj"
  else
    webxr_bridge_obj=""
    log "  webxr_bridge.cpp not found, skipping (Phase 2 bridge)"
  fi


  # WebXR Phase 2: Engine hooks (Engine_DisableAutoRender, RenderSingleFrame, SetCameraMatrix)
  local webxr_hooks_src="$REPO_ROOT/emscripten/webxr_hooks.cpp"
  local webxr_hooks_obj="$ENGINE_DIR/build/webxr_hooks.o"
  if [ -f "$webxr_hooks_src" ]; then
    log "Compiling webxr_hooks.cpp..."
    emcc -O0 -fPIC -D__EMSCRIPTEN__ -c "$webxr_hooks_src" -o "$webxr_hooks_obj"
    log "  webxr_hooks compiled: $webxr_hooks_obj"
  else
    webxr_hooks_obj=""
    log "  webxr_hooks.cpp not found, skipping (Phase 2 engine hooks)"
  fi

  log "Running: emcc link → hl2_launcher.html ..."
  emcc \
    -sUSE_BZIP2=1 -sUSE_SDL=2 -sUSE_FREETYPE=1 -sUSE_LIBJPEG=1 \
    -sUSE_LIBPNG -sMALLOC=mimalloc \
    -sMAIN_MODULE \
    -sINITIAL_MEMORY=1024mb \
    -sALLOW_MEMORY_GROWTH=1 \
    -sMAXIMUM_MEMORY=4gb \
    -sSHARED_MEMORY=1 -sUSE_PTHREADS -sPTHREAD_POOL_SIZE=8 \
    -sPTHREAD_POOL_SIZE_STRICT=2 \
    -sFULL_ES3 -sSTACK_SIZE=64mb \
    --shell-file=emscripten/shell.html \
    -sPROXY_TO_PTHREAD \
    -sOFFSCREENCANVASES_TO_PTHREAD="#canvas" \
    -sOFFSCREENCANVAS_SUPPORT=1 \
    "-sEXPORTED_RUNTIME_METHODS=['wasmMemory','addRunDependency','removeRunDependency','FS','callMain','abort','HEAPU8','ccall','cwrap','wasmExports','getValue','setValue','HEAPF32','HEAPU32','lengthBytesUTF8','stringToUTF8','UTF8ToString']" \
    --pre-js emscripten/pre.js \
    --post-js emscripten/post.js \
    -sERROR_ON_UNDEFINED_SYMBOLS=0 \
    -L build/install/ \
    build/launcher_main/libhl2_launcher.a \
    ${stubs_obj:+"$stubs_obj"} \
    ${ivp_vtable_obj:+"$ivp_vtable_obj"} \
    ${webxr_bridge_obj:+"$webxr_bridge_obj"} \
    ${webxr_hooks_obj:+"$webxr_hooks_obj"} \
    $link_libs \
    -o build/launcher_main/hl2_launcher.html \
    2>&1 | tee "$LOG_DIR/emcc_link.log"

  cp build/launcher_main/hl2_launcher.{html,js,wasm} build/install/

  # GL stubs + dlsym/dlopen intercept + GL version spoof
  python3 "$REPO_ROOT/scripts/gl_stubs_patch.py" build/launcher_main/hl2_launcher.js || true
  python3 "$REPO_ROOT/scripts/gl_stubs_patch.py" build/install/hl2_launcher.js || true
  cp -r emscripten/assets build/install/ 2>/dev/null || true

  # Verify EXPORTED_RUNTIME_METHODS were applied
  if grep -q "ccall" "$ENGINE_DIR/build/install_hl2/hl2_launcher.js" 2>/dev/null; then
    if grep -q "unexportedSymbols.*ccall" "$ENGINE_DIR/build/install_hl2/hl2_launcher.js" 2>/dev/null; then
      log "WARNING: ccall still in unexportedSymbols — EXPORTED_RUNTIME_METHODS may not have been applied!"
    else
      log "OK: ccall exported on Module"
    fi
  fi
  checkpoint_mark "emcc_link"
}

# ---------------------------------------------------------------------------
# 11. Asset-Repackaging
# ---------------------------------------------------------------------------
repackage_assets() {
  checkpoint_done "repackage" && { log "repackage: skip"; return; }
  cd "$ENGINE_DIR"

  log "Copying assets from: $ASSETS_ROOT"
  if [ ! -d "$ASSETS_ROOT/hl2" ]; then
    log "WARNING: ASSETS_ROOT/hl2 not found — skipping asset copy and repackage."
    log "  Set ASSETS_ARCHIVE_URL secret to enable full asset packaging."
    checkpoint_mark "repackage"
    return
  fi

  mkdir -p build/install/hl2
  cp -r "$ASSETS_ROOT/hl2/." build/install/hl2/
  if [ -d "$ASSETS_ROOT/platform" ]; then
    mkdir -p build/install/platform
    cp -r "$ASSETS_ROOT/platform/." build/install/platform/

  # Create missing bootstrap VTFs (not in Retail 2153)
  python3 "$REPO_ROOT/scripts/create_dummy_vtfs.py" build/install/hl2/materials
  log "Bootstrap VTFs ensured"
  fi

  # repackage.js braucht map-*.txt Asset-Trace-Logs (via get_logs.sh + echte HL2-Installation)
  # Im CI erzeugen wir stattdessen einen Basis-Chunk mit Startup-Assets (background1)
  log "Generating startup asset chunk (CI mode, no map trace logs) ..."
  mkdir -p "$ENGINE_DIR/chunks"

  node - << 'NODEJS'
const fs = require('fs')
const path = require('path')

const baseGamePath = process.env.ASSETS_ROOT || ''
const outDir = './chunks'
fs.mkdirSync(outDir, {recursive: true})

// Track all shader files for manifest generation
let shaderManifest = []

function addFile(chunks, src, vpath, trackShader = false) {
  let blob
  try { blob = fs.readFileSync(src) } catch { return 0 }
  const dst = Buffer.from(vpath)
  const hdr = Buffer.alloc(8)
  hdr.writeUint32LE(dst.length, 0)
  hdr.writeUint32LE(blob.length, 4)
  chunks.push(hdr, dst, blob)
  if (trackShader) {
    shaderManifest.push({ path: vpath, bytes: blob.length })
  }
  return blob.length
}

function walk(chunks, dir, vBase, srcRel, trackShader = false) {
  let entries
  try { entries = fs.readdirSync(dir, {withFileTypes: true}) } catch { return 0 }
  let total = 0
  for (const e of entries) {
    const full = path.join(dir, e.name)
    const rel  = srcRel ? srcRel + '/' + e.name : e.name
    if (e.isDirectory()) total += walk(chunks, full, vBase, rel, trackShader)
    else total += addFile(chunks, full, vBase + '/' + rel, trackShader)
  }
  return total
}

// Add individual files (for bootstrap VTFs that may be in subdirectories)
function addFileFromTree(chunks, srcDir, vpath, filename) {
  // Search recursively for filename in srcDir
  function findFile(dir, name) {
    let entries
    try { entries = fs.readdirSync(dir, {withFileTypes: true}) } catch { return null }
    for (const e of entries) {
      const full = path.join(dir, e.name)
      if (e.isDirectory()) {
        const found = findFile(full, name)
        if (found) return found
      } else if (e.name.toLowerCase() === name.toLowerCase()) {
        return full
      }
    }
    return null
  }
  // Try original assets dir first
  let found = findFile(srcDir, filename)
  // Fallback: search in build/install (where dummy VTFs are created)
  if (!found) {
    const buildDir = path.join(process.cwd(), 'build/install/hl2/materials')
    found = findFile(buildDir, filename)
    if (found) console.log(`  Found in build/install: ${found}`)
  }
  if (found) {
    console.log(`  Found bootstrap file: ${found} -> ${vpath}`)
    return addFile(chunks, found, vpath, true)
  }
  console.log(`  WARNING: bootstrap file not found: ${filename}`)
  return 0
}

function writeChunk(name, dirPairs, trackShader = false) {
  const chunks = []
  let totalBytes = 0, fileCount = 0
  for (const [srcDir, vBase] of dirPairs) {
    if (fs.existsSync(srcDir)) {
      const before = chunks.length
      const bytes = walk(chunks, srcDir, vBase, path.basename(srcDir), trackShader)
      totalBytes += bytes
      const added = (chunks.length - before) / 3
      fileCount += added
      console.log(`  ${srcDir}: ${Math.round(bytes/1024/1024)}MB, ${added} files`)
    } else {
      console.log(`  SKIP (not found): ${srcDir}`)
    }
  }
  const out = path.join(outDir, name)
  const buf = Buffer.concat(chunks)
  fs.writeFileSync(out, buf)
  console.log(`-> ${name}: ${Math.round(buf.length/1024/1024)}MB, ${fileCount} files`)
  return buf.length
}

console.log('=== Chunk 0: shaders.data (Pre-compiled Shader Cache) ===')
// Shader cache files from HL2 Retail 2153 — pre-compiled by Valve
// These are .vsh/.psh files in hl2/shaders/fxc/
// The engine REQUIRES these before callMain() — without them, shader loading aborts
writeChunk('shaders.data', [
  [baseGamePath + '/hl2/shaders', '/hl2'],
], true)  // trackShader = true for manifest

// Verify critical shader files exist
const criticalShaders = [
  'vertexlit_and_unlit_generic_vs20',
  'vertexlit_and_unlit_generic_ps20',
  'vertexlit_and_unlit_generic_ps20b',
  'unlitgeneric_vs20',
  'unlitgeneric_ps20',
  'lightmappedgeneric_vs20',
  'lightmappedgeneric_ps20',
  'lightmappedgeneric_ps20b',
]
const shaderPaths = shaderManifest.map(f => f.path.toLowerCase())
let missingShaders = []
for (const s of criticalShaders) {
  const found = shaderPaths.some(p => p.includes(s.toLowerCase()))
  if (!found) missingShaders.push(s)
  else console.log(`  ✓ ${s}`)
}
if (missingShaders.length > 0) {
  console.log(`  WARNING: ${missingShaders.length} critical shaders not found:`)
  missingShaders.forEach(s => console.log(`    - ${s}`))
  console.log('  Engine will crash on shader loading!')
} else {
  console.log('  All critical shader families found ✓')
}

// Write shader manifest for preflight validation
fs.writeFileSync(
  path.join(outDir, 'shader-manifest.json'),
  JSON.stringify({
    format: 1,
    branch: 'source-build-2153',
    shader_count: shaderManifest.length,
    files: shaderManifest,
  }, null, 2)
)
console.log(`  Manifest: ${shaderManifest.length} shader files`)

console.log('\n=== Chunk 1: background1.data (Maps + Config + Bootstrap VTFs) ===')
const bgChunks = []
// Maps + config + resource
const bgDirs = [
  [baseGamePath + '/hl2/cfg',           '/hl2'],
  [baseGamePath + '/hl2/resource',      '/hl2'],
  [baseGamePath + '/platform/resource', '/platform'],
  [baseGamePath + '/hl2/maps',          '/hl2'],
]
for (const [srcDir, vBase] of bgDirs) {
  if (fs.existsSync(srcDir)) {
    const bytes = walk(bgChunks, srcDir, vBase, path.basename(srcDir))
    console.log(`  ${srcDir}: ${Math.round(bytes/1024/1024)}MB`)
  } else {
    console.log(`  SKIP: ${srcDir}`)
  }
}
// Bootstrap VTFs — critical for engine init, must be in background1 chunk
console.log('  Adding bootstrap VTFs...')
addFileFromTree(bgChunks, baseGamePath + '/hl2/materials', '/hl2/materials/dev/identitylightwarp.vtf', 'identitylightwarp.vtf')
addFileFromTree(bgChunks, baseGamePath + '/hl2/materials', '/hl2/materials/engine/normalizedrandomdirections2d.vtf', 'normalizedrandomdirections2d.vtf')
addFileFromTree(bgChunks, baseGamePath + '/hl2/materials', '/hl2/materials/effects/flashlight_border.vtf', 'flashlight_border.vtf')
addFileFromTree(bgChunks, baseGamePath + '/hl2/materials', '/hl2/materials/debug/debugluxelsnoalpha.vtf', 'debugluxelsnoalpha.vtf')

// Write background1 chunk
const bgBuf = Buffer.concat(bgChunks)
fs.writeFileSync(path.join(outDir, 'background1.data'), bgBuf)
console.log(`-> background1.data: ${Math.round(bgBuf.length/1024/1024)}MB`)

console.log('\n=== Chunk 2: materials.data (Texturen) ===')
writeChunk('materials.data', [
  [baseGamePath + '/hl2/materials',     '/hl2'],
])

console.log('\n=== Chunk 3: models.data (Models + Sound) ===')
writeChunk('models.data', [
  [baseGamePath + '/hl2/models',        '/hl2'],
  [baseGamePath + '/hl2/sound',         '/hl2'],
])

console.log('\nAll chunks written!')
NODEJS
  if [ $? -eq 0 ]; then
    log "  startup chunk OK: $(ls -lh $ENGINE_DIR/chunks/*.data 2>/dev/null | awk '{print $5, $9}')"
  else
    log "WARNING: chunk generation failed — continuing without asset chunks"
  fi

  checkpoint_mark "repackage"

# ---------------------------------------------------------------------------


}

# ---------------------------------------------------------------------------
# 12. Outputs sammeln
# ---------------------------------------------------------------------------
collect_outputs() {
  log "Collecting outputs → $OUT_DIR ..."
  mkdir -p "$OUT_DIR/web" "$OUT_DIR/chunks" "$OUT_DIR/logs"

  # Web-Outputs: html/js/wasm + Side-Module .so
  cp "$ENGINE_DIR/build/install/hl2_launcher.html" "$OUT_DIR/web/" 2>/dev/null || true
  cp "$ENGINE_DIR/build/install/hl2_launcher.js"   "$OUT_DIR/web/" 2>/dev/null || true
  cp "$ENGINE_DIR/build/install/hl2_launcher.wasm" "$OUT_DIR/web/" 2>/dev/null || true
  find "$ENGINE_DIR/build/install/" -name '*.so' -exec cp {} "$OUT_DIR/web/" \; 2>/dev/null || true
  cp -r "$ENGINE_DIR/build/install/assets"          "$OUT_DIR/web/" 2>/dev/null || true

  # Data-Chunks (only if present)
  find "$ENGINE_DIR/chunks/" -name '*.data' -exec cp {} "$OUT_DIR/chunks/" \; 2>/dev/null || true
  # Shader manifest
  cp "$ENGINE_DIR/chunks/shader-manifest.json" "$OUT_DIR/chunks/" 2>/dev/null || true

  # Logs
  find "$LOG_DIR/" -name '*.log' -exec cp {} "$OUT_DIR/logs/" \; 2>/dev/null || true

  log "Output summary:"
  ls -lh "$OUT_DIR/web/" 2>/dev/null || true
  echo "---"
  ls -lh "$OUT_DIR/chunks/" 2>/dev/null | grep -v "^total" | head -10
}

# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------
write_build_manifest() {
  log "Writing build-manifest.json..."

  local web_dir="$OUT_DIR/web"
  mkdir -p "$web_dir"

  local git_sha
  git_sha=$(git -C "$ENGINE_DIR" rev-parse --short HEAD 2>/dev/null || echo "unknown")

  local wasm_size js_size html_size
  wasm_size=$(stat -c%s "$web_dir/hl2_launcher.wasm" 2>/dev/null || echo 0)
  js_size=$(stat -c%s "$web_dir/hl2_launcher.js" 2>/dev/null || echo 0)
  html_size=$(stat -c%s "$web_dir/hl2_launcher.html" 2>/dev/null || echo 0)

  local so_count
  so_count=$(find "$web_dir" -maxdepth 1 -type f -name '*.so' | wc -l)

  local wasm_hash
  wasm_hash=$(sha256sum "$web_dir/hl2_launcher.wasm" 2>/dev/null | cut -d' ' -f1 || echo "")

  cat > "$web_dir/build-manifest.json" << MANIFEST_EOF
{
  "git_sha": "$git_sha",
  "emsdk": "3.1.72",
  "build_type": "$BUILDTYPE",
  "main_module": "hl2_launcher.wasm",
  "main_module_size": $wasm_size,
  "main_module_sha256": "$wasm_hash",
  "js_size": $js_size,
  "html_size": $html_size,
  "side_module_count": $so_count,
  "asset_base_url": "https://hl2-assets-proxy.hl2-webxr.workers.dev/chunks/",
  "build_mode": "phase1-debug"
}
MANIFEST_EOF

  log "  manifest: sha=$git_sha, wasm=${wasm_size}B, so=$so_count"
}

# ---------------------------------------------------------------------------
# Main execution
# ---------------------------------------------------------------------------
main() {
  mkdir -p "$LOG_DIR" "$OUT_DIR"
  log "=== HL2 WebXR CI Build — $(date) ==="
  log "BUILDTYPE: $BUILDTYPE"
  log "ENGINE_DIR: $ENGINE_DIR"
  log "EMSDK_DIR: $EMSDK_DIR"
  log "ASSETS_ROOT: $ASSETS_ROOT"
  log "JOBS: $JOBS"
  echo ""

  install_apt_deps
  install_emsdk
  clone_engine
  apply_source_patches
  build_sdl2
  patch_libwebgl
  waf_configure
  waf_build
  compile_ivp_vtable_stub
  emcc_link
  repackage_assets
  collect_outputs

# R2 Upload: Upload chunks to Cloudflare R2
if [ -n "${R2_ACCESS_KEY_ID:-}" ] && [ -n "${R2_SECRET_ACCESS_KEY:-}" ] && [ -d "${OUT_DIR}/chunks" ]; then
  log "Uploading chunks to Cloudflare R2..."
  pip3 install -q boto3 2>/dev/null || true
  R2_ENDPOINT="https://bdeeeb229289da950d71472c4c4bab76.r2.cloudflarestorage.com"
  for f in "${OUT_DIR}"/chunks/*.data "${OUT_DIR}"/chunks/*.json; do
    [ -f "$f" ] || continue
    fname=$(basename "$f")
    size_mb=$(du -m "$f" | cut -f1)
    log "  Uploading $fname (${size_mb}MB)..."
    python3 -c "
import sys, os, boto3
from botocore.config import Config
s3 = boto3.client('s3',
    endpoint_url='$R2_ENDPOINT',
    aws_access_key_id=os.environ['R2_ACCESS_KEY_ID'],
    aws_secret_access_key=os.environ['R2_SECRET_ACCESS_KEY'],
    config=Config(signature_version='s3v4'),
    region_name='auto'
)
s3.upload_file(sys.argv[1], 'hl2-webxr-assets', 'chunks/' + os.path.basename(sys.argv[1]),
    ExtraArgs={'ContentType': 'application/octet-stream'})
print('OK')
" "$f" || log "  FAILED: $fname"
  done
  log "R2 upload complete"
else
  log "R2 credentials not set or no chunks dir — skipping R2 upload"
fi

  write_build_manifest
  log ""
  log "=== BUILD COMPLETE — $(date) ==="
  log "Outputs: $OUT_DIR"
}

main "$@"



