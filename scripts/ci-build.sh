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
EMSDK_COMMIT="${EMSDK_COMMIT:-75eb9522ae0d24a9057c29ff6c72336beddf9508}"
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
#include <emscripten/emscripten.h>

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

// IVP_Mindist::do_impact main-module fallback. This symbol is imported by
// libvphysics.so and must be retained in the MAIN_MODULE symbol table.
EMSCRIPTEN_KEEPALIVE
void _ZN11IVP_Mindist9do_impactEv(void* self) {
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

// IVP_Compact_Edge::next_table — global data symbol required by side modules.
// Keep a zero-initialized WASM32 table so dynamic linking resolves the address
// without entering unsupported native IVP code.
__attribute__((weak, used, visibility("default")))
void* _ZN16IVP_Compact_Edge10next_tableE[256] = { 0 };

} // extern "C"

#endif // __EMSCRIPTEN__
EOF
  log "  patch: emscripten_stubs.cpp (with IVP_Mindist main-module fallback)"


  # Patch 6 (post): post.js — Shader + Asset Chunk Loading vor callMain()
  POST_JS="$ENGINE_DIR/emscripten/post.js"
  if [ -f "$POST_JS" ]; then
    cat > "$POST_JS" << 'POST_JS_EOF'
;(() => {
  if(typeof window === 'undefined') return;
  window.addEventListener('beforeunload', function (event) { event.preventDefault() })
  if (typeof canvasElement !== 'undefined' && canvasElement) {
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
// === DATA LOADER: streaming packed [pathLen][dataLen][path][blob] chunks ===
  var dataLoader = (function() {
    var cache = Object.create(null);
    var decoder = new TextDecoder();
    function normalizePath(path) {
      return ('/' + String(path).replace(/^\/+/, '').replace(/\\/g, '/')).replace(/\/+/g, '/');
    }
    function append(a, b) {
      if (!a || !a.length) return b;
      var out = new Uint8Array(a.length + b.length);
      out.set(a); out.set(b, a.length); return out;
    }
    function writeFile(path, data) {
      var slash = path.lastIndexOf('/');
      if (slash > 0) FS.mkdirTree(path.slice(0, slash));
      FS.writeFile(path, data);
    }
    function createUnpacker(mapName) {
      var pending = new Uint8Array(0);
      var pathLen = null, dataLen = null, path = null;
      var files = 0, bytes = 0, lastReport = 0;
      function process() {
        for (;;) {
          if (pathLen === null) {
            if (pending.length < 8) break;
            var header = new DataView(pending.buffer, pending.byteOffset, 8);
            pathLen = header.getUint32(0, true);
            dataLen = header.getUint32(4, true);
            pending = pending.slice(8);
            if (!pathLen || pathLen > 4096 || dataLen > 1024 * 1024 * 1024) {
              throw new Error('Invalid ' + mapName + ' record header');
            }
          }
          if (path === null) {
            if (pending.length < pathLen) break;
            path = normalizePath(decoder.decode(pending.slice(0, pathLen)));
            pending = pending.slice(pathLen);
          }
          if (pending.length < dataLen) break;
          var data = pending.slice(0, dataLen);
          pending = pending.slice(dataLen);
          writeFile(path, data);
          files++; bytes += dataLen;
          if (bytes - lastReport >= 64 * 1024 * 1024) {
            assetTelemetry(mapName + ' unpacked ' + bytes + ' bytes (' + files + ' files)');
            lastReport = bytes;
          }
          pathLen = null; dataLen = null; path = null;
        }
      }
      async function consume(reader) {
        var received = 0;
        try {
          for (;;) {
            var next = await reader.read();
            if (next.value && next.value.length) {
              received += next.value.length;
              pending = append(pending, next.value);
              process();
            }
            if (next.done) break;
          }
          return received;
        } catch (e) {
          e.__rangeReceived = received;
          throw e;
        }
      }
      function finish() {
        process();
        if (pathLen !== null || path !== null || pending.length) {
          throw new Error('Truncated ' + mapName + ' chunk at EOF');
        }
        assetTelemetry('unpack ' + mapName, { files: files, bytes: bytes });
        return { mapName: mapName, files: files, bytes: bytes };
      }
      return { consume: consume, finish: finish };
    }
    async function loadMapRanged(mapName) {
      var url = chunkUrl(mapName);
      var rangeSize = 16 * 1024 * 1024;
      var offset = 0;
      var unpacker = createUnpacker(mapName);
      var complete = false;
      var result = null;
      while (!complete) {
        var received = 0;
        var succeeded = false;
        for (var attempt = 1; attempt <= 3 && !succeeded; attempt++) {
          try {
            var end = offset + rangeSize - 1;
            assetTelemetry('range-start ' + mapName, { start: offset, end: end, attempt: attempt });
            var response = await fetch(url, {
              mode: 'cors', credentials: 'omit',
              headers: { 'Range': 'bytes=' + offset + '-' + end }
            });
            if (response.status === 416) {
              result = unpacker.finish();
              complete = true;
              succeeded = true;
              break;
            }
            if (response.status !== 206 && !(response.status === 200 && offset === 0)) {
              throw new Error('Chunk ' + mapName + ': HTTP ' + response.status);
            }
            if (!response.body || !response.body.getReader) {
              throw new Error(mapName + ' range response has no readable body');
            }
            var chunkBytes = await unpacker.consume(response.body.getReader());
            offset += chunkBytes;
            assetTelemetry('range-received ' + mapName, { bytes: chunkBytes, offset: offset });
            received = 0;
            if (chunkBytes < rangeSize) {
              result = unpacker.finish();
              complete = true;
            }
            succeeded = true;
          } catch (e) {
            received = e.__rangeReceived || received;
            if (received) offset += received;
            assetTelemetry('range-retry ' + mapName, { offset: offset, attempt: attempt, error: String(e) });
            if (attempt === 3) throw e;
            await new Promise(function(resolve) { setTimeout(resolve, 500 * attempt); });
          }
        }
        if (!succeeded) throw new Error('Range loader stalled for ' + mapName);
      }
      return result || unpacker.finish();
    }
    function loadMap(mapName) {
      if (!cache[mapName]) {
        cache[mapName] = (async function() {
          var started = performance.now();
          assetTelemetry('stream-start ' + mapName, { url: chunkUrl(mapName), mode: 'range-resume' });
          var result = await loadMapRanged(mapName);
          assetTelemetry('stream-done ' + mapName, { duration_ms: Math.round(performance.now() - started) });
          return result;
        })();
      }
      return cache[mapName];
    }
    return { loadMap: loadMap, loadMapCached: loadMap };
  })();

      assetTelemetry('load_game_data registered')
      addRunDependency('load_game_data')

  // Load shaders chunk first (critical, non-optional)
  var loadShaders = (typeof dataLoader !== 'undefined' && dataLoader.loadMapCached)
    ? dataLoader.loadMapCached('shaders')
    : Promise.reject(new Error('dataLoader not available'))

  loadShaders.then(function() {
    console.log('[hl2] shaders.data loaded — ' +
      FS.readdir('/hl2/shaders').length + ' shader dirs in MEMFS')

    // === v6 SHADER OVERWRITE ===
    // The retail 2153 shaders are version 1 (2004 format).
    // The nillerusr engine (Source 2013) requires version 6 shaders.
    // Download v6 shaders from R2 and overwrite the v1 files in MEMFS.
    fetchChunk('shaders_v6').then(function(v6Buffer) {
      var dv = new DataView(v6Buffer)
      var off = 0
      var replaced = 0
      while (off + 8 <= v6Buffer.byteLength) {
        var pathLen = dv.getInt32(off, true)
        var dataLen = dv.getInt32(off + 4, true)
        off += 8
        if (pathLen <= 0 || pathLen > 256 || dataLen <= 0 || dataLen > 50000000) break
        var pathBytes = new Uint8Array(v6Buffer, off, pathLen)
        var path = new TextDecoder().decode(pathBytes)
        off += pathLen
        var shaderData = new Uint8Array(v6Buffer, off, dataLen)
        off += dataLen
        // Overwrite the v1 shader file in MEMFS
        try {
          FS.writeFile(path, shaderData)
          replaced++
        } catch(e) {
          console.warn('[hl2] v6 shader overwrite failed for ' + path + ': ' + e)
        }
      }
      console.log('[hl2] v6 shaders: ' + replaced + ' files overwritten in MEMFS')
    }).catch(function(e) {
      console.warn('[hl2] v6 shader download failed (using v1 fallback): ' + e)
    })
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

    // Load large chunks sequentially to avoid parallel long-stream connection resets.
    // Runtime/map initialization remains blocked until both chunks complete.
    return dataLoader.loadMap('background1').then(function() {
      return fetch(CHUNK_PREFIX + '/materials-manifest.json', { mode: 'cors', credentials: 'omit' })
        .then(function(r) { if (!r.ok) throw new Error('materials manifest HTTP ' + r.status); return r.json() })
        .then(function(manifest) {
          if (!manifest.chunks || !manifest.chunks.length) throw new Error('materials manifest has no chunks')
          return manifest.chunks.reduce(function(chain, chunk) {
            return chain.then(function() { return dataLoader.loadMap(chunk.name.replace(/\.data$/, '')) })
          }, Promise.resolve())
        })
    })
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
    // PATCH 3: gameinfo.txt (required by engine setup)
    var gameinfoContent = '"GameInfo"\n{\n  game  "HL2"\n  title  "Half-Life 2"\n  type  singleplayer_only\n  developer  "Valve"\n  icon  "hl2"\n  FileSystem\n  {\n    SteamAppId  2153\n    ToolsAppId  211\n    SearchPaths\n    {\n      Game  |gameinfo_path|.\n      Game  hl2\n      Platform  platform\n    }\n  }\n}'
    FS.writeFile('/hl2/gameinfo.txt', gameinfoContent)
    console.log('[hl2] gameinfo.txt created in MEMFS')

    // PATCH 4: VTF files — replace dummy VTFs with proper VTF format
    var vtfFixList = [
      '/hl2/materials/dev/identitylightwarp.vtf',
      '/hl2/materials/engine/normalizedrandomdirections2d.vtf',
      '/hl2/materials/effects/flashlight_border.vtf'
    ]
    var vtfFixed = 0
    for (var vi = 0; vi < vtfFixList.length; vi++) {
      var vtfPath = vtfFixList[vi]
      if (FS.analyzePath(vtfPath).exists) {
        var existing = FS.readFile(vtfPath)
        if (existing[0] !== 0x56) {
          var vtfHeader = new Uint8Array(84)
          vtfHeader[0] = 0x56; vtfHeader[1] = 0x54; vtfHeader[2] = 0x46; vtfHeader[3] = 0x00
          vtfHeader[4] = 7; vtfHeader[8] = 1; vtfHeader[12] = 80
          vtfHeader[16] = 4; vtfHeader[18] = 4
          vtfHeader[20] = 0x00; vtfHeader[21] = 0x40
          vtfHeader[24] = 1; vtfHeader[44] = 12; vtfHeader[48] = 1
          vtfHeader[52] = 12; vtfHeader[56] = 1; vtfHeader[57] = 1; vtfHeader[58] = 1
          vtfHeader[80] = 128; vtfHeader[81] = 128; vtfHeader[82] = 128; vtfHeader[83] = 255
          var fullImage = new Uint8Array(64)
          for (var fi = 0; fi < 16; fi++) { fullImage[fi*4]=128; fullImage[fi*4+1]=128; fullImage[fi*4+2]=128; fullImage[fi*4+3]=255 }
          var fullVtf = new Uint8Array(80 + 4 + 64)
          fullVtf.set(vtfHeader.subarray(0,80), 0)
          fullVtf.set(vtfHeader.subarray(80,84), 80)
          fullVtf.set(fullImage, 84)
          FS.writeFile(vtfPath, fullVtf)
          vtfFixed++
        }
      }
    }
    console.log('[hl2] Fixed ' + vtfFixed + ' VTF files in MEMFS')

    // PATCH 5: Shader version — patch .vcs files from version 1 to version 6
    try {
      var fxcDir = '/hl2/shaders/fxc'
      var shaderFiles = FS.readdir(fxcDir)
      var versionPatched = 0
      for (var sfi = 0; sfi < shaderFiles.length; sfi++) {
        var sfn = shaderFiles[sfi]
        if (sfn === '.' || sfn === '..') continue
        if (sfn.indexOf('.vcs') < 0) continue
        var sfp = fxcDir + '/' + sfn
        var sdata = FS.readFile(sfp)
        if (sdata.length >= 4 && sdata[0] === 1 && sdata[1] === 0 && sdata[2] === 0 && sdata[3] === 0) {
          sdata[0] = 6
          FS.writeFile(sfp, sdata)
          versionPatched++
        }
      }
      console.log('[hl2] Patched ' + versionPatched + ' shader files from version 1 to version 6')
    } catch(e) { console.warn('[hl2] Shader version patch error: ' + e) }

    // PATCH 6: Shader case-insensitive symlinks (MEMFS is case-sensitive)
    try {
      var fxcDir2 = '/hl2/shaders/fxc'
      var shaderFiles2 = FS.readdir(fxcDir2)
      var caseFixed = 0
      for (var si = 0; si < shaderFiles2.length; si++) {
        var fname = shaderFiles2[si]
        if (fname === '.' || fname === '..') continue
        var lower = fname.toLowerCase()
        if (lower !== fname && !FS.analyzePath(fxcDir2 + '/' + lower).exists) {
          FS.symlink(fxcDir2 + '/' + fname, fxcDir2 + '/' + lower)
          caseFixed++
        }
      }
      console.log('[hl2] Fixed ' + caseFixed + ' shader filename cases')
    } catch(e) { console.warn('[hl2] Shader case fix error: ' + e) }

    console.log('[hl2] All chunks loaded, starting engine...')
    assetTelemetry('all chunks loaded; releasing load_game_data')
    removeRunDependency('load_game_data')
  }).catch(function(err) {
    assetTelemetry('chunk load error; releasing load_game_data with partial data', { error: String(err) })
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

  # === BUILD #97: em_loop_iteration KEEPALIVE patch ===
  # The Source Engine defines em_loop_iteration() as 'void' (not static) in sys_dll2.cpp.
  # wasm-ld DCE strips it because no exported function references it directly.
  # The main WASM imports _Z17em_loop_iterationv from env, but no side module exports it.
  # Fix: Add EMSCRIPTEN_KEEPALIVE (WITHOUT extern "C") to prevent DCE.
  # Must keep C++ linkage — the main WASM imports _Z17em_loop_iterationv (mangled name).
  # extern "C" would rename to _em_loop_iteration and the import would NOT be satisfied.
  for sys_dll in "$ENGINE_DIR/engine/gamedll/sys_dll2.cpp" "$ENGINE_DIR/engine/sys_dll2.cpp"; do
    if [ -f "$sys_dll" ]; then
      log "  patch: em_loop_iteration KEEPALIVE in $sys_dll"
      # Add #include <emscripten.h> if not present
      if ! grep -q 'emscripten.h' "$sys_dll"; then
        sed -i '1s/^/#include <emscripten.h>\n/' "$sys_dll"
      fi
      # Replace 'static void em_loop_iteration()' with KEEPALIVE version
      # The function is "void em_loop_iteration()" or "void em_loop_iteration(void)"
      sed -i 's/^void em_loop_iteration *( *void *)/EMSCRIPTEN_KEEPALIVE void em_loop_iteration(void)/g' "$sys_dll"
      # Also handle 'static void em_loop_iteration()' without void
      sed -i 's/^void em_loop_iteration *()/EMSCRIPTEN_KEEPALIVE void em_loop_iteration(void)/g' "$sys_dll"
      # Verify the patch was applied
      if grep -q 'EMSCRIPTEN_KEEPALIVE.*em_loop_iteration' "$sys_dll"; then
        log "  ✓ em_loop_iteration now has EMSCRIPTEN_KEEPALIVE"
      else
        log "  WARNING: em_loop_iteration patch not applied — function may not exist in this file"
      fi
      break
    fi
  done

  # === BUILD #108: KEEPALIVE patches for engine functions ===
  # These functions need EMSCRIPTEN_KEEPALIVE so they're exported from
  # the side module (libengine.so) and accessible via dlsym/mergeLibSymbols.
  # Without KEEPALIVE, wasm-ld strips them via dead-code elimination.

  # Host_Init and Host_RunFrame are in engine/host.cpp
  host_src="$ENGINE_DIR/engine/host.cpp"
  if [ -f "$host_src" ]; then
    log "  patching: $host_src"

    # Add #include <emscripten.h> if not present
    if ! grep -q 'emscripten.h' "$host_src"; then
      sed -i '1s/^/#include <emscripten.h>\n/' "$host_src"
    fi

    # Host_Init — void Host_Init( bool bDedicated )
    # Match with flexible whitespace
    sed -i 's/^void Host_Init *( *bool *bDedicated *)/EMSCRIPTEN_KEEPALIVE void Host_Init( bool bDedicated )/g' "$host_src"
    sed -i 's/^void Host_Init *( *bool *)/EMSCRIPTEN_KEEPALIVE void Host_Init( bool )/g' "$host_src"

    # Host_RunFrame — void Host_RunFrame( float time )
    sed -i 's/^void Host_RunFrame *( *float *time *)/EMSCRIPTEN_KEEPALIVE void Host_RunFrame( float time )/g' "$host_src"
    sed -i 's/^void Host_RunFrame *( *float *)/EMSCRIPTEN_KEEPALIVE void Host_RunFrame( float )/g' "$host_src"

    # Verify
    if grep -q 'EMSCRIPTEN_KEEPALIVE.*Host_Init' "$host_src"; then
      log "  ✓ Host_Init now has EMSCRIPTEN_KEEPALIVE"
    else
      log "  WARNING: Host_Init patch not applied"
    fi
    if grep -q 'EMSCRIPTEN_KEEPALIVE.*Host_RunFrame' "$host_src"; then
      log "  ✓ Host_RunFrame now has EMSCRIPTEN_KEEPALIVE"
    else
      log "  WARNING: Host_RunFrame patch not applied"
    fi
  fi

  # Cbuf_AddText and Cbuf_Execute are in engine/cmd.cpp (NOT cbuf.cpp)
  cmd_src="$ENGINE_DIR/engine/cmd.cpp"
  if [ -f "$cmd_src" ]; then
    log "  patching: $cmd_src"

    if ! grep -q 'emscripten.h' "$cmd_src"; then
      sed -i '1s/^/#include <emscripten.h>\n/' "$cmd_src"
    fi

    # Cbuf_AddText — void Cbuf_AddText( const char *pText )
    sed -i 's/^void Cbuf_AddText *( *const char \*pText *)/EMSCRIPTEN_KEEPALIVE void Cbuf_AddText( const char *pText )/g' "$cmd_src"
    sed -i 's/^void Cbuf_AddText *( *const char \*[^)]*)/EMSCRIPTEN_KEEPALIVE void Cbuf_AddText( const char *pText )/g' "$cmd_src"

    # Cbuf_Execute — void Cbuf_Execute()
    sed -i 's/^void Cbuf_Execute *()/EMSCRIPTEN_KEEPALIVE void Cbuf_Execute()/g' "$cmd_src"
    sed -i 's/^void Cbuf_Execute *( *void *)/EMSCRIPTEN_KEEPALIVE void Cbuf_Execute(void)/g' "$cmd_src"

    if grep -q 'EMSCRIPTEN_KEEPALIVE.*Cbuf_AddText' "$cmd_src"; then
      log "  ✓ Cbuf_AddText now has EMSCRIPTEN_KEEPALIVE"
    else
      log "  WARNING: Cbuf_AddText patch not applied"
    fi
    if grep -q 'EMSCRIPTEN_KEEPALIVE.*Cbuf_Execute' "$cmd_src"; then
      log "  ✓ Cbuf_Execute now has EMSCRIPTEN_KEEPALIVE"
    else
      log "  WARNING: Cbuf_Execute patch not applied"
    fi
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
  # Hook source is intentionally rebuilt for each CI run; invalidate any
  # previous link checkpoint so the fresh object is included in the WASM.
  if [ -f "$REPO_ROOT/emscripten/webxr_hooks.cpp" ]; then
    sed -i '/emcc_link/d' "$checkpoint_file" 2>/dev/null || true
  fi
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

  # Also force re-link if source_patches changed (e.g. em_loop_iteration patch)
  _sp_hash=$(grep "em_loop_iteration\|WebXR_Engine_LoadMap\|do_impact\|EMSCRIPTEN_KEEPALIVE.*do_impact\|EMSCRIPTEN_KEEPALIVE.*em_loop\|KEEPALIVE.*Host_Init\|KEEPALIVE.*Host_RunFrame\|KEEPALIVE.*Cbuf_AddText\|KEEPALIVE.*Cbuf_Execute" "$REPO_ROOT/scripts/ci-build.sh" | md5sum | cut -c1-8)
  _sp_cache="$ENGINE_DIR/build/.sp_hash"
  if [ -f "$_sp_cache" ] && [ "$(cat "$_sp_cache")" != "$_sp_hash" ]; then
    log "Source patches changed — forcing waf_build + emcc_link re-run"
    sed -i '/emcc_link/d' "$checkpoint_file" 2>/dev/null || true
    sed -i '/waf_build/d' "$checkpoint_file" 2>/dev/null || true
    # Also clear source_patches checkpoint to re-apply patches
    sed -i '/source_patches/d' "$checkpoint_file" 2>/dev/null || true
    # Clear waf build cache to force recompilation with KEEPALIVE
    find "$ENGINE_DIR/build" -mindepth 1 -delete 2>/dev/null || true
  fi
  echo "$_sp_hash" > "$_sp_cache" 2>/dev/null || true

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
    log "Compiling webxr_hooks.cpp (forced fresh object)..."
    rm -f "$webxr_hooks_obj" 2>/dev/null || true
    emcc -O0 -fPIC -D__EMSCRIPTEN__ -c "$webxr_hooks_src" -o "$webxr_hooks_obj"
    log "  webxr_hooks compiled: $webxr_hooks_obj"
  else
    webxr_hooks_obj=""
    log "  webxr_hooks.cpp not found, skipping (Phase 2 engine hooks)"
  fi

  # Copy pre.js and shell.html from repo root to ENGINE_DIR/emscripten/ (emcc runs from ENGINE_DIR)
  mkdir -p "$ENGINE_DIR/emscripten" 2>/dev/null || true
  [ -f "$REPO_ROOT/emscripten/pre.js" ] && cp "$REPO_ROOT/emscripten/pre.js" "$ENGINE_DIR/emscripten/pre.js"
  [ -f "$REPO_ROOT/emscripten/shell.html" ] && cp "$REPO_ROOT/emscripten/shell.html" "$ENGINE_DIR/emscripten/shell.html" || true
  # Ensure pre.js content is fresh (not from a previous cached build)
  if [ ! -f "$ENGINE_DIR/emscripten/pre.js" ]; then
    log "  WARNING: pre.js not found — creating minimal pre.js"
    cat > "$ENGINE_DIR/emscripten/pre.js" << 'PRE_JS_FALLBACK'
var canvasElement = null;
var statusElement = null;
var progressElement = null;
var spinnerElement = null;
var __allowCanvasTransfer = true;
var transferredCanvasNames = "";
PRE_JS_FALLBACK
  fi
  log "  pre.js: $(wc -c < "$ENGINE_DIR/emscripten/pre.js" 2>/dev/null || echo 'missing') bytes"

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
    -sOFFSCREENCANVASES_TO_PTHREAD="#game-canvas" \
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

  # PROXY_TO_PTHREAD: Module.setStatus can execute in a worker where DOM nodes are null.
  # Keep status reporting alive without letting progress UI access abort runtime startup.
  for html_file in build/launcher_main/hl2_launcher.html build/install/hl2_launcher.html; do
    if [ -f "$html_file" ]; then
      python3 - "$html_file" <<'PY_DOM_SAFE'
import sys
from pathlib import Path
p = Path(sys.argv[1])
s = p.read_text()
old = """            progressElement.value = parseInt(m[2])*100;
            progressElement.max = parseInt(m[4])*100;
            progressElement.hidden = false;
            spinnerElement.hidden = false;"""
new = """            if (progressElement) {
              progressElement.value = parseInt(m[2])*100;
              progressElement.max = parseInt(m[4])*100;
              progressElement.hidden = false;
            }
            if (spinnerElement) spinnerElement.hidden = false;"""
old2 = """            progressElement.value = null;
            progressElement.max = null;
            progressElement.hidden = true;
            if (!text) spinnerElement.style.display = 'none';
          }
          statusElement.innerHTML = text;"""
new2 = """            if (progressElement) {
              progressElement.value = null;
              progressElement.max = null;
              progressElement.hidden = true;
            }
            if (!text && spinnerElement) spinnerElement.style.display = 'none';
          }
          if (statusElement) statusElement.innerHTML = text;"""
if old not in s or old2 not in s:
    raise SystemExit(f'DOM status block not found or already changed: {p}')
s = s.replace(old, new, 1).replace(old2, new2, 1)
p.write_text(s)
print(f'DOM-safe status patched: {p}')
PY_DOM_SAFE
    fi
  done

  cp build/launcher_main/hl2_launcher.{html,js,wasm} build/install/

  # GL stubs + dlsym/dlopen intercept + GL version spoof
  python3 "$REPO_ROOT/scripts/gl_stubs_patch.py" build/launcher_main/hl2_launcher.js || true
  python3 "$REPO_ROOT/scripts/gl_stubs_patch.py" build/install/hl2_launcher.js || true
  # Runtime safety patches: non-fatal abort, exception handling, GL fallback
  python3 "$REPO_ROOT/scripts/runtime_patches.py" build/launcher_main/hl2_launcher.js || true
  python3 "$REPO_ROOT/scripts/runtime_patches.py" build/install/hl2_launcher.js || true
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
// Startup config/resource only. Do not place the complete maps tree here:
// the reference port creates map-specific chunks from OpenForRead traces.
const bgDirs = [
  [baseGamePath + '/hl2/cfg',           '/hl2'],
  [baseGamePath + '/hl2/resource',      '/hl2'],
  [baseGamePath + '/platform/resource', '/platform'],
]
for (const [srcDir, vBase] of bgDirs) {
  if (fs.existsSync(srcDir)) {
    const bytes = walk(bgChunks, srcDir, vBase, path.basename(srcDir))
    console.log(`  ${srcDir}: ${Math.round(bytes/1024/1024)}MB`)
  } else {
    console.log(`  SKIP: ${srcDir}`)
  }
}

// Only the first map is part of the bootstrap chunk. Later BSPs receive
// zero-length stubs so Source can resolve their virtual paths without
// transferring every campaign map before Engine_Init.
const mapsDir = baseGamePath + '/hl2/maps'
const startupMapNames = ['background01.bsp', 'background1.bsp']
let startupMapAdded = false
for (const name of startupMapNames) {
  const src = path.join(mapsDir, name)
  if (fs.existsSync(src)) {
    const bytes = addFile(bgChunks, src, '/hl2/maps/' + name)
    console.log(`  startup map: ${name}: ${Math.round(bytes/1024/1024)}MB`)
    startupMapAdded = true
    break
  }
}
if (!startupMapAdded) console.log('  WARNING: startup BSP not found (background01/background1)')
if (fs.existsSync(mapsDir)) {
  for (const name of fs.readdirSync(mapsDir).filter(n => /\.bsp$/i.test(n))) {
    if (startupMapNames.includes(name)) continue
    const dst = Buffer.from('/hl2/maps/' + name)
    const hdr = Buffer.alloc(8)
    hdr.writeUint32LE(dst.length, 0)
    hdr.writeUint32LE(0, 4)
    bgChunks.push(hdr, dst)
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
writeSplitChunks('materials', [
  [baseGamePath + '/hl2/materials',     '/hl2'],
], 48 * 1024 * 1024)


// Split a large asset tree into bounded record-stream chunks while preserving
// the original virtual paths. Records are never split across chunk files.
function writeSplitChunks(prefix, dirPairs, maxBytes = 48 * 1024 * 1024) {
  let current = [], currentBytes = 0, index = 0, totalBytes = 0, totalFiles = 0
  const manifest = []
  function flush() {
    if (!current.length) return
    const name = prefix + '_' + String(index++).padStart(3, '0') + '.data'
    const buf = Buffer.concat(current)
    fs.writeFileSync(path.join(outDir, name), buf)
    manifest.push({ name, bytes: buf.length, files: current.length })
    current = []; currentBytes = 0
  }
  function addRecord(src, vpath) {
    let blob
    try { blob = fs.readFileSync(src) } catch { return 0 }
    const dst = Buffer.from(vpath)
    const hdr = Buffer.alloc(8)
    hdr.writeUint32LE(dst.length, 0); hdr.writeUint32LE(blob.length, 4)
    const record = Buffer.concat([hdr, dst, blob])
    if (current.length && currentBytes + record.length > maxBytes) flush()
    current.push(record); currentBytes += record.length
    totalBytes += blob.length; totalFiles++
    return blob.length
  }
  function walkSplit(dir, vBase, srcRel) {
    let entries
    try { entries = fs.readdirSync(dir, {withFileTypes: true}) } catch { return }
    for (const e of entries) {
      const full = path.join(dir, e.name)
      const rel = srcRel ? srcRel + '/' + e.name : e.name
      if (e.isDirectory()) walkSplit(full, vBase, rel)
      else addRecord(full, vBase + '/' + rel)
    }
  }
  for (const [srcDir, vBase] of dirPairs) {
    if (fs.existsSync(srcDir)) walkSplit(srcDir, vBase, path.basename(srcDir))
    else console.log(`  SKIP (not found): ${srcDir}`)
  }
  flush()
  const manifestPath = path.join(outDir, prefix + '-manifest.json')
  fs.writeFileSync(manifestPath, JSON.stringify({ format: 1, prefix, maxBytes, totalBytes, totalFiles, chunks: manifest }, null, 2))
  console.log(`-> ${prefix}: ${manifest.length} chunks, ${Math.round(totalBytes/1024/1024)}MB, ${totalFiles} files`)
  return manifest
}

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
  cp "$REPO_ROOT/emscripten/_headers"              "$OUT_DIR/" 2>/dev/null || true

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



