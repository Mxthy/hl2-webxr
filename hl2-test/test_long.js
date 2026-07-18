const { chromium } = require('playwright');
(async () => {
  const browser = await chromium.launch({
    args: ['--enable-features=SharedArrayBuffer,CrossOriginIsolation','--cross-origin-isolated','--no-sandbox','--disable-dev-shm-usage','--use-gl=swiftshader']
  });
  const page = await browser.newPage({ viewport: { width: 1280, height: 1024 } });
  const allLogs = [];
  page.on('console', msg => {
    const t = msg.text();
    if (!t.includes('GOT stub') && !t.includes('registerOrRemove')) {
      allLogs.push(`[${msg.type()}] ${t.substring(0, 200)}`);
    }
  });
  page.on('pageerror', err => allLogs.push(`[ERROR] ${err.message.substring(0, 200)}`));
  page.on('requestfailed', req => allLogs.push(`[FAIL] ${req.url()} — ${req.failure()?.errorText}`));

  await page.goto('http://localhost:8087/index.html', { waitUntil: 'domcontentloaded', timeout: 30000 });
  
  console.log('Waiting 90s for engine init...');
  await page.waitForTimeout(90000);

  console.log(`\n=== Filtered Logs (${allLogs.length}) ===`);
  allLogs.forEach(l => console.log(l));
  
  const info = await page.evaluate(() => ({
    title: document.title,
    status: document.getElementById('status')?.textContent,
    bodyText: document.body?.innerText?.substring(0, 800),
    canvas: (() => {
      const c = document.getElementById('canvas') || document.getElementById('game-canvas');
      return c ? { w: c.width, h: c.height, id: c.id } : null;
    })(),
    hasModule: typeof Module !== 'undefined',
    callMainExists: typeof Module !== 'undefined' && typeof Module.callMain === 'function',
    moduleReady: typeof Module !== 'undefined' && typeof Module._main !== 'undefined',
    exports: typeof Module !== 'undefined' && Module.wasmExports ? Object.keys(Module.wasmExports).filter(k => k.startsWith('Engine_') || k === '_malloc' || k === '_main' || k === 'callMain') : 'no wasmExports',
  }));
  console.log('\n=== Engine Info ===');
  console.log(JSON.stringify(info, null, 2));
  
  await page.screenshot({ path: 'long_screenshot.png' });
  console.log('\nScreenshot saved: long_screenshot.png');
  
  await browser.close();
})();
