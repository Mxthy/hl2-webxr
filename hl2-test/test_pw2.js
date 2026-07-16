const { chromium } = require('playwright');

(async () => {
  const browser = await chromium.launch({
    headless: true,
    args: [
      '--enable-features=SharedArrayBuffer',
      '--enable-unsafe-swiftshader',
      '--use-gl=swiftshader',
      '--enable-webgl',
      '--ignore-gpu-blocklist',
      '--enable-gpu-rasterization',
    ]
  });
  
  const context = await browser.newContext({
    viewport: { width: 1280, height: 800 },
  });
  
  const page = await context.newPage();
  
  // Capture console output from page AND workers
  page.on('console', msg => {
    const text = msg.text();
    console.log(`[BROWSER] [${msg.type()}] ${text}`);
  });
  page.on('pageerror', err => {
    console.log(`[BROWSER PAGE ERROR] ${err.message}`);
  });
  
  // Also capture worker console output
  page.on('worker', worker => {
    console.log(`[WORKER] Worker created: ${worker.url()}`);
    worker.on('console', msg => {
      console.log(`[WORKER-CONSOLE] [${msg.type()}] ${msg.text()}`);
    });
    worker.on('pageerror', err => {
      console.log(`[WORKER-ERROR] ${err.message}`);
    });
  });
  
  console.log('Navigating to test page...');
  await page.goto('https://hl2-webxr.pages.dev/test_console.html', {
    waitUntil: 'domcontentloaded',
    timeout: 30000
  });
  
  console.log('Page loaded, waiting for engine to initialize...');
  
  // Wait for up to 2 minutes
  for (let i = 0; i < 24; i++) {
    await page.waitForTimeout(5000);
    const title = await page.title().catch(() => 'ERROR');
    console.log(`\n=== Check ${i+1} (${(i+1)*5}s) ===`);
    console.log(`Title: ${title.substring(0, 500)}`);
    
    if (title.includes('CALLMAIN') || title.includes('Runtime initialized') || title.includes('ERR') || title.includes('ABORT')) {
      console.log('Engine reached a key state, waiting more...');
      await page.waitForTimeout(20000);
      const finalLog = await page.evaluate(() => document.getElementById('log')?.textContent || '').catch(() => 'ERROR');
      console.log(`\n=== FINAL LOG ===\n${finalLog}`);
      break;
    }
  }
  
  const finalLog = await page.evaluate(() => document.getElementById('log')?.textContent || '').catch(() => 'ERROR');
  console.log(`\n=== FINAL FULL LOG ===\n${finalLog}`);
  
  await browser.close();
  process.exit(0);
})().catch(e => {
  console.error('Fatal error:', e);
  process.exit(1);
});
