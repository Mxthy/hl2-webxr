const { chromium } = require('playwright');
(async () => {
  const browser = await chromium.launch({
    args: ['--enable-features=SharedArrayBuffer,CrossOriginIsolation','--cross-origin-isolated','--no-sandbox','--disable-gpu','--disable-dev-shm-usage']
  });
  const page = await (await browser.newContext({viewport:{width:1280,height:1024}})).newPage();
  page.on('console', m => {
    const t = m.text();
    if (t.includes('RUNNER') || t.includes('EM-LOOP') || t.includes('runIter') ||
        t.includes('SET-MAIN') || t.includes('POST-EXIT') || t.includes('WORKER]'))
      console.log('['+m.type()+'] '+t.substring(0,250));
  });
  page.on('pageerror', e => console.log('[PAGE_ERROR] ' + e.message.substring(0,200)));
  await page.goto('http://localhost:8087/index.html', {waitUntil:'domcontentloaded',timeout:30000});
  await page.waitForTimeout(15000);
  const st = await page.evaluate(() => ({
    loop: typeof MainLoop!=='undefined'?MainLoop.running:'undef',
    runnerCount: MainLoop.__runnerCount || 0,
    emLoopCount: typeof __emLoopCount!=='undefined'?__emLoopCount:'undef',
  }));
  console.log('\n=== STATE ===');
  console.log(JSON.stringify(st,null,2));
  await browser.close();
})();
