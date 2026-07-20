const { chromium } = require('playwright');

(async () => {
  const browser = await chromium.launch({
    args: ['--enable-features=SharedArrayBuffer,CrossOriginIsolation', '--cross-origin-isolated', '--no-sandbox', '--disable-gpu', '--disable-dev-shm-usage']
  });
  const page = await (await browser.newContext({ viewport: { width: 1280, height: 1024 } })).newPage();
  
  var allLogs = [];
  page.on('console', msg => {
    const text = msg.text();
    if (text.includes('EXIT') || text.includes('exit') || text.includes('WORKER') ||
        text.includes('POST') || text.includes('SIGTRAP') || text.includes('Main') ||
        text.includes('main') || text.includes('Loop') || text.includes('loop') ||
        text.includes('SET') || text.includes('EM') || text.includes('render') ||
        text.includes('Render') || text.includes('error') || text.includes('Error') ||
        text.includes('abort') || text.includes('Abort') || text.includes('stack') ||
        text.includes('Stack') || text.includes('Frame') || text.includes('frame')) {
      if (!text.includes('PRE-INIT') && !text.includes('OVERRIDE') && !text.includes('DLSYM')) {
        allLogs.push('[' + msg.type() + '] ' + text.substring(0, 300));
      }
    }
  });
  page.on('pageerror', err => allLogs.push('[PAGE_ERROR] ' + err.message.substring(0, 300) + (err.stack ? ' | STACK: ' + err.stack.substring(0, 300) : '')));

  console.log('Navigating...');
  await page.goto('http://localhost:8087/index.html', { waitUntil: 'domcontentloaded', timeout: 30000 });
  await page.waitForTimeout(15000);
  
  // Check main loop state
  const state = await page.evaluate(() => {
    return {
      mainLoopRunning: typeof MainLoop !== 'undefined' ? MainLoop.running : 'undef',
      calledMain: Module.calledMain,
    };
  });
  console.log('\n=== STATE ===');
  console.log(JSON.stringify(state));
  console.log('\n=== ALL LOGS ===');
  allLogs.forEach(l => console.log(l));
  
  await browser.close();
})();
