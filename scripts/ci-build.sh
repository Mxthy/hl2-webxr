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

  # 5c: ivp_mindist_minimize EMSCRIPTEN guard
  p="$ENGINE_DIR/ivp/ivp_collision/ivp_mindist_minimize.cxx"
  if ! head -1 "$p" | grep -q "__EMSCRIPTEN__"; then
    {
      echo "#ifndef __EMSCRIPTEN__"
      cat "$p"
      echo ""
      echo "#endif /* __EMSCRIPTEN__ */"
    } > "${p}.tmp" && mv "${p}.tmp" "$p"
    log "  patch: ivp_mindist_minimize guard"
  fi

  # 5d: emscripten_stubs.cpp
  p="$ENGINE_DIR/emscripten/emscripten_stubs.cpp"
  if [ ! -f "$p" ]; then
    cat > "$p" << 'EOF'
#ifdef __EMSCRIPTEN__
unsigned long GetRam() { return 2047UL; }
#include <sys/time.h>
int futimes(int fd, const struct timeval tv[2]) { return 0; }
#endif
EOF
    log "  patch: emscripten_stubs.cpp"
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
  if [ -f "$stubs_src" ]; then
    emcc -O2 -fPIC -D__EMSCRIPTEN__ -c "$stubs_src" -o "$stubs_obj"
    log "  stubs compiled: $stubs_obj"
  else
    stubs_obj=""
    log "  stubs not found, skipping"
  fi

  log "Running: emcc link → hl2_launcher.html ..."
  emcc \
    -sUSE_BZIP2=1 -sUSE_SDL=2 -sUSE_FREETYPE=1 -sUSE_LIBJPEG=1 \
    -sUSE_LIBPNG -sMALLOC=mimalloc \
    -sMAIN_MODULE \
    -sINITIAL_MEMORY=2047mb \
    -sSHARED_MEMORY=1 -sUSE_PTHREADS -sPTHREAD_POOL_SIZE=8 \
    -sPTHREAD_POOL_SIZE_STRICT=2 \
    -sFULL_ES3 -sSTACK_SIZE=4mb \
    --shell-file=emscripten/shell.html \
    -sPROXY_TO_PTHREAD \
    -sOFFSCREENCANVASES_TO_PTHREAD="#canvas" \
    -sOFFSCREENCANVAS_SUPPORT=1 \
    --pre-js emscripten/pre.js \
    --post-js emscripten/post.js \
    -sERROR_ON_UNDEFINED_SYMBOLS=0 \
    -L build/install/ \
    build/launcher_main/libhl2_launcher.a \
    ${stubs_obj:+"$stubs_obj"} \
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

  log "Running repackage.js ..."
  node emscripten/repackage.js \
    2>&1 | tee "$LOG_DIR/repackage.log"

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
  emcc_link
  repackage_assets
  collect_outputs

  log ""
  log "=== BUILD COMPLETE — $(date) ==="
  log "Outputs: $OUT_DIR"
}

main "$@"
