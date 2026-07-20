const { chromium } = require('playwright');

(async () => {
  const browser = await chromium.launch({
    args: [
      '--enable-features=SharedArrayBuffer,CrossOriginIsolation',
      '--cross-origin-isolated',
      '--enable-experimental-web-platform-features',
      '--no-sandbox',
      '--disable-gpu',
      '--disable-dev-shm-usage',
    ]
  });
  const context = await browser.newContext({ viewport: { width: 1280, height: 1024 } });
  const page = await context.newPage();
  
  page.on('console', msg => {
    const text = msg.text();
    if (text.includes('Render') || text.includes('Frame') || text.includes('render') ||
        text.includes('frame') || text.includes('Error') || text.includes('error') ||
        text.includes('LOOP') || text.includes('loop') || text.includes('tick') ||
        text.includes('GL') || text.includes('SDL') || text.includes('VGUI') ||
        text.includes('map') || text.includes('Map') || text.includes('MOD') ||
        text.includes('load') || text.includes('Load') || text.includes('PROC') ||
        text.includes('crash') || text.includes('abort') || text.includes('Engine')) {
      console.log('[' + msg.type() + '] ' + text.substring(0, 300));
    }
  });
  page.on('pageerror', err => console.log('[PAGE_ERROR] ' + err.message.substring(0, 200)));

  console.log('Navigating...');
  await page.goto('http://localhost:8087/index.html', { waitUntil: 'domcontentloaded', timeout: 30000 });
  
  // Wait 15s for engine init (main() runs automatically)
  await page.waitForTimeout(15000);

  // Check engine state
  const info = await page.evaluate(() => {
    var r = {};
    r.mainLoopRunning = typeof MainLoop !== 'undefined' ? MainLoop.running : 'undef';
    r.calledMain = Module.calledMain;
    r.hasRender = Module.wasmExports && typeof Module.wasmExports.Engine_RenderSingleFrame === 'function';
    r.hasDisable = Module.wasmExports && typeof Module.wasmExports.Engine_DisableAutoRender === 'function';
    r.hasMalloc = Module.wasmExports && typeof Module.wasmExports.malloc === 'function';
    r.canvasW = document.getElementById('game-canvas') ? document.getElementById('game-canvas').width : 0;
    r.canvasH = document.getElementById('game-canvas') ? document.getElementById('game-canvas').height : 0;
    return r;
  });
  console.log('\n=== ENGINE STATE ===');
  console.log(JSON.stringify(info, null, 2));

  // Try to manually start the render loop
  console.log('\n=== STARTING RENDER LOOP ===');
  const renderResult = await page.evaluate(() => {
    try {
      var results = [];
      
      // Disable auto render first
      if (Module.wasmExports && Module.wasmExports.Engine_DisableAutoRender) {
        Module.wasmExports.Engine_DisableAutoRender();
        results.push('Engine_DisableAutoRender() called');
      }
      
      // Render a single frame
      if (Module.wasmExports && Module.wasmExports.Engine_RenderSingleFrame) {
        var ret = Module.wasmExports.Engine_RenderSingleFrame();
        results.push('Engine_RenderSingleFrame() returned: ' + ret);
      }
      
      // Try malloc
      if (Module.wasmExports && Module.wasmExports.malloc) {
        var ptr = Module.wasmExports.malloc(1024);
        results.push('malloc(1024) = ' + ptr);
        if (ptr) Module.wasmExports.free(ptr);
      }
      
      return results.join('; ');
    } catch(e) {
      return 'Error: ' + e.message + ' / ' + e.stack.substring(0, 200);
    }
  });
  console.log('Render result:', renderResult);

  // Check for any GL calls or canvas changes
  await page.waitForTimeout(5000);
  
  const info2 = await page.evaluate(() => {
    var c = document.getElementById('game-canvas');
    return {
      mainLoopRunning: typeof MainLoop !== 'undefined' ? MainLoop.running : 'undef',
      canvasW: c ? c.width : 0,
      canvasH: c ? c.height : 0,
      hasGL: typeof GL !== 'undefined' && GL.contexts ? Object.keys(GL.contexts).length : 'undef',
    };
  });
  console.log('\n=== AFTER RENDER (5s) ===');
  console.log(JSON.stringify(info2, null, 2));

  await page.screenshot({ path: '/app/hl2-test/render_screenshot.png' });
  console.log('Screenshot saved');
  await browser.close();
})();
