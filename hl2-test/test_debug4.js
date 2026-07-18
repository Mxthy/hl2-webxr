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
  const allLogs = [];
  page.on('console', msg => allLogs.push(`[${msg.type()}] ${msg.text()}`));
  page.on('pageerror', err => allLogs.push(`[ERROR] ${err.message}`));

  console.log('Navigating...');
  await page.goto('http://localhost:8080/index.html', { waitUntil: 'domcontentloaded', timeout: 30000 });
  
  // Wait 45s
  console.log('Waiting 45s...');
  await page.waitForTimeout(45000);

  // Check if we can call main
  const info = await page.evaluate(() => {
    var info = {};
    info.crossOriginIsolated = window.crossOriginIsolated;
    info.runtimeReady = typeof Module !== 'undefined' && Module.calledMain !== undefined;
    info.calledMain = typeof Module !== 'undefined' ? Module.calledMain : false;
    info.statusText = document.getElementById('status')?.textContent || 'null';
    info.logHTML = document.getElementById('log')?.innerHTML?.substring(0, 5000) || 'null';
    
    // Try to call main if not called yet
    if (typeof Module !== 'undefined' && !Module.calledMain && typeof Module.callMain === 'function') {
      try {
        info.callMainResult = 'attempted';
        Module.callMain(['-game', 'hl2', '-windowed', '-w', '1280', '-h', '800', '-novid', '-noip']);
        info.callMainResult = 'success';
      } catch (e) {
        info.callMainResult = 'error: ' + e.message;
      }
    }
    
    return info;
  });

  // Wait another 10s after callMain attempt
  await page.waitForTimeout(10000);

  // Print filtered logs
  console.log('\n=== Console Logs (' + allLogs.length + ' total, filtered) ===');
  allLogs.filter(l => 
    !l.includes('Cannot read properties') && 
    !l.includes('still waiting') && 
    !l.includes('(end of list)') &&
    !l.includes('dependency:')
  ).forEach(l => console.log(l));

  console.log('\n=== Info ===');
  console.log(JSON.stringify(info, null, 2));

  // Get final logs after callMain
  const finalLogs = await page.evaluate(() => ({
    logHTML: document.getElementById('log')?.innerHTML?.substring(0, 5000) || 'null',
    calledMain: typeof Module !== 'undefined' ? Module.calledMain : false,
  }));
  console.log('\n=== Final ===');
  console.log(JSON.stringify(finalLogs, null, 2));

  await browser.close();
})();
