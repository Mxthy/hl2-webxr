const { chromium } = require('playwright');

(async () => {
  const browser = await chromium.launch({
    headless: true,
    args: [
      '--enable-features=SharedArrayBuffer,CrossOriginIsolation',
      '--cross-origin-isolated',
      '--no-sandbox',
      '--use-gl=swiftshader',
      '--enable-webgl',
      '--ignore-gpu-blocklist',
    ]
  });
  const page = await browser.newPage();
  
  const logs = [];
  page.on('console', msg => logs.push(`[${msg.type()}] ${msg.text()}`));
  page.on('pageerror', err => logs.push(`[PAGE_ERROR] ${err.message}`));
  
  console.log('=== Build #94 Test — Navigating to localhost:8087 ===');
  await page.goto('http://localhost:8087/index.html', { waitUntil: 'domcontentloaded', timeout: 30000 });
  
  // Wait 120s for engine init + chunk loading
  console.log('Waiting 120s for engine init + chunk loading...');
  for (let i = 0; i < 12; i++) {
    await page.waitForTimeout(10000);
    const status = await page.evaluate(() => document.getElementById('status')?.textContent || 'no status').catch(() => 'eval failed');
    const canvas = await page.evaluate(() => ({ w: document.getElementById('game-canvas')?.width || 0, h: document.getElementById('game-canvas')?.height || 0 })).catch(() => ({w:0,h:0}));
    console.log(`  ${(i+1)*10}s: status="${status}" canvas=${canvas.w}x${canvas.h} logs=${logs.length}`);
  }
  
  // Check engine state
  const info = await page.evaluate(() => {
    return {
      crossOriginIsolated: crossOriginIsolated,
      runtimeReady: typeof Module !== 'undefined' && typeof Module._Engine_DisableAutoRender === 'function',
      statusText: document.getElementById('status')?.textContent || '',
      exportList: document.getElementById('export-list')?.innerHTML || 'no list',
      canvasW: document.getElementById('game-canvas')?.width || 0,
      canvasH: document.getElementById('game-canvas')?.height || 0,
      logCount: logs?.length || 0,
    };
  }).catch(e => ({ error: e.message }));
  
  console.log('\n=== Engine Info ===');
  console.log(JSON.stringify(info, null, 2));
  
  // Print all unique logs
  console.log('\n=== All Logs (' + logs.length + ' total) ===');
  const unique = [...new Set(logs)];
  unique.forEach(l => console.log(l));
  
  // Try bridge test
  console.log('\n=== Bridge Test ===');
  const bridge = await page.evaluate(() => {
    try {
      if (typeof Module === 'undefined') return 'Module undefined';
      if (typeof Module._Engine_DisableAutoRender === 'function') {
        Module._Engine_DisableAutoRender();
        return 'SUCCESS — _Engine_DisableAutoRender called';
      }
      return 'Function not found on Module';
    } catch (e) {
      return 'CRASH: ' + e.message;
    }
  }).catch(e => 'EVAL ERROR: ' + e.message);
  console.log(bridge);
  
  await page.screenshot({ path: 'build94b_screenshot.png' });
  console.log('\nScreenshot saved');
  
  await browser.close();
  console.log('=== Test Complete ===');
})();
