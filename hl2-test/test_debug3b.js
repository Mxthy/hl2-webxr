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
  await page.goto('http://localhost:8080/index.html', { waitUntil: 'domcontentloaded', timeout: 30000 });
  await page.waitForTimeout(20000);

  // Check what's happening — get ALL console logs
  console.log('\n=== ALL Console Logs (' + allLogs.length + ' total) ===');
  allLogs.forEach(l => console.log(l));

  // Check if onRuntimeInitialized fired
  const info = await page.evaluate(() => {
    var info = {};
    info.crossOriginIsolated = window.crossOriginIsolated;
    info.moduleReady = typeof Module !== 'undefined' && typeof Module._Engine_DisableAutoRender === 'function';
    info.runtimeReady = typeof Module !== 'undefined' && typeof Module.onRuntimeInitialized === 'function';
    info.calledMain = typeof Module !== 'undefined' && Module.calledMain;
    info.statusText = document.getElementById('status')?.textContent || 'null';
    info.logHTML = document.getElementById('log')?.innerHTML?.substring(0, 2000) || 'null';
    // Check what null.style errors are about
    info.statusElement = typeof statusElement !== 'undefined' ? (statusElement ? 'exists' : 'null') : 'undefined';
    info.progressElement = typeof progressElement !== 'undefined' ? (progressElement ? 'exists' : 'null') : 'undefined';
    info.spinnerElement = typeof spinnerElement !== 'undefined' ? (spinnerElement ? 'exists' : 'null') : 'undefined';
    return info;
  });
  console.log('\n=== Info ===');
  console.log(JSON.stringify(info, null, 2));

  await browser.close();
})();
