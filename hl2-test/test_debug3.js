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

  const context = await browser.newContext({
    viewport: { width: 1280, height: 1024 }
  });

  const page = await context.newPage();

  // Collect console messages
  const logs = [];
  page.on('console', msg => {
    logs.push(`[${msg.type()}] ${msg.text()}`);
  });
  page.on('pageerror', err => {
    logs.push(`[ERROR] ${err.message}`);
  });

  console.log('Navigating to localhost:8080...');
  await page.goto('http://localhost:8080/index.html', {
    waitUntil: 'domcontentloaded',
    timeout: 30000
  });

  // Wait for engine init
  console.log('Waiting 15s for engine init...');
  await page.waitForTimeout(15000);

  // Check if engine ready
  const status = await page.evaluate(() => {
    return {
      crossOriginIsolated: window.crossOriginIsolated,
      statusText: document.getElementById('status')?.textContent,
      buttons: {
        testBridge: !document.getElementById('btnTestBridge')?.disabled,
        checkExports: !document.getElementById('btnCheckExports')?.disabled,
      },
      moduleExists: typeof Module !== 'undefined',
      moduleKeys: typeof Module !== 'undefined' ? Object.keys(Module).filter(k => 
        k.indexOf('Engine') >= 0 || k.indexOf('Disable') >= 0 || k.indexOf('Render') >= 0 || k.indexOf('Camera') >= 0 || k.indexOf('ccall') >= 0 || k.indexOf('cwrap') >= 0 || k.indexOf('wasm') >= 0
      ) : [],
    };
  });

  console.log('=== Page Status ===');
  console.log(JSON.stringify(status, null, 2));

  // If test bridge button is enabled, click it
  if (status.buttons.testBridge) {
    console.log('\nClicking Test Bridge button...');
    await page.click('#btnTestBridge');
    await page.waitForTimeout(2000);
  }

  // If check exports button is enabled, click it
  if (status.buttons.checkExports) {
    console.log('Clicking Check Exports button...');
    await page.click('#btnCheckExports');
    await page.waitForTimeout(2000);
  }

  // Get log output
  const logText = await page.evaluate(() => {
    return document.getElementById('log')?.innerHTML || '';
  });

  // Parse log HTML to text
  const logLines = logText.split('<div>').map(l => l.replace(/<\/div>/g, '').trim()).filter(Boolean);

  console.log('\n=== Console Log ===');
  logs.slice(-30).forEach(l => console.log(l));

  console.log('\n=== Debug Log ===');
  logLines.slice(-30).forEach(l => console.log(l));

  await browser.close();
})();
