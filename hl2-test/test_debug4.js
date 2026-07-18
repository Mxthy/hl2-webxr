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
  
  // Wait 40s — allows 30s chunk timeout + 10s for engine init
  console.log('Waiting 40s for engine init + chunk timeout...');
  await page.waitForTimeout(40000);

  // Get status
  const info = await page.evaluate(() => {
    var info = {};
    info.crossOriginIsolated = window.crossOriginIsolated;
    info.statusText = document.getElementById('status')?.textContent || 'null';
    info.logHTML = document.getElementById('log')?.innerHTML?.substring(0, 3000) || 'null';
    info.moduleKeys = typeof Module !== 'undefined' ? Object.keys(Module).filter(k => 
      k.indexOf('Engine') >= 0 || k.indexOf('Disable') >= 0 || k.indexOf('Render') >= 0 || 
      k.indexOf('Camera') >= 0 || k.indexOf('ccall') >= 0 || k.indexOf('cwrap') >= 0 || 
      k.indexOf('wasm') >= 0 || k.indexOf('callMain') >= 0 || k.indexOf('calledMain') >= 0
    ) : [];
    info.calledMain = typeof Module !== 'undefined' ? Module.calledMain : false;
    return info;
  });

  // Print filtered logs (no null.style spam)
  console.log('\n=== Console Logs (' + allLogs.length + ' total) ===');
  allLogs.filter(l => !l.includes('Cannot read properties')).forEach(l => console.log(l));

  console.log('\n=== Info ===');
  console.log(JSON.stringify(info, null, 2));

  await browser.close();
})();
