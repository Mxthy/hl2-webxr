const { chromium } = require('playwright');
(async () => {
  const browser = await chromium.launch({
    args: ['--enable-features=SharedArrayBuffer,CrossOriginIsolation','--cross-origin-isolated','--no-sandbox','--disable-dev-shm-usage','--use-gl=swiftshader']
  });
  const page = await browser.newPage({ viewport: { width: 1280, height: 1024 } });
  const allLogs = [];
  page.on('console', msg => allLogs.push(`[${msg.type()}] ${msg.text()}`));
  page.on('pageerror', err => allLogs.push(`[ERROR] ${err.message}`));
  page.on('requestfailed', req => allLogs.push(`[FAIL] ${req.url()} — ${req.failure()?.errorText}`));

  await page.goto('http://localhost:8087/index.html', { waitUntil: 'domcontentloaded', timeout: 30000 });
  await page.waitForTimeout(15000);

  console.log(`=== ALL Logs (${allLogs.length}) ===`);
  allLogs.forEach(l => console.log(l));
  
  // Check what the page looks like
  const info = await page.evaluate(() => ({
    title: document.title,
    bodyText: document.body?.innerText?.substring(0, 500),
    scripts: [...document.querySelectorAll('script')].map(s => s.src),
    canvas: document.getElementById('canvas') ? 'found' : 'not found',
  }));
  console.log('\n=== Page Info ===');
  console.log(JSON.stringify(info, null, 2));
  
  await browser.close();
})();
