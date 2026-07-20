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
  
  var modSpam = 0, frameLogs = 0, renderLogs = [];
  page.on('console', msg => {
    const text = msg.text();
    if (text.includes('write path MOD')) modSpam++;
    else if (text.includes('SET-MAIN-LOOP') || text.includes('EM-LOOP') || text.includes('Render') || text.includes('Frame') || text.includes('render')) {
      frameLogs++;
      if (renderLogs.length < 10) renderLogs.push('[' + msg.type() + '] ' + text.substring(0, 200));
    }
  });
  page.on('pageerror', err => console.log('[PAGE_ERROR] ' + err.message.substring(0, 200)));

  console.log('Navigating...');
  await page.goto('http://localhost:8087/index.html', { waitUntil: 'domcontentloaded', timeout: 30000 });
  
  // Wait 20s for engine to init + main loop to start
  console.log('Waiting 20s for engine init...');
  await page.waitForTimeout(20000);

  // Check state
  const info = await page.evaluate(() => {
    return {
      mainLoopRunning: typeof MainLoop !== 'undefined' ? MainLoop.running : 'undef',
      mainLoopFunc: typeof MainLoop !== 'undefined' ? typeof MainLoop.func : 'undef',
      calledMain: Module.calledMain,
      hasRender: Module.wasmExports && typeof Module.wasmExports.Engine_RenderSingleFrame === 'function',
    };
  });
  console.log('\n=== STATE AFTER 20s ===');
  console.log(JSON.stringify(info, null, 2));
  console.log('MOD spam:', modSpam);
  console.log('Render/frame logs:', frameLogs);
  renderLogs.forEach(l => console.log(l));

  // Take screenshot
  try {
    await page.screenshot({ path: '/app/hl2-test/loop_screenshot.png' });
    console.log('Screenshot saved');
  } catch(e) {
    console.log('Screenshot failed');
  }

  await browser.close();
})();
