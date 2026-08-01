// Canonical Emscripten post-js runtime for HL2 WebXR.
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

    // === v6 SHADER OVERWRITE ===
    // The retail 2153 shaders are version 1 (2004 format).
    // The nillerusr engine (Source 2013) requires version 6 shaders.
    // Download v6 shaders from R2 and overwrite the v1 files in MEMFS.
    return fetchChunk('shaders_v6').then(function(v6Buffer) {
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
    }).then(function() {
    // Preflight: verify critical shader families exist
    var criticalShaders = [
      'vertexlit_and_unlit_generic_vs20',
      'vertexlit_and_unlit_generic_ps20',
      'lightmappedgeneric_vs20',
      'lightmappedgeneric_ps20',
    ]
    var missing = []
    try {
      var fxcDir = '/hl2/shaders/fxc'
      if (FS.analyzePath(fxcDir).exists) {
        var files = FS.readdir(fxcDir).map(function(n) { return n.toLowerCase(); })
        for (var i = 0; i < criticalShaders.length; i++) {
          var found = false
          for (var j = 0; j < files.length; j++) {
            if (files[j].indexOf(criticalShaders[i].toLowerCase()) >= 0) { found = true; break }
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
    })
  }).then(function() {
    // MEMFS is case-sensitive and symlinks are unreliable for Source lookups.
    // Retail 2153 uses capitalized material directories; mirror the actual files
    // into the lowercase paths requested by the engine.
    var mirrorMaterialDir = function(src, dst) {
      try {
        if (!FS.analyzePath(src).exists) return 0
        try { FS.mkdirTree(dst) } catch (e0) {}
        var entries = FS.readdir(src)
        var copied = 0
        for (var mi = 0; mi < entries.length; mi++) {
          var en = entries[mi]
          if (en === '.' || en === '..') continue
          var sp = src + '/' + en
          var dp = dst + '/' + en
          var st = FS.stat(sp)
          if (FS.isDir(st.mode)) copied += mirrorMaterialDir(sp, dp)
          else { FS.writeFile(dp, FS.readFile(sp), {encoding:'binary'}); copied++ }
        }
        console.log('[hl2] Material directory mirrored: ' + src + ' -> ' + dst + ' (' + copied + ' files)')
        return copied
      } catch (e1) {
        console.warn('[hl2] Material mirror failed: ' + src + ' -> ' + dst + ': ' + e1)
        return 0
      }
    }
    mirrorMaterialDir('/hl2/materials/Console', '/hl2/materials/console')
    mirrorMaterialDir('/hl2/materials/Debug', '/hl2/materials/debug')
    mirrorMaterialDir('/hl2/materials/Dev', '/hl2/materials/dev')
    mirrorMaterialDir('/hl2/materials/Engine', '/hl2/materials/engine')
    mirrorMaterialDir('/hl2/materials/Effects', '/hl2/materials/effects')
    // PATCH 3: gameinfo.txt (required by engine setup)
    var gameinfoContent = '"GameInfo"\n{\n  game  "HL2"\n  title  "Half-Life 2"\n  type  singleplayer_only\n  developer  "Valve"\n  icon  "hl2"\n  FileSystem\n  {\n    SteamAppId  2153\n    ToolsAppId  211\n    SearchPaths\n    {\n      Game  |gameinfo_path|.\n      Game  hl2\n      Platform  platform\n    }\n  }\n}'
    FS.writeFile('/hl2/gameinfo.txt', gameinfoContent)
    // /MOD is the engine's writable search path; populate it after chunks exist.
    try {
      FS.mkdirTree('/MOD')
      FS.writeFile('/MOD/gameinfo.txt', gameinfoContent)
      if (FS.analyzePath('/hl2/steam.inf').exists) {
        FS.writeFile('/MOD/steam.inf', FS.readFile('/hl2/steam.inf'))
      }
      console.log('[hl2] /MOD bootstrap files ready')
      if (typeof FS.syncfs === 'function') FS.syncfs(false, function(err) {
        if (err) console.warn('[hl2] /MOD syncfs error:', err)
      })
    } catch (modErr) {
      console.warn('[hl2] /MOD bootstrap error: ' + modErr)
    }
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
    removeRunDependency('load_game_data')
  }).catch(function(err) {
    console.error('[hl2] Chunk load error: ' + err + ' — starting with partial data')
    removeRunDependency('load_game_data')
  })
})();
