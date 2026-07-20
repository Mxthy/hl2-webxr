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
  
  var modSpamCount = 0;
  var allErrors = [];
  page.on('console', msg => {
    const text = msg.text();
    if (text.includes('write path MOD')) modSpamCount++;
    if (text.includes('GL') && !text.includes('DLSYM') && !text.includes('extension') && !text.includes('NOT support') && !text.includes('DISABLED') && !text.includes('NOT AVAIL') && !text.includes('UNAVAIL') && !text.includes('MAX_SAMPLES')) {
      allErrors.push('[' + msg.type() + '] ' + text.substring(0, 200));
    }
    if (text.includes('Engine') || text.includes('render') || text.includes('Render') || text.includes('frame') || text.includes('Frame')) {
      if (!text.includes('DLSYM') && !text.includes('PRE-INIT')) {
        allErrors.push('[' + msg.type() + '] ' + text.substring(0, 200));
      }
    }
  });
  page.on('pageerror', err => allErrors.push('[PAGE_ERROR] ' + err.message.substring(0, 200)));

  console.log('Navigating...');
  await page.goto('http://localhost:8087/index.html', { waitUntil: 'domcontentloaded', timeout: 30000 });
  await page.waitForTimeout(15000);

  // Check GL state in detail
  const glInfo = await page.evaluate(() => {
    var r = {};
    // Check GL module
    r.glExists = typeof GL !== 'undefined';
    r.glContexts = r.glExists ? Object.keys(GL.contexts || {}) : [];
    r.glCurrentContext = r.glExists ? GL.currentContext : null;
    
    // Check offscreenCanvases
    r.offscreenCanvases = r.glExists ? Object.keys(GL.offscreenCanvases || {}) : [];
    
    // Check Module
    r.calledMain = Module.calledMain;
    r.keepRuntimeAlive = typeof Module.keepRuntimeAlive === "function" ? Module.keepRuntimeAlive() : "not a function";
    r.runtimeAlive = typeof runtimeAlive === 'function' ? runtimeAlive() : 'undef';
    
    // Check MainLoop
    r.mainLoopRunning = typeof MainLoop !== 'undefined' ? MainLoop.running : 'undef';
    r.mainLoopFunc = typeof MainLoop !== 'undefined' ? typeof MainLoop.func : 'undef';
    
    // Check wasmExports for render functions
    r.renderFn = Module.wasmExports && typeof Module.wasmExports.Engine_RenderSingleFrame;
    r.disableFn = Module.wasmExports && typeof Module.wasmExports.Engine_DisableAutoRender;
    
    return r;
  });
  
  console.log('\n=== GL STATE ===');
  console.log(JSON.stringify(glInfo, null, 2));
  console.log('\nMOD spam count:', modSpamCount);
  console.log('\nKey logs:');
  allErrors.forEach(e => console.log(e));

  // Try calling Engine_RenderSingleFrame in a loop
  console.log('\n=== RENDER LOOP TEST ===');
  const loopResult = await page.evaluate(() => {
    try {
      var results = [];
      // Disable auto render
      if (Module.wasmExports.Engine_DisableAutoRender) {
        Module.wasmExports.Engine_DisableAutoRender();
        results.push('DisableAutoRender OK');
      }
      // Render 3 frames
      for (var i = 0; i < 3; i++) {
        var ret = Module.wasmExports.Engine_RenderSingleFrame();
        results.push('Frame ' + i + ': ret=' + ret);
      }
      // Check GL after rendering
      results.push('GL contexts after: ' + Object.keys(GL.contexts || {}));
      results.push('GL currentContext: ' + (GL.currentContext ? 'exists' : 'null'));
      return results.join('\n');
    } catch(e) {
      return 'Error: ' + e.message;
    }
  });
  console.log(loopResult);

  await page.screenshot({ path: '/app/hl2-test/gl_test_screenshot.png' });
  console.log('\nScreenshot saved');
  await browser.close();
})();
