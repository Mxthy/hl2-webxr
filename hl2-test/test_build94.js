const { chromium } = require('playwright');

(async () => {
  const browser = await chromium.launch({
    args: [
      '--enable-features=SharedArrayBuffer,CrossOriginIsolation',
      '--cross-origin-isolated',
      '--no-sandbox',
      '--disable-dev-shm-usage',
      '--use-gl=swiftshader',
    ]
  });
  const context = await browser.newContext({ viewport: { width: 1280, height: 1024 } });
  const page = await context.newPage();
  const allLogs = [];
  page.on('console', msg => allLogs.push(`[${msg.type()}] ${msg.text()}`));
  page.on('pageerror', err => allLogs.push(`[ERROR] ${err.message}`));

  console.log('=== Build #94 Test — Navigating to localhost:8086 ===');
  await page.goto('http://localhost:8086/index.html', { waitUntil: 'domcontentloaded', timeout: 30000 });
  
  console.log('Waiting 50s for engine init...');
  await page.waitForTimeout(50000);

  // Check engine status
  const info = await page.evaluate(() => {
    return {
      crossOriginIsolated: window.crossOriginIsolated,
      runtimeReady: typeof Module !== 'undefined',
      calledMain: typeof Module !== 'undefined' ? Module.calledMain : false,
      statusText: document.getElementById('loading-status')?.textContent || 'null',
      logHTML: document.getElementById('console-log')?.innerHTML?.substring(0, 3000) || 'null',
      exportList: document.getElementById('export-list')?.textContent?.substring(0, 1000) || 'null',
      canvasW: document.getElementById('game-canvas')?.width || 0,
      canvasH: document.getElementById('game-canvas')?.height || 0,
    };
  });

  // Try the bridge test — DisableAutoRender
  console.log('\n=== Bridge Test: _Engine_DisableAutoRender ===');
  const bridgeResult = await page.evaluate(() => {
    try {
      if (typeof Module !== 'undefined' && Module._Engine_DisableAutoRender) {
        Module._Engine_DisableAutoRender();
        return 'SUCCESS — _Engine_DisableAutoRender called without crash';
      }
      return 'HOOK NOT FOUND — Module._Engine_DisableAutoRender missing';
    } catch (e) {
      return 'CRASH: ' + e.message;
    }
  });

  // Wait 5s after bridge test
  await page.waitForTimeout(5000);

  // Take screenshot
  await page.screenshot({ path: '/app/hl2-test/build94_screenshot.png' });
  console.log('Screenshot saved to build94_screenshot.png');

  // Print logs — filter for key messages
  console.log('\n=== Console Logs (' + allLogs.length + ' total) ===');
  const keyLogs = allLogs.filter(l => 
    l.includes('ENGINE RUNTIME') || l.includes('Ready') || l.includes('error') ||
    l.includes('Error') || l.includes('WARN') || l.includes('null function') ||
    l.includes('stack') || l.includes('IVP') || l.includes('SDL') ||
    l.includes('canvas') || l.includes('transfer') || l.includes('abort') ||
    l.includes('callMain') || l.includes('Debug') || l.includes('MISSING') ||
    l.includes('LoadLibrary') || l.includes('UTF-8') || l.includes('pthread')
  );
  keyLogs.forEach(l => console.log(l));

  console.log('\n=== Engine Info ===');
  console.log(JSON.stringify(info, null, 2));
  
  console.log('\n=== Bridge Result ===');
  console.log(bridgeResult);

  // Check for IVP warnings
  const ivpWarnings = allLogs.filter(l => l.includes('IVP_Compact_Edge') || l.includes('next_table'));
  console.log('\n=== IVP Warnings ===');
  console.log(ivpWarnings.length === 0 ? 'NONE — IVP_Compact_Edge symbols properly resolved! ✅' : 
    ivpWarnings.slice(0, 5).join('\n'));

  // Check for null function errors
  const nullFuncErrors = allLogs.filter(l => l.includes('null function'));
  console.log('\n=== Null Function Errors ===');
  console.log(nullFuncErrors.length === 0 ? 'NONE — No null function RuntimeErrors! ✅' : 
    nullFuncErrors.slice(0, 3).join('\n'));

  // Check for canvas transfer errors
  const canvasErrors = allLogs.filter(l => l.includes('transfer canvas') || l.includes('canvas'));
  console.log('\n=== Canvas Transfer ===');
  console.log(canvasErrors.length === 0 ? 'No canvas transfer errors ✅' : 
    canvasErrors.slice(0, 5).join('\n'));

  await browser.close();
  console.log('\n=== Test Complete ===');
})();
