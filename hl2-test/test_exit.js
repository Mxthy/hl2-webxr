const { chromium } = require('playwright');

(async () => {
  const browser = await chromium.launch({
    args: ['--enable-features=SharedArrayBuffer,CrossOriginIsolation', '--cross-origin-isolated', '--no-sandbox', '--disable-gpu', '--disable-dev-shm-usage']
  });
  const page = await (await browser.newContext({ viewport: { width: 1280, height: 1024 } })).newPage();
  
  page.on('console', msg => {
    const text = msg.text();
    if (text.includes('EXIT') || text.includes('exit') || text.includes('WORKER') || 
        text.includes('POST-EXIT') || text.includes('SIGTRAP') || text.includes('main') ||
        text.includes('Main') || text.includes('loop') || text.includes('Loop') ||
        text.includes('SET-MAIN') || text.includes('EM-LOOP')) {
      console.log('[' + msg.type() + '] ' + text.substring(0, 250));
    }
  });
  page.on('pageerror', err => console.log('[PAGE_ERROR] ' + err.message.substring(0, 250)));

  await page.goto('http://localhost:8087/index.html', { waitUntil: 'domcontentloaded', timeout: 30000 });
  await page.waitForTimeout(20000);
  await browser.close();
})();
