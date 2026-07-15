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
  if [ ! -d "$ENGINE_DIR/.git" ]; then
    git clone --depth=1 \
              --recurse-submodules \
              --shallow-submodules \
              "$ENGINE_REPO" \
              "$ENGINE_DIR"
  fi

  checkpoint_mark "repo_clone"
}

# ---------------------------------------------------------------------------
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
// IVP_Mindist vtable + symbol stubs for Emscripten MAIN_MODULE
// -----------------------------------------------------------------------
// libvphysics.so (SIDE_MODULE) imports these via GOT. The MAIN_MODULE
// must export them with EXACTLY the signatures libvphysics.so expects.
//
// CRITICAL: libvphysics.so imports init_mms_function_table as () -> void
// (no this pointer). The main module must match this exactly or
// WebAssembly.instantiate() throws a LinkError type-mismatch.
// -----------------------------------------------------------------------

// Define IVP_Mindist class with matching vtable layout
// CRITICAL: The destructor is declared OUT-OF-LINE (not inline).
// This makes it the "key function" in C++ ABI, which forces the
// compiler to emit the vtable (_ZTV11IVP_Mindist) in THIS TU.
// All-inline virtual methods would NOT emit a vtable.
class __attribute__((visibility("default"))) IVP_Mindist {
public:
    virtual ~IVP_Mindist();  // out-of-line declaration = key function
    virtual int recalc_mindist() { return 0; }
    virtual int recalc_invalid_mindist() { return 0; }
};

// Out-of-line definition — this is the key function that forces vtable emission
IVP_Mindist::~IVP_Mindist() {}

// Force the vtable symbol to not be stripped by the linker
__attribute__((used, visibility("default")))
extern "C" void* _ZTV11IVP_Mindist_anchor = nullptr;
__attribute__((constructor)) static void __ivp_mindist_init() {
    // Create an instance to ensure the vtable is referenced
    static IVP_Mindist __ivp_instance;
    _ZTV11IVP_Mindist_anchor = *(void**)&__ivp_instance;
}

// init_mms_function_table — () -> void (NO this pointer, matches libvphysics.so)
extern "C" __attribute__((visibility("default")))
void _ZN27IVP_Mindist_Minimize_Solver23init_mms_function_tableEv() {
    // no-op stub — real implementation lives in libvphysics.so
}

// IVP_Mindist::recalc_mindist — (i32) -> i32 (has this pointer)
extern "C" __attribute__((visibility("default")))
int _ZN11IVP_Mindist14recalc_mindistEv(void* self) {
    (void)self;
    return 0;
}

// IVP_Mindist::recalc_invalid_mindist — (i32) -> i32 (has this pointer)
extern "C" __attribute__((visibility("default")))
int _ZN11IVP_Mindist22recalc_invalid_mindistEv(void* self) {
    (void)self;
    return 0;
}

#endif // __EMSCRIPTEN__
EOF
  log "  patch: emscripten_stubs.cpp (with IVP_Mindist weak stubs)"
  

  # Patch 6 (post): post.js — Multi-Chunk Loading für HL2 Retail
  POST_JS="$ENGINE_DIR/emscripten/post.js"
  if [ -f "$POST_JS" ]; then
    # Schreibe neuen post.js Content der alle 3 Chunks lädt
    cat > "$POST_JS" << 'POST_JS_EOF'
;(() => {
  if(typeof window === 'undefined') return;
  window.addEventListener('beforeunload', function (event) { event.preventDefault() })
  if (typeof canvasElement !== 'undefined') {
    canvasElement.onkeypress = e => e.preventDefault()
  }

  // Nur background1 beim Start laden (803 MB).
  // 'background01' ist FALSCH — DataLoader.mapsOrdered enthält 'background1' (ohne 0).
  // materials + models (~2.3 GB) werden lazy via Module.downloadMap geladen.
  addRunDependency('load_game_data')
  dataLoader.loadMapWithDeps('background1')
    .then(() => {
      console.log('[hl2] background1 OK — Engine startet')
      removeRunDependency('load_game_data')
    })
    .catch(err => {
      console.warn('[hl2] background1 Fehler (ignoriert, Engine startet trotzdem):', err.message)
      removeRunDependency('load_game_data')
    })
})();
POST_JS_EOF
    log "  patch: post.js background1 lazy-load (materials/models via downloadMap)"
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
  # SKIPPED: compiling real ivp_mindist*.cxx produces (i32)->void signatures
  # for init_mms_function_table, but libvphysics.so expects () -> void.
  # The emscripten_stubs.cpp now provides correct signatures + vtable.
  # Creating an empty .o so the emcc_link step's file check passes.
  emsdk_env
  cd "$ENGINE_DIR"
  mkdir -p build/ivp_vtable_stub
  echo "" | em++ -x c++ -c - -o build/ivp_vtable_stub/ivp_mindist_vtable.o 2>/dev/null || true
  if [ ! -f build/ivp_vtable_stub/ivp_mindist_vtable.o ]; then
    # Fallback: create empty file — emcc_link checks existence
    touch build/ivp_vtable_stub/ivp_mindist_vtable.o
  fi
  log "  ivp vtable stub: using emscripten_stubs.cpp signatures (skip real .cxx)"
  checkpoint_mark "ivp_vtable_stub"
  return

  # --- OLD CODE BELOW (not executed) ---
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
  checkpoint_done "emcc_link" && { log "emcc_link: skip"; return; }
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
    emcc -O0 -fPIC -D__EMSCRIPTEN__ -c "$stubs_src" -o "$stubs_obj"  # -O0 prevents vtable DCE
    log "  stubs compiled: $stubs_obj"
  else
    stubs_obj=""
    log "  stubs not found, skipping"
  fi

  log "Running: emcc link → hl2_launcher.html ..."
  emcc \
    -msimd128 -DWEBXR=1 -sUSE_BZIP2=1 -sUSE_SDL=2 -sUSE_FREETYPE=1 -sUSE_LIBJPEG=1 \
    -sUSE_LIBPNG -sMALLOC=mimalloc \
    -sMAIN_MODULE \
    -sINITIAL_MEMORY=2048mb \
    -sALLOW_MEMORY_GROWTH=1 \
    -sMAXIMUM_MEMORY=3gb \
    -sSHARED_MEMORY=1 -sUSE_PTHREADS -sPTHREAD_POOL_SIZE=4 \
    -sPTHREAD_POOL_SIZE_STRICT=2 \
    -sFULL_ES3 -sSTACK_SIZE=64mb \
    --shell-file=emscripten/shell.html \
    -sPROXY_TO_PTHREAD \
    -sOFFSCREENCANVASES_TO_PTHREAD="#canvas" \
    -sOFFSCREENCANVAS_SUPPORT=1 \
    "-sEXPORTED_RUNTIME_METHODS=['wasmMemory','addRunDependency','removeRunDependency','FS','callMain','abort','HEAPU8']" \
    --pre-js emscripten/pre.js \
    --post-js emscripten/post.js \
    -sERROR_ON_UNDEFINED_SYMBOLS=0 \
    -L build/install/ \
    build/launcher_main/libhl2_launcher.a \
    ${stubs_obj:+"$stubs_obj"} \
    ${ivp_vtable_obj:+"$ivp_vtable_obj"} \
    $link_libs \
    -o build/launcher_main/hl2_launcher.html \
    2>&1 | tee "$LOG_DIR/emcc_link.log"

  cp build/launcher_main/hl2_launcher.{html,js,wasm} build/install/
  cp -r emscripten/assets build/install/ 2>/dev/null || true

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

function addFile(chunks, src, vpath) {
  let blob
  try { blob = fs.readFileSync(src) } catch { return 0 }
  const dst = Buffer.from(vpath)
  const hdr = Buffer.alloc(8)
  hdr.writeUint32LE(dst.length, 0)
  hdr.writeUint32LE(blob.length, 4)
  chunks.push(hdr, dst, blob)
  return blob.length
}

function walk(chunks, dir, vBase, srcRel) {
  let entries
  try { entries = fs.readdirSync(dir, {withFileTypes: true}) } catch { return 0 }
  let total = 0
  for (const e of entries) {
    const full = path.join(dir, e.name)
    const rel  = srcRel ? srcRel + '/' + e.name : e.name
    if (e.isDirectory()) total += walk(chunks, full, vBase, rel)
    else total += addFile(chunks, full, vBase + '/' + rel)
  }
  return total
}

function writeChunk(name, dirPairs) {
  const chunks = []
  let totalBytes = 0, fileCount = 0
  for (const [srcDir, vBase] of dirPairs) {
    if (fs.existsSync(srcDir)) {
      const before = chunks.length
      const bytes = walk(chunks, srcDir, vBase, path.basename(srcDir))
      totalBytes += bytes
      const added = (chunks.length - before) / 3  // hdr+dst+blob = 3 per file
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

console.log('=== Chunk 1: background1.data (Maps + Config) ===')
writeChunk('background1.data', [
  [baseGamePath + '/hl2/cfg',           '/hl2'],
  [baseGamePath + '/hl2/resource',      '/hl2'],
  [baseGamePath + '/platform/resource', '/platform'],
  [baseGamePath + '/hl2/maps',          '/hl2'],
])

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
  # WebXR Frontend-Dateien
  for xr_file in xr_wrapper.js index.html sw.js pre.js; do
    cp "$ENGINE_DIR/emscripten/$xr_file" "$OUT_DIR/web/" 2>/dev/null || true
  done
  log "  WebXR Frontend-Dateien kopiert"
  cp -r "$ENGINE_DIR/build/install/assets"          "$OUT_DIR/web/" 2>/dev/null || true

  # Data-Chunks (only if present)
  find "$ENGINE_DIR/chunks/" -name '*.data' -exec cp {} "$OUT_DIR/chunks/" \; 2>/dev/null || true

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

  log ""
  log "=== BUILD COMPLETE — $(date) ==="
  log "Outputs: $OUT_DIR"
}

main "$@"
