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
  
  page.on('console', msg => {
    const text = msg.text();
    if (text.includes('RAISE') || text.includes('SIDE') || text.includes('SIGTRAP') || 
        text.includes('Error') || text.includes('error') || text.includes('ABORT') ||
        text.includes('loaded') || text.includes('module') || text.includes('dylib') ||
        text.includes('Runtime') || text.includes('ready') || text.includes('POST') ||
        text.includes('UNWIND') || text.includes('malloc') || text.includes('Frame') ||
        text.includes('crash') || text.includes('trap') || text.includes('abort')) {
      console.log('[' + msg.type() + '] ' + text.substring(0, 200));
    }
  });
  page.on('pageerror', err => console.log('[PAGE_ERROR] ' + err.message.substring(0, 200)));
  page.on('requestfailed', req => {
    if (!req.url().includes('tailwindcss')) console.log('[REQ_FAIL] ' + req.url());
  });

  console.log('Navigating...');
  await page.goto('http://localhost:8087/index.html', { waitUntil: 'domcontentloaded', timeout: 30000 });
  
  for (let i = 0; i < 6; i++) {
    await page.waitForTimeout(5000);
    try {
      const info = await page.evaluate(() => {
        return {
          hasCallMain: typeof Module !== 'undefined' && typeof Module.callMain === 'function',
          hasMalloc: typeof Module !== 'undefined' && typeof Module._malloc === 'function',
          calledMain: typeof Module !== 'undefined' ? Module.calledMain : false,
          loadingStatus: document.getElementById('loading-status') ? document.getElementById('loading-status').textContent.substring(0, 100) : 'null',
          mainLoopRunning: typeof MainLoop !== 'undefined' ? MainLoop.running : 'undef',
        };
      });
      console.log('[' + (i+1)*5 + 's] callMain:' + info.hasCallMain + ' malloc:' + info.hasMalloc + ' calledMain:' + info.calledMain + ' status:' + info.loadingStatus + ' loop:' + info.mainLoopRunning);
    } catch(e) {
      console.log('[' + (i+1)*5 + 's] Page eval failed: ' + e.message.substring(0, 100));
      break;
    }
  }

  try {
    await page.screenshot({ path: '/app/hl2-test/crash_screenshot.png' });
    console.log('Screenshot saved');
  } catch(e) {
    console.log('Screenshot failed (page may have crashed)');
  }
  
  await browser.close();
})();
