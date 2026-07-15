// ===== Desktop GL Function Stubs =====
// Source Engine queries GL function pointers via SDL_GL_GetProcAddress.
// These desktop GL functions don't exist in WebGL — provide no-op stubs
// so the engine doesn't crash on null function pointers.
Module.preRun = Module.preRun || [];
Module.preRun.push(function() {
  // Intercept GL function lookups after Emscripten runtime is ready
  var origGetProcAddress = Module._SDL_GL_GetProcAddress || Module._glGetProcAddress;
  
  // Desktop GL no-op stubs that report as valid function pointers
  var glStubs = {
    'glAlphaFunc': function() {},
    'glColor4f': function() {},
    'glClientActiveTexture': function() {},
    'glGetTexLevelParameteriv': function() {},
    'glDrawRangeElementsBaseVertex': function() {},
    'glDrawElementsBaseVertex': function() {},
    'glBegin': function() {},
    'glEnd': function() {},
    'glVertex3f': function() {},
    'glVertex2f': function() {},
    'glTexCoord2f': function() {},
    'glTexCoord3f': function() {},
    'glNormal3f': function() {},
    'glColor3f': function() {},
    'glColor4ub': function() {},
    'glMatrixMode': function() {},
    'glLoadIdentity': function() {},
    'glOrtho': function() {},
    'glFrustum': function() {},
    'glPushMatrix': function() {},
    'glPopMatrix': function() {},
    'glTranslatef': function() {},
    'glRotatef': function() {},
    'glScalef': function() {},
    'glEnableClientState': function() {},
    'glDisableClientState': function() {},
    'glVertexPointer': function() {},
    'glTexCoordPointer': function() {},
    'glNormalPointer': function() {},
    'glColorPointer': function() {},
    'glShadeModel': function() {},
    'glLightfv': function() {},
    'glLightf': function() {},
    'glLighti': function() {},
    'glMaterialfv': function() {},
    'glMaterialf': function() {},
    'glFogf': function() {},
    'glFogfv': function() {},
    'glFogi': function() {},
    'glHint': function() {},
    'glTexImage1D': function() {},
    'glTexSubImage1D': function() {},
    'glGetTexImage': function() {},
    'glRectf': function() {},
    'glRecti': function() {},
    'glClearDepth': function() {},
    'glPolygonMode': function() {},
    'glInitNames': function() {},
    'glLoadName': function() {},
    'glPushName': function() {},
    'glPopName': function() {},
    'glRenderMode': function() { return 0; },
    'glSelectBuffer': function() {},
    'glFeedbackBuffer': function() {},
    'glPassThrough': function() {},
    'glEdgeFlag': function() {},
    'glIndexi': function() {},
    'glIndexf': function() {},
    'glLogicOp': function() {},
    'glAccum': function() {},
    'glClearAccum': function() {},
    'glMap1f': function() {},
    'glMap2f': function() {},
    'glMapGrid1f': function() {},
    'glMapGrid2f': function() {},
    'glEvalCoord1f': function() {},
    'glEvalCoord2f': function() {},
    'glEvalMesh1': function() {},
    'glEvalMesh2': function() {},
    'glEvalPoint1': function() {},
    'glEvalPoint2': function() {},
    'glPixelTransferf': function() {},
    'glPixelTransferi': function() {},
    'glPixelMapfv': function() {},
    'glPixelZoom': function() {},
    'glCopyPixels': function() {},
    'glDrawPixels': function() {},
    'glBitmap': function() {},
    'glListBase': function() {},
    'glCallList': function() {},
    'glCallLists': function() {},
    'glNewList': function() {},
    'glEndList': function() {},
    'glDeleteLists': function() {},
    'glGenLists': function() { return 0; },
    'glIsList': function() { return 0; },
    'glAreTexturesResident': function() { return 1; },
    'glPrioritizeTextures': function() {},
    'glColorMaterial': function() {},
    'glGetPointerv': function() {},
    'glPushAttrib': function() {},
    'glPopAttrib': function() {},
    'glPushClientAttrib': function() {},
    'glPopClientAttrib': function() {},
    'glClipPlane': function() {},
    'glGetClipPlane': function() {},
    'glGetLightfv': function() {},
    'glGetLightiv': function() {},
    'glGetMaterialfv': function() {},
    'glGetMaterialiv': function() {},
    'glGetPixelMapfv': function() {},
    'glGetPixelMapusv': function() {},
    'glGetPixelMapuiv': function() {},
    'glGetPolygonStipple': function() {},
    'glGetTexEnvfv': function() {},
    'glGetTexEnviv': function() {},
    'glGetTexGenfv': function() {},
    'glGetTexGendv': function() {},
    'glGetTexGeniv': function() {},
    'glGetTexParameterPointerv': function() {},
    'glGetTexParameterPointervAPPLE': function() {},
    'glMultiTexCoord1f': function() {},
    'glMultiTexCoord2f': function() {},
    'glMultiTexCoord3f': function() {},
    'glMultiTexCoord4f': function() {},
    'glMultiTexCoord1i': function() {},
    'glMultiTexCoord2i': function() {},
    'glMultiTexCoord3i': function() {},
    'glMultiTexCoord4i': function() {},
    'glActiveTextureARB': function() {},
    'glClientActiveTextureARB': function() {},
    'glPointParameterf': function() {},
    'glPointParameterfv': function() {},
    'glPointParameteri': function() {},
    'glPointParameteriv': function() {},
    'glFogCoordf': function() {},
    'glFogCoordfv': function() {},
    'glFogCoordd': function() {},
    'glFogCoorddv': function() {},
    'glFogCoordPointer': function() {},
    'glSecondaryColor3f': function() {},
    'glSecondaryColor3ub': function() {},
    'glSecondaryColorPointer': function() {},
    'glWindowPos2f': function() {},
    'glWindowPos3f': function() {},
    'glBlendFuncSeparate': function() {},
    'glMultiDrawArrays': function() {},
    'glPointParameterfARB': function() {},
    'glPointParameterfvARB': function() {},
    'glActiveTexture': function() {},
    'glSampleCoverage': function() {}
  };
  
  // Store stubs for lookup - Emscripten's SDL_GL_GetProcAddress uses _emscripten_GetProcAddress
  Module.__glStubs = glStubs;
  
  // Override the Emscripten GL proc address lookup
  if (Module._emscripten_GetProcAddress) {
    var origEmGetProc = Module._emscripten_GetProcAddress;
    Module._emscripten_GetProcAddress = function(namePtr) {
      var name = UTF8ToString(namePtr);
      if (glStubs[name]) {
        console.log('[GL] Stub for: ' + name);
        return addFunction(glStubs[name]);
      }
      return origEmGetProc(namePtr);
    };
  }
  
  console.log('[GL] Desktop GL stub table ready (' + Object.keys(glStubs).length + ' functions)');
});



// Create gameinfo.txt for HL2
Module.preRun.push(function() {
  if (typeof FS !== 'undefined') {
    FS.mkdirTree('/hl2');
    var gameinfo = [
  '"GameInfo"',
  '{',
  '  game    "HALF-LIFE 2"',
  '  title   "HALF-LIFE 2"',
  '  type    singleplayer_only',
  '  nomodels 1',
  '  nohint 1',
  '  nodifficulty 1',
  '  gamedetail 1',
  '  GameData "hl2"',
  '  FileSystem',
  '  {',
  '    SteamAppId        2153',
  '    ToolsAppId         211',
  '    SearchPaths',
  '    {',
  '      Game                |all_source_engine_paths|hl2',
  '      Platform            |all_source_engine_paths|platform',
  '      GameBin             |gameinfo_path|bin',
  '      Game                |gameinfo_path|.',
  '      Game                |all_source_engine_paths|hl2',
  '      Game                |all_source_engine_paths|../hl2',
  '    }',
  '  }',
  '}'
].join('\n');
    FS.writeFile('/hl2/gameinfo.txt', gameinfo);
    console.log('[GAMEINFO] Created /hl2/gameinfo.txt');
  }
});

class DataLoader {
	mapsOrdered = [
		'background1',
		'testchmb_a_00',
		'testchmb_a_01',
		'testchmb_a_02',
		'testchmb_a_03',
		'testchmb_a_04',
		'testchmb_a_05',
		'testchmb_a_06',
		'testchmb_a_07',
		'testchmb_a_08',
		'testchmb_a_09',
		'testchmb_a_10',
		'testchmb_a_11',
		'testchmb_a_13',
		'testchmb_a_14',
		'testchmb_a_15'
	]

	loadedMaps = {}

	async loadMapWithDeps(mapName) {
		const index = this.mapsOrdered.indexOf(mapName)
		if(index === -1) {
			throw new Error(`no such map: ${mapName}`)
		}

		// load past maps and current one
		for(let i = 0; i < index + 1; i++) {
			await this.loadMapCached(this.mapsOrdered[i])
		}

		// schedule next map if it exists
		const next = this.mapsOrdered[index + 1]
		if(next) {
			this.loadMapCached(next)
		}
	}

	async loadMapCached(mapName) {
		if(mapName in this.loadedMaps) return this.loadedMaps[mapName]
		const promise = this.loadMap(mapName)
		this.loadedMaps[mapName] = promise
		return promise
	}

	async setProgress(mapName, progress) {
		if(progress < 1) {
			spinnerElement.style.display = ''
			statusElement.innerText = `Downloading map ${mapName}`
			progressElement.hidden = false
			progressElement.value = progress
		} else {
			spinnerElement.style.display = 'none'
			statusElement.innerText = ''
			progressElement.hidden = true
		}
	}

	async loadMap(mapName) {
		this.setProgress(mapName, 0)

		let resolve, reject
		const promise = new Promise((res, rej) => { resolve = res; reject = rej })

		const xhr = new XMLHttpRequest()
		xhr.responseType = 'arraybuffer'
		xhr.onprogress = e => {
			this.setProgress(mapName, e.loaded / e.total)
		}

		xhr.onerror = () => {
			reject(new Error(`cannot load map ${mapName}`))
		}

		xhr.onload = e => {
			this.setProgress(mapName, 1)
			const dv = new DataView(xhr.response)

			let offset = 0
			
			// data format: { pathLen: uint32le, dataLen: uint32le, path: bytes, blob: bytes }[]
			while(offset < dv.byteLength) {
				const pathLen = dv.getInt32(offset, true)
				const dataLen = dv.getInt32(offset + 4, true)
				const path = new TextDecoder().decode(new DataView(
					dv.buffer,
					offset + 8,
					pathLen
				))
				const blob = new Uint8Array(
					dv.buffer,
					offset + 8 + pathLen,
					dataLen
				)
				offset += 8 + pathLen + dataLen

				const dir = path.replace(/\/[^\/]+$/, '')
				FS.mkdirTree(dir)
				FS.writeFile(path, blob)
			}

			resolve()
		}
		xhr.open('GET', `https://hl2-assets-proxy.hl2-webxr.workers.dev/chunks/${mapName}.data`, true)
		xhr.send()

		return promise
	}
}

const dataLoader = new DataLoader()

Module.downloadMap = (lock, mapName) => {
	console.log('[SKIP-DOWNLOAD] Skipping chunk download for: ' + mapName);
	// Immediately release the lock so the engine proceeds without assets
	Atomics.store(HEAP32, lock, 0)
	Atomics.notify(HEAP32, lock)
}