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
  page.on('console', msg => allLogs.push(`[${msg.type()}] ${msg.text()}`));
  page.on('pageerror', err => allLogs.push(`[ERROR] ${err.message}`));

  console.log('Navigating to http://localhost:8087/index.html ...');
  await page.goto('http://localhost:8087/index.html', { waitUntil: 'domcontentloaded', timeout: 30000 });
  
  // Wait 30s for engine init
  console.log('Waiting 30s for engine init...');
  await page.waitForTimeout(30000);

  // Gather info
  const info = await page.evaluate(() => {
    var info = {};
    info.crossOriginIsolated = window.crossOriginIsolated;
    info.canvasSize = (() => {
      const c = document.getElementById('game-canvas');
      return c ? `${c.width}x${c.height}` : 'null';
    })();
    info.canvasStyle = (() => {
      const c = document.getElementById('game-canvas');
      if (!c) return 'null';
      return `w:${c.style.width} h:${c.style.height} disp:${c.style.display}`;
    })();
    info.loadingStatus = document.getElementById('loading-status')?.textContent || 'null';
    info.moduleExists = typeof Module !== 'undefined';
    info.calledMain = typeof Module !== 'undefined' ? Module.calledMain : false;
    info.runtimeReady = typeof Module !== 'undefined' && Module.calledMain !== undefined;
    
    // Check WASM exports
    if (typeof Module !== 'undefined') {
      info.hasMalloc = typeof Module._malloc === 'function';
      info.hasCallMain = typeof Module.callMain === 'function';
      info.hasDisableAutoRender = typeof Module._Engine_DisableAutoRender === 'function';
      info.hasRenderSingleFrame = typeof Module._Engine_RenderSingleFrame === 'function';
    }
    
    // Check console log
    info.consoleLog = document.getElementById('console-log')?.innerText?.substring(0, 3000) || 'null';
    
    // Check export list
    info.exportList = document.getElementById('export-list')?.innerText?.substring(0, 1000) || 'null';
    
    return info;
  });

  console.log('\n=== ENGINE STATUS ===');
  console.log('crossOriginIsolated:', info.crossOriginIsolated);
  console.log('canvasSize:', info.canvasSize);
  console.log('canvasStyle:', info.canvasStyle);
  console.log('loadingStatus:', info.loadingStatus);
  console.log('moduleExists:', info.moduleExists);
  console.log('calledMain:', info.calledMain);
  console.log('runtimeReady:', info.runtimeReady);
  console.log('hasMalloc:', info.hasMalloc);
  console.log('hasCallMain:', info.hasCallMain);
  console.log('hasDisableAutoRender:', info.hasDisableAutoRender);
  console.log('hasRenderSingleFrame:', info.hasRenderSingleFrame);
  console.log('\n=== CONSOLE LOG ===');
  console.log(info.consoleLog);
  console.log('\n=== EXPORT LIST ===');
  console.log(info.exportList);
  
  console.log('\n=== BROWSER LOGS (last 50) ===');
  allLogs.slice(-50).forEach(l => console.log(l));

  // Take screenshot
  await page.screenshot({ path: '/app/hl2-test/build104_screenshot.png' });
  console.log('\nScreenshot saved to build104_screenshot.png');

  await browser.close();
})();
