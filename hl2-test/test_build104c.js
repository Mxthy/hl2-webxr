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
  const allLogs = [];
  
  // Capture ALL console messages from the very start
  page.on('console', msg => {
    const text = msg.text();
    allLogs.push(`[${msg.type()}] ${text}`);
    // Print immediately for real-time monitoring
    if (msg.type() === 'error' || msg.type() === 'warning' || text.includes('SIGTRAP') || text.includes('ESCAPE') || text.includes('SIDE') || text.includes('loaded') || text.includes('merge') || text.includes('error') || text.includes('Error') || text.includes('wasm')) {
      console.log(`[${msg.type()}] ${text}`);
    }
  });
  page.on('pageerror', err => {
    allLogs.push(`[PAGE_ERROR] ${err.message}`);
    console.log(`[PAGE_ERROR] ${err.message}`);
  });
  page.on('requestfailed', req => {
    console.log(`[REQ_FAIL] ${req.url()} - ${req.failure()?.errorText}`);
  });

  console.log('Navigating...');
  await page.goto('http://localhost:8087/index.html', { waitUntil: 'domcontentloaded', timeout: 30000 });
  
  // Wait 60s and collect logs
  console.log('Waiting 60s...');
  await page.waitForTimeout(60000);

  // Get detailed info
  const info = await page.evaluate(() => {
    var info = {};
    info.crossOriginIsolated = window.crossOriginIsolated;
    
    // Check Module state
    if (typeof Module !== 'undefined') {
      info.calledMain = Module.calledMain;
      info.hasCallMain = typeof Module.callMain === 'function';
      info.hasMalloc = typeof Module._malloc === 'function';
      info.dynamicLibraries = Module.dynamicLibraries ? Module.dynamicLibraries.length : 0;
      info.preRunListeners = Module.preRun ? Module.preRun.length : 0;
      info.postRunListeners = Module.postRun ? Module.postRun.length : 0;
      info.runtimeInitialized = Module.runtimeInitialized;
      
      // Check run dependencies
      info.runDependencies = typeof runDependencies !== 'undefined' ? runDependencies : 'undef';
      
      // Check MainLoop
      if (typeof MainLoop !== 'undefined') {
        info.mainLoopFunc = typeof MainLoop.func;
        info.mainLoopRunning = MainLoop.running;
      }
    }
    
    return info;
  });

  console.log('\n=== DETAILED STATUS ===');
  console.log(JSON.stringify(info, null, 2));
  
  console.log('\n=== ALL LOGS (first 80) ===');
  allLogs.slice(0, 80).forEach(l => console.log(l));
  
  console.log('\n=== ALL LOGS (last 30) ===');
  allLogs.slice(-30).forEach(l => console.log(l));
  
  console.log('\nTotal logs:', allLogs.length);

  await page.screenshot({ path: '/app/hl2-test/build104c_screenshot.png' });
  await browser.close();
})();
