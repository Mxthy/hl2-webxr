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

  console.log('Navigating...');
  await page.goto('http://localhost:8087/index.html', { waitUntil: 'domcontentloaded', timeout: 30000 });
  
  // Wait 45s for engine init
  console.log('Waiting 45s...');
  await page.waitForTimeout(45000);

  // Gather info
  const info = await page.evaluate(() => {
    var info = {};
    info.crossOriginIsolated = window.crossOriginIsolated;
    info.canvasSize = (() => {
      const c = document.getElementById('game-canvas');
      return c ? `${c.width}x${c.height}` : 'null';
    })();
    info.loadingStatus = document.getElementById('loading-status')?.textContent || 'null';
    info.moduleExists = typeof Module !== 'undefined';
    info.calledMain = typeof Module !== 'undefined' ? Module.calledMain : false;
    info.hasCallMain = typeof Module !== 'undefined' && typeof Module.callMain === 'function';
    info.hasMalloc = typeof Module !== 'undefined' && typeof Module._malloc === 'function';
    info.hasDisableAutoRender = typeof Module !== 'undefined' && typeof Module._Engine_DisableAutoRender === 'function';
    info.consoleLog = document.getElementById('console-log')?.innerText?.substring(0, 5000) || 'null';
    info.exportList = document.getElementById('export-list')?.innerText?.substring(0, 2000) || 'null';
    // Check MainLoop
    if (typeof Module !== 'undefined') {
      info.mainLoopFunc = typeof Module.MainLoop !== 'undefined' ? typeof Module.MainLoop.func : 'no MainLoop';
    }
    return info;
  });

  console.log('\n=== ENGINE STATUS ===');
  console.log('crossOriginIsolated:', info.crossOriginIsolated);
  console.log('canvasSize:', info.canvasSize);
  console.log('loadingStatus:', info.loadingStatus);
  console.log('moduleExists:', info.moduleExists);
  console.log('calledMain:', info.calledMain);
  console.log('hasCallMain:', info.hasCallMain);
  console.log('hasMalloc:', info.hasMalloc);
  console.log('hasDisableAutoRender:', info.hasDisableAutoRender);
  console.log('mainLoopFunc:', info.mainLoopFunc);
  console.log('\n=== CONSOLE LOG (UI) ===');
  console.log(info.consoleLog);
  console.log('\n=== EXPORT LIST ===');
  console.log(info.exportList);
  
  console.log('\n=== BROWSER LOGS (last 60) ===');
  allLogs.slice(-60).forEach(l => console.log(l));

  await page.screenshot({ path: '/app/hl2-test/build104b_screenshot.png' });
  console.log('\nScreenshot saved');
  await browser.close();
})();
