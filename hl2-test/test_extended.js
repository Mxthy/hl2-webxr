const { chromium } = require('playwright');

(async () => {
  const browser = await chromium.launch({
    args: ['--enable-features=SharedArrayBuffer,CrossOriginIsolation', '--cross-origin-isolated', '--no-sandbox', '--disable-gpu', '--disable-dev-shm-usage']
  });
  const page = await (await browser.newContext({ viewport: { width: 1280, height: 1024 } })).newPage();
  
  var renderCount = 0;
  var errorCount = 0;
  var lastErrors = [];
  page.on('console', msg => {
    const text = msg.text();
    if (text.includes('render') || text.includes('Render') || text.includes('frame') || text.includes('Frame')) {
      if (!text.includes('PRE-INIT') && !text.includes('OVERRIDE') && !text.includes('DLSYM')) {
        renderCount++;
      }
    }
    if (msg.type() === 'error') {
      errorCount++;
      if (lastErrors.length < 5) lastErrors.push(text.substring(0, 200));
    }
  });
  page.on('pageerror', err => {
    errorCount++;
    if (lastErrors.length < 5) lastErrors.push('PAGE_ERROR: ' + err.message.substring(0, 200));
  });

  await page.goto('http://localhost:8087/index.html', { waitUntil: 'domcontentloaded', timeout: 30000 });
  
  // Check every 5 seconds for 30 seconds
  for (let i = 0; i < 6; i++) {
    await page.waitForTimeout(5000);
    try {
      const info = await page.evaluate(() => {
        return {
          mainLoopRunning: typeof MainLoop !== 'undefined' ? MainLoop.running : 'undef',
          mainLoopFunc: typeof MainLoop !== 'undefined' ? typeof MainLoop.func : 'undef',
          mainLoopIter: typeof MainLoop !== 'undefined' && MainLoop.iterFunc ? MainLoop.iterFunc.name : 'none',
          calledMain: Module.calledMain,
          loadingStatus: document.getElementById('loading-status') ? document.getElementById('loading-status').textContent.substring(0, 80) : 'null',
          canvasPixels: document.getElementById('game-canvas') ? document.getElementById('game-canvas').toDataURL().length : 0,
        };
      });
      console.log('[' + (i+1)*5 + 's] loop:' + info.mainLoopRunning + ' func:' + info.mainLoopFunc + ' iter:' + info.mainLoopIter + ' canvas:' + info.canvasPixels + ' status:' + info.loadingStatus);
    } catch(e) {
      console.log('[' + (i+1)*5 + 's] eval failed: ' + e.message.substring(0, 100));
      break;
    }
  }
  
  console.log('\nRender-related logs:', renderCount);
  console.log('Errors:', errorCount);
  if (lastErrors.length) {
    console.log('Last errors:');
    lastErrors.forEach(e => console.log('  ' + e));
  }
  
  try {
    await page.screenshot({ path: '/app/hl2-test/extended_screenshot.png' });
    console.log('Screenshot saved');
  } catch(e) {
    console.log('Screenshot failed');
  }
  
  await browser.close();
})();
