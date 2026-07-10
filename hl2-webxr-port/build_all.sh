#!/bin/bash
# HL2 WebXR Full Build Script — Vesper Build System
# Checkpointed — safe to re-run after timeout
# Usage: bash build_all.sh [--from STEP]
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG="$SCRIPT_DIR/build_all.log"
CHECKPOINT="$SCRIPT_DIR/.build_checkpoint"
EMSDK_DIR="$SCRIPT_DIR/tools/emsdk"
REPO_DIR="$SCRIPT_DIR/engine/portal-port"
ASSETS_HL2="$SCRIPT_DIR/assets/game/Half-Life 2"

step_done() { echo "$1" >> "$CHECKPOINT"; echo "[CHECKPOINT] $1 done at $(date)" | tee -a "$LOG"; }
step_skip() { echo "[SKIP] $1 already done" | tee -a "$LOG"; }
need_step() { ! grep -qx "$1" "$CHECKPOINT" 2>/dev/null; }

echo "=== HL2 WebXR Build $(date) ===" | tee -a "$LOG"
touch "$CHECKPOINT"

# ── STEP 1: Install system deps ──────────────────────────────────────────────
if need_step "apt_deps"; then
  echo "[STEP 1] apt deps" | tee -a "$LOG"
  apt-get install -y --no-install-recommends \
    git curl wget python3 xz-utils llvm binutils \
    gcc g++ gcc-multilib g++-multilib \
    libsdl2-dev:i386 libfontconfig-dev:i386 \
    pkg-config cmake ninja-build \
    xvfb libgl1-mesa-dev 2>&1 | tail -5 | tee -a "$LOG"
  step_done "apt_deps"
else step_skip "apt_deps"; fi

# ── STEP 2: Clone emsdk ──────────────────────────────────────────────────────
if need_step "emsdk_clone"; then
  echo "[STEP 2] emsdk clone" | tee -a "$LOG"
  mkdir -p "$EMSDK_DIR"
  git clone https://github.com/emscripten-core/emsdk.git "$EMSDK_DIR" 2>&1 | tee -a "$LOG"
  cd "$EMSDK_DIR"
  git checkout 2d480a1b7c7a34a354188d93f3e89190a44a1d21 2>&1 | tee -a "$LOG"
  step_done "emsdk_clone"
else step_skip "emsdk_clone"; fi

# ── STEP 3: Install + activate emsdk ─────────────────────────────────────────
if need_step "emsdk_install"; then
  echo "[STEP 3] emsdk install+activate" | tee -a "$LOG"
  cd "$EMSDK_DIR"
  ./emsdk install latest 2>&1 | tee -a "$LOG"
  ./emsdk activate latest 2>&1 | tee -a "$LOG"
  step_done "emsdk_install"
else step_skip "emsdk_install"; fi

source "$EMSDK_DIR/emsdk_env.sh" 2>/dev/null
export PATH="$EMSDK_DIR/upstream/emscripten:$EMSDK_DIR/upstream/bin:$PATH"

# ── STEP 4: SDL2 build + audio patch ─────────────────────────────────────────
if need_step "sdl2_build"; then
  echo "[STEP 4] embuilder sdl2" | tee -a "$LOG"
  embuilder --pic build sdl2 sdl2-mt 2>&1 | tee -a "$LOG"
  SDL_AUDIO=$(find "$EMSDK_DIR/upstream/emscripten/cache" -name "SDL_emscriptenaudio.c" 2>/dev/null | head -1)
  if [ -n "$SDL_AUDIO" ]; then
    sed -Ei 's/freq = EM_ASM_INT/freq = MAIN_THREAD_EM_ASM_INT/' "$SDL_AUDIO"
    echo "[STEP 4] SDL2 audio patch OK: $SDL_AUDIO" | tee -a "$LOG"
    embuilder --force --pic build sdl2 sdl2-mt 2>&1 | tail -3 | tee -a "$LOG"
  else
    echo "[WARN] SDL_emscriptenaudio.c not found after build" | tee -a "$LOG"
  fi
  step_done "sdl2_build"
else step_skip "sdl2_build"; fi

# ── STEP 5: libwebgl.patch ───────────────────────────────────────────────────
if need_step "libwebgl_patch"; then
  echo "[STEP 5] libwebgl.patch" | tee -a "$LOG"
  LIBWEBGL="$EMSDK_DIR/upstream/emscripten/src/lib/libwebgl.js"
  if grep -q "MAP_UNSYNCHRONIZED" "$LIBWEBGL" 2>/dev/null; then
    patch -p0 "$LIBWEBGL" "$REPO_DIR/emscripten/libwebgl.patch" 2>&1 | tee -a "$LOG" && \
      echo "[STEP 5] libwebgl patch applied" | tee -a "$LOG"
  else
    echo "[STEP 5] libwebgl already patched (no MAP_UNSYNCHRONIZED)" | tee -a "$LOG"
  fi
  step_done "libwebgl_patch"
else step_skip "libwebgl_patch"; fi

# ── STEP 6: Clone portal-port repo ───────────────────────────────────────────
if need_step "repo_clone"; then
  echo "[STEP 6] clone portal-port" | tee -a "$LOG"
  mkdir -p "$SCRIPT_DIR/engine"
  git clone --depth=1 --recurse-submodules --shallow-submodules \
    https://github.com/weliveinhell/source-engine "$REPO_DIR" 2>&1 | tee -a "$LOG"
  step_done "repo_clone"
else step_skip "repo_clone"; fi

# ── STEP 7: Apply source patches ─────────────────────────────────────────────
if need_step "source_patches"; then
  echo "[STEP 7] source patches" | tee -a "$LOG"
  cd "$REPO_DIR"

  # alloca.h for emscripten (ivp_physics.hxx)
  python3 -c "
p='ivp/ivp_physics/ivp_physics.hxx'
with open(p) as f: c=f.read()
old='#include <stdio.h>'
new='#include <stdio.h>\n#ifdef __EMSCRIPTEN__\n#include <alloca.h>\n#endif'
if old in c and 'alloca' not in c:
    c=c.replace(old,new,1); open(p,'w').write(c); print('alloca ivp OK')
else: print('alloca ivp SKIP')
"

  # emscripten_stubs.cpp
  cat > emscripten/emscripten_stubs.cpp << 'STUBS'
#ifdef __EMSCRIPTEN__
unsigned long GetRam() { return 2047UL; }
#include <sys/time.h>
int futimes(int fd, const struct timeval tv[2]) { return 0; }
#endif
STUBS
  echo "emscripten_stubs.cpp OK" | tee -a "$LOG"

  # ivp_mindist_minimize.cxx — wrap file in EMSCRIPTEN guard
  python3 -c "
p='ivp/ivp_collision/ivp_mindist_minimize.cxx'
with open(p) as f: lines=f.readlines()
if lines and lines[0].strip()!='#ifndef __EMSCRIPTEN__':
    lines=['#ifndef __EMSCRIPTEN__\n']+lines+['\n#endif\n']
    open(p,'w').writelines(lines); print('mindist guard OK')
else: print('mindist guard SKIP')
"

  # basefilesystem.cpp printf patch (for get_logs.sh asset discovery)
  python3 -c "
p='filesystem/basefilesystem.cpp'
with open(p) as f: c=f.read()
old='FileHandle_t CBaseFileSystem::OpenForRead( const char *pFileNameT, const char *pOptions, unsigned flags, const char *pathID, char **ppszResolvedFilename )\n{\n\tVPROF( \"CBaseFileSystem::OpenForRead\" );'
new='FileHandle_t CBaseFileSystem::OpenForRead( const char *pFileNameT, const char *pOptions, unsigned flags, const char *pathID, char **ppszResolvedFilename )\n{\n\tprintf(\"OpenForRead %s %s\\\n\", pFileNameT, pathID ? pathID : \"\");\n\tVPROF( \"CBaseFileSystem::OpenForRead\" );'
if old in c and 'OpenForRead %s' not in c:
    c=c.replace(old,new,1); open(p,'w').write(c); print('printf patch OK')
else: print('printf patch SKIP')
"

  # native_stubs.cpp
  cat > engine/native_stubs.cpp << 'NSTUBS'
#ifndef __EMSCRIPTEN__
#include <stdio.h>
#include <sys/utsname.h>
unsigned long GetRam() { return 2047UL; }
void DisplaySystemVersion(char *osversion, int maxlen) {
    struct utsname u;
    if (uname(&u)==0) snprintf(osversion,maxlen,"%s %s %s",u.sysname,u.release,u.machine);
    else snprintf(osversion,maxlen,"Linux unknown");
}
#endif
NSTUBS
  echo "native_stubs.cpp OK" | tee -a "$LOG"

  # engine/wscript: add native_stubs.cpp
  python3 -c "
p='engine/wscript'
with open(p) as f: c=f.read()
old=\"source += ['audio/snd_posix.cpp']\"
new=\"source += ['audio/snd_posix.cpp', 'native_stubs.cpp']\"
if old in c and new not in c: c=c.replace(old,new,1); open(p,'w').write(c); print('engine wscript OK')
else: print('engine wscript SKIP')
"

  step_done "source_patches"
else step_skip "source_patches"; fi

# ── STEP 8: Native build (for get_logs.sh) ───────────────────────────────────
if need_step "native_build"; then
  echo "[STEP 8] native build" | tee -a "$LOG"
  cd "$REPO_DIR"
  export PKG_CONFIG_PATH=/usr/lib/i386-linux-gnu/pkgconfig:/usr/share/pkgconfig
  python3 waf configure --out=build_native --prefix=build/install_native 2>&1 | tee -a "$LOG"
  python3 waf install 2>&1 | tee -a "$LOG"
  echo "NATIVE_BUILD_EXIT:$?" | tee -a "$LOG"
  step_done "native_build"
else step_skip "native_build"; fi

# ── STEP 9: get_logs.sh (asset file discovery) ───────────────────────────────
if need_step "get_logs"; then
  echo "[STEP 9] get_logs.sh" | tee -a "$LOG"
  cd "$REPO_DIR/build/install_native"
  
  # Setup HL2 game dir symlink
  ln -sfn "$ASSETS_HL2/hl2" ./hl2 2>/dev/null || true
  ln -sfn "$ASSETS_HL2/platform" ./platform 2>/dev/null || true

  # Start Xvfb
  Xvfb :99 -screen 0 1024x768x16 &
  XVFB_PID=$!
  export DISPLAY=:99
  sleep 2

  # Run get_logs.sh — captures all OpenForRead calls per map
  mkdir -p "$SCRIPT_DIR/config/asset_logs"
  
  maps=(
    d1_trainstation_01 d1_trainstation_02 d1_trainstation_03
    d1_canals_01 d1_canals_01a d1_canals_02
    d2_coast_01 d2_coast_03 d3_c17_01 d3_citadel_01
  )
  
  for map in "${maps[@]}"; do
    echo "[get_logs] $map" | tee -a "$LOG"
    LD_LIBRARY_PATH=./bin:. ./hl2_launcher -game hl2 +map "$map" \
      2>&1 > "$SCRIPT_DIR/config/asset_logs/map-$map.txt" &
    PID=$!
    sleep 20
    kill $PID 2>/dev/null || true
    sleep 3
  done

  kill $XVFB_PID 2>/dev/null || true
  step_done "get_logs"
else step_skip "get_logs"; fi

# ── STEP 10: WASM build ──────────────────────────────────────────────────────
if need_step "wasm_build"; then
  echo "[STEP 10] WASM build" | tee -a "$LOG"
  cd "$REPO_DIR"
  bash emscripten/build.sh 2>&1 | tee -a "$LOG"
  echo "WASM_EXIT:$?" | tee -a "$LOG"
  step_done "wasm_build"
else step_skip "wasm_build"; fi

# ── STEP 11: repackage.js ────────────────────────────────────────────────────
if need_step "repackage"; then
  echo "[STEP 11] repackage" | tee -a "$LOG"
  cd "$REPO_DIR"
  # Copy assets to expected location
  mkdir -p build/install_hl2/hl2
  cp -r "$ASSETS_HL2/hl2/." build/install_hl2/hl2/
  cp -r "$ASSETS_HL2/platform" build/install_hl2/ 2>/dev/null || true
  
  node emscripten/repackage.js 2>&1 | tee -a "$LOG"
  echo "REPACKAGE_EXIT:$?" | tee -a "$LOG"
  step_done "repackage"
else step_skip "repackage"; fi

echo "=== ALL STEPS COMPLETE $(date) ===" | tee -a "$LOG"
