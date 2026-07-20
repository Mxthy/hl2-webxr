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
  
  page.on('console', msg => console.log('[' + msg.type() + '] ' + msg.text().substring(0, 300)));
  page.on('pageerror', err => console.log('[PAGE_ERROR] ' + err.message.substring(0, 200)));

  console.log('Navigating...');
  await page.goto('http://localhost:8087/index.html', { waitUntil: 'domcontentloaded', timeout: 30000 });
  
  // Wait 15s for initial load
  await page.waitForTimeout(15000);

  // Check what's available
  const info = await page.evaluate(() => {
    var result = {};
    result.hasCallMain = typeof Module.callMain === 'function';
    result.hasMalloc = typeof Module._malloc === 'function';
    result.calledMain = Module.calledMain;
    result.runtimeReady = Module.runtimeInitialized;
    
    // Check wasmExports
    if (Module.wasmExports) {
      var exports = Object.keys(Module.wasmExports).filter(k => k.includes('em_loop') || k.includes('Engine') || k.includes('Frame') || k.includes('malloc') || k.includes('callMain') || k.includes('main'));
      result.wasmExportKeys = exports.slice(0, 30);
      result.hasEmLoop = !!Module.wasmExports.em_loop_iteration || !!Module.wasmExports._em_loop_iteration;
      result.hasEngineDisable = !!Module.wasmExports.Engine_DisableAutoRender || !!Module.wasmExports._Engine_DisableAutoRender;
      result.hasEngineRender = !!Module.wasmExports.Engine_RenderSingleFrame || !!Module.wasmExports._Engine_RenderSingleFrame;
    }
    
    // Check MainLoop
    if (typeof MainLoop !== 'undefined') {
      result.mainLoopRunning = MainLoop.running;
      result.mainLoopFunc = typeof MainLoop.func;
    }
    
    // Check canvas
    var c = document.getElementById('game-canvas');
    result.canvasSize = c ? c.width + 'x' + c.height : 'null';
    result.canvasStyle = c ? c.style.cssText.substring(0, 100) : 'null';
    
    return result;
  });

  console.log('\n=== ENGINE STATE ===');
  console.log(JSON.stringify(info, null, 2));

  // Try to call callMain
  console.log('\n=== CALLING callMain ===');
  try {
    const mainResult = await page.evaluate(() => {
      try {
        if (Module.calledMain) return 'already called';
        Module.callMain(['-game', 'hl2', '-windowed', '-novid']);
        return 'callMain returned';
      } catch(e) {
        return 'callMain error: ' + e.message;
      }
    });
    console.log('callMain result:', mainResult);
  } catch(e) {
    console.log('Failed to call callMain:', e.message);
  }

  // Wait 10s and check again
  await page.waitForTimeout(10000);
  
  const info2 = await page.evaluate(() => {
    var result = {};
    result.calledMain = Module.calledMain;
    result.mainLoopRunning = typeof MainLoop !== 'undefined' ? MainLoop.running : 'undef';
    result.loadingStatus = document.getElementById('loading-status') ? document.getElementById('loading-status').textContent : 'null';
    return result;
  });
  console.log('\n=== AFTER callMain (10s) ===');
  console.log(JSON.stringify(info2, null, 2));

  await page.screenshot({ path: '/app/hl2-test/start_screenshot.png' });
  console.log('Screenshot saved');
  await browser.close();
})();
